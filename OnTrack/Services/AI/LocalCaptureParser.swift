import Foundation

/// On-device capture. Deliberately dumb compared to the model, but it means
/// speaking a task always produces a task — no backend, no network, no excuses.
/// Also used as the fallback when the model call fails mid-capture.
///
/// The order of operations matters: every element it recognises is *removed*
/// from the text as it goes, so what's left over is the title. Recognising
/// "every Monday" but leaving it in the title is worse than not recognising it.
struct LocalCaptureParser: AIService, Sendable {
    var isFullyCapable: Bool { false }

    func capture(text: String, existingTitles: [String]) async throws -> CaptureResult {
        let fragments = Self.split(text)
        let tasks = fragments.compactMap { Self.parseOne($0) }
        guard !tasks.isEmpty else {
            return CaptureResult(tasks: [], reply: "Didn't catch a task in that.")
        }
        return CaptureResult(tasks: tasks, reply: nil)
    }

    func plan(tasks: [TaskItem], calendarBusy: [BusyBlock]) async throws -> DayPlan {
        // Heuristic stand-in: late work first, then today's, then whatever is
        // highest priority. No reasoning, just triage rules — so calendar
        // blocks aren't actually weighed against slots here the way the real
        // model weighs them. Worth saying so, rather than quietly ignoring
        // access the user explicitly granted.
        let open = tasks.filter { $0.status == .open && $0.parentId == nil }
        let ordered = open.inWorkingOrder()
        let chosen = Array(ordered.prefix(6))

        let items = chosen.enumerated().map { index, task in
            PlanItem(
                taskId: task.id,
                slot: task.isOverdue ? .now : (index < 3 ? .morning : .afternoon),
                reason: task.isOverdue ? "Overdue — clear it first." : "High on your list.",
                order: index
            )
        }

        let note = calendarBusy.isEmpty
            ? "Planned on-device. Connect the backend for real triage."
            : "Planned on-device — connect the backend to actually weigh today's \(calendarBusy.count) calendar block\(calendarBusy.count == 1 ? "" : "s") against it."

        return DayPlan(
            focus: chosen.first?.title ?? "Nothing pressing.",
            items: items,
            deferIds: [],
            note: note
        )
    }

    func chat(history: [ChatTurn], tasks: [TaskItem]) async throws -> ChatReply {
        throw AIError.unsupportedLocally("Chat")
    }

    func breakdown(task: TaskItem) async throws -> [String] {
        throw AIError.unsupportedLocally("Breaking tasks down")
    }

    // MARK: - Splitting

    /// One utterance can hold several tasks. Split only on strong boundaries —
    /// over-splitting mangles single tasks that merely contain "and".
    static func split(_ text: String) -> [String] {
        let separators = ["\n", ";", ", also ", " and also ", " and then ", ", then "]
        var parts = [text]
        for separator in separators {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 1 }
    }

    // MARK: - Parsing one task

    static func parseOne(_ raw: String) -> CapturedTask? {
        var working = raw

        let tags = extractTags(from: &working)
        let priority = extractPriority(from: &working)
        let recurrence = extractRecurrence(from: &working)
        let time = extractTimeOfDay(from: &working)
        var dueAt = extractDate(from: &working)

        // A recurring task with no stated date starts at its next occurrence.
        if let recurrence, dueAt == nil {
            dueAt = Recurrence.firstOccurrence(onOrAfter: Date(), rule: recurrence)
        }

        // Apply the stated time, or 9am so all-day tasks have somewhere to fire.
        if let due = dueAt {
            dueAt = Calendar.current.date(
                bySettingHour: time?.hour ?? 9,
                minute: time?.minute ?? 0,
                second: 0,
                of: due
            ) ?? due
        }

        let title = tidy(working)
        guard !title.isEmpty else { return nil }

        return CapturedTask(
            title: title,
            dueAt: dueAt,
            hasTime: time != nil,
            priority: priority,
            tags: tags,
            recurrence: recurrence
        )
    }

    // MARK: - Tags

    private static func extractTags(from text: inout String) -> [String] {
        var tags: [String] = []
        while let match = firstMatch(#"#([\p{L}0-9_-]+)"#, in: text) {
            if let captured = match.groups.first ?? nil {
                tags.append(captured.lowercased())
            }
            text.removeSubrange(match.range)
        }
        return tags
    }

    // MARK: - Priority

    private static func extractPriority(from text: inout String) -> Int {
        let lowered = text.lowercased()
        var priority = 0

        if lowered.contains("!!!") || lowered.range(of: #"\b(urgent|asap|critical|emergency)\b"#, options: [.regularExpression]) != nil {
            priority = 3
        } else if lowered.contains("!!") || lowered.range(of: #"\b(important|high priority)\b"#, options: [.regularExpression]) != nil {
            priority = 2
        } else if lowered.contains("!") {
            priority = 1
        }

        guard priority > 0 else { return 0 }

        // The words carried the meaning; they shouldn't survive into the title.
        removeAll(#"\b(urgent|asap|critical|emergency|important|high priority)\b"#, from: &text)
        removeAll(#"!+"#, from: &text)
        return priority
    }

    // MARK: - Recurrence

    private static let weekdayPattern =
        "(?:mondays?|mon|tuesdays?|tues|tue|wednesdays?|weds|wed|thursdays?|thurs|thu|fridays?|fri|saturdays?|sat|sundays?|sun)"

    private static let weekdayCodes: [(String, String)] = [
        ("monday", "MO"), ("mon", "MO"),
        ("tuesday", "TU"), ("tues", "TU"), ("tue", "TU"),
        ("wednesday", "WE"), ("weds", "WE"), ("wed", "WE"),
        ("thursday", "TH"), ("thurs", "TH"), ("thu", "TH"),
        ("friday", "FR"), ("fri", "FR"),
        ("saturday", "SA"), ("sat", "SA"),
        ("sunday", "SU"), ("sun", "SU")
    ]

    private static func extractRecurrence(from text: inout String) -> String? {
        let rule = detectRecurrence(in: text.lowercased())
        guard let rule else { return nil }

        // Strip the phrase that produced the rule, longest patterns first so
        // "every day" goes before a bare "every".
        removeAll(#"\b(every|each)\s+(single\s+)?(day|week|month|year)\b"#, from: &text)
        // The connector is optional: people say "every monday wednesday friday"
        // as often as "every monday, wednesday and friday". Leaving a day behind
        // is actively harmful — the date detector then reads it as a due date.
        removeAll(#"\b(every|each)\s+\#(weekdayPattern)(?:\s*(?:,|and|&|/)?\s*\#(weekdayPattern))*"#, from: &text)
        removeAll(#"\b(daily|weekly|monthly|yearly|annually)\b"#, from: &text)
        return rule
    }

    static func detectRecurrence(in lowered: String) -> String? {
        guard lowered.contains("every") || lowered.contains("daily")
                || lowered.contains("weekly") || lowered.contains("monthly")
                || lowered.contains("yearly") || lowered.contains("annually")
                || lowered.contains("each ") else { return nil }

        if lowered.contains("daily") || lowered.contains("every day") || lowered.contains("each day") {
            return "FREQ=DAILY"
        }
        if lowered.contains("monthly") || lowered.contains("every month") || lowered.contains("each month") {
            return "FREQ=MONTHLY"
        }
        if lowered.contains("yearly") || lowered.contains("annually") || lowered.contains("every year") {
            return "FREQ=YEARLY"
        }

        // Named days. Longest names are checked first so "sun" can't shadow
        // "sunday" and produce a duplicate.
        var days: [String] = []
        for (name, code) in weekdayCodes where lowered.contains(name) {
            if !days.contains(code) { days.append(code) }
        }
        if !days.isEmpty {
            // Preserve calendar order rather than the order they were spoken.
            let order = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
            days.sort { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
            return "FREQ=WEEKLY;BYDAY=" + days.joined(separator: ",")
        }
        if lowered.contains("weekly") || lowered.contains("every week") {
            return "FREQ=WEEKLY"
        }
        return nil
    }

    // MARK: - Time of day

    private struct TimeOfDay {
        var hour: Int
        var minute: Int
    }

    /// Pulled out *before* the date detector runs. Handling "at 4pm" separately
    /// means "tomorrow at 4pm" resolves correctly instead of relying on the
    /// detector to catch both halves in one match.
    private static func extractTimeOfDay(from text: inout String) -> TimeOfDay? {
        // 4pm · 4:30pm · at 7 a.m.
        if let match = firstMatch(#"\b(?:at\s+|@\s*)?(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)"#, in: text) {
            var hour = Int(match.groups[0] ?? "") ?? 0
            let minute = Int(match.groups[1] ?? "") ?? 0
            let meridiem = (match.groups[2] ?? "").lowercased()
            if meridiem.hasPrefix("p") && hour < 12 { hour += 12 }
            if meridiem.hasPrefix("a") && hour == 12 { hour = 0 }
            guard hour < 24, minute < 60 else { return nil }
            text.removeSubrange(match.range)
            return TimeOfDay(hour: hour, minute: minute)
        }

        // at 19:30
        if let match = firstMatch(#"\bat\s+(\d{1,2}):(\d{2})\b"#, in: text) {
            let hour = Int(match.groups[0] ?? "") ?? 0
            let minute = Int(match.groups[1] ?? "") ?? 0
            guard hour < 24, minute < 60 else { return nil }
            text.removeSubrange(match.range)
            return TimeOfDay(hour: hour, minute: minute)
        }

        // 5 o'clock
        if let match = firstMatch(#"\b(?:at\s+)?(\d{1,2})\s*o'?clock\b"#, in: text) {
            let hour = Int(match.groups[0] ?? "") ?? 0
            guard hour < 24 else { return nil }
            text.removeSubrange(match.range)
            return TimeOfDay(hour: hour, minute: 0)
        }

        if let match = firstMatch(#"\b(noon|midday|midnight)\b"#, in: text) {
            let word = (match.groups[0] ?? "").lowercased()
            text.removeSubrange(match.range)
            return TimeOfDay(hour: word == "midnight" ? 0 : 12, minute: 0)
        }

        return nil
    }

    // MARK: - Dates

    private static func extractDate(from text: inout String) -> Date? {
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = detector.matches(in: text, range: range).first,
               let matchRange = Range(match.range, in: text),
               let date = match.date {
                text.removeSubrange(matchRange)
                return date
            }
        }

        // "before the 5th", "on the 21st" — the system detector doesn't reliably
        // catch a bare day of the month, and it's a common way to say it.
        if let match = firstMatch(#"\b(?:by|before|on|due)?\s*the\s+(\d{1,2})(?:st|nd|rd|th)\b"#, in: text) {
            if let day = Int(match.groups[0] ?? ""), (1...31).contains(day) {
                text.removeSubrange(match.range)
                return nextDate(onDayOfMonth: day)
            }
        }

        return nil
    }

    /// The next time that day-of-month comes around — this month if it hasn't
    /// passed, otherwise next.
    private static func nextDate(onDayOfMonth day: Int) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month], from: now)
        components.day = day

        guard let thisMonth = calendar.date(from: components) else { return nil }
        if calendar.startOfDay(for: thisMonth) >= calendar.startOfDay(for: now) {
            return thisMonth
        }
        return calendar.date(byAdding: .month, value: 1, to: thisMonth)
    }

    // MARK: - Title clean-up

    /// Strips the scaffolding words people say out loud and normalises whatever
    /// spacing the removals left behind.
    static func tidy(_ input: String) -> String {
        var text = input
        let leadingNoise = [
            "remind me to ", "remind me ", "reminder to ", "remember to ",
            "i need to ", "i have to ", "i should ", "i want to ", "i must ",
            "add a task to ", "add task to ", "add a task ", "add task ",
            "make a note to ", "note to ", "todo ", "to do ", "please "
        ]

        var changed = true
        while changed {
            changed = false
            let lowered = text.lowercased()
            for noise in leadingNoise where lowered.hasPrefix(noise) {
                text = String(text.dropFirst(noise.count))
                changed = true
                break
            }
        }

        // Collapse whitespace left by removed date, time and tag spans.
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+([,.!?])"#, with: "$1", options: .regularExpression)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n,.;:-–/"))

        // Prepositions stranded by a removed date ("ship the rewrite by").
        // Looped, because removals can strand two in a row.
        let dangling = [" on", " at", " by", " before", " for", " due", " every", " each", " this", " next"]
        var trimming = true
        while trimming {
            trimming = false
            let lowered = text.lowercased()
            for suffix in dangling where lowered.hasSuffix(suffix) {
                text = String(text.dropLast(suffix.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n,.;:-–/"))
                trimming = true
                break
            }
        }

        guard let first = text.first else { return "" }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: - Regex helpers

    private struct RegexMatch {
        var range: Range<String.Index>
        /// Capture groups, 1-indexed in the pattern but 0-indexed here.
        var groups: [String?]
    }

    private static func firstMatch(_ pattern: String, in text: String) -> RegexMatch? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let matchRange = Range(match.range, in: text) else { return nil }

        var groups: [String?] = []
        if match.numberOfRanges > 1 {
            for index in 1..<match.numberOfRanges {
                if let groupRange = Range(match.range(at: index), in: text) {
                    groups.append(String(text[groupRange]))
                } else {
                    groups.append(nil)
                }
            }
        }
        return RegexMatch(range: matchRange, groups: groups)
    }

    private static func removeAll(_ pattern: String, from text: inout String) {
        text = text.replacingOccurrences(
            of: pattern,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}
