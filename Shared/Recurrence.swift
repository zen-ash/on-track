import Foundation

/// A deliberately small slice of RRULE — not the full spec, but enough for
/// what people actually say to a todo app: "every day", "every Monday",
/// "Mon/Wed/Fri", "every 2 weeks", "monthly on the 15th", "the last day of
/// the month", and "the last Friday" (or "last weekday") "of the month".
enum Recurrence {
    private static let dayCodes: [String: Int] = [
        // Calendar weekdays are 1-based from Sunday.
        "SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7
    ]

    private static let dayAbbreviations: [String: String] = [
        "SU": "Sun", "MO": "Mon", "TU": "Tue", "WE": "Wed", "TH": "Thu", "FR": "Fri", "SA": "Sat"
    ]

    static func components(of rule: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in rule.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            out[String(parts[0]).uppercased()] = String(parts[1]).uppercased()
        }
        return out
    }

    /// The next occurrence strictly after `date`, preserving time of day.
    static func nextDate(after date: Date, rule: String, calendar: Calendar = .current) -> Date? {
        let parts = components(of: rule)
        guard let freq = parts["FREQ"] else { return nil }
        let interval = Int(parts["INTERVAL"] ?? "1") ?? 1

        switch freq {
        case "DAILY":
            return calendar.date(byAdding: .day, value: interval, to: date)

        case "WEEKLY":
            guard let byDay = parts["BYDAY"] else {
                return calendar.date(byAdding: .weekOfYear, value: interval, to: date)
            }
            let targets = byDay.split(separator: ",").compactMap { dayCodes[String($0)] }.sorted()
            guard !targets.isEmpty else {
                return calendar.date(byAdding: .weekOfYear, value: interval, to: date)
            }
            // Walk forward day by day — clearer than modular arithmetic and the
            // bound is tiny.
            for offset in 1...14 {
                guard let candidate = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
                if targets.contains(calendar.component(.weekday, from: candidate)) {
                    return candidate
                }
            }
            return nil

        case "MONTHLY":
            if let setPos = Int(parts["BYSETPOS"] ?? ""), let byDay = parts["BYDAY"] {
                let weekdays = byDay.split(separator: ",").compactMap { dayCodes[String($0)] }
                return nextMonthlyBySetPos(after: date, weekdays: weekdays, setPos: setPos, interval: interval, calendar: calendar)
            }
            if let monthDay = Int(parts["BYMONTHDAY"] ?? "") {
                return nextMonthlyByMonthDay(after: date, monthDay: monthDay, interval: interval, calendar: calendar)
            }
            // No day rule: preserve whatever day of the month `date` already has.
            return calendar.date(byAdding: .month, value: interval, to: date)

        case "YEARLY":
            return calendar.date(byAdding: .year, value: interval, to: date)

        default:
            return nil
        }
    }

    /// The first occurrence on or after `date` — unlike `nextDate(after:)`,
    /// today counts. Used when a recurring task is created with no start date.
    static func firstOccurrence(onOrAfter date: Date, rule: String, calendar: Calendar = .current) -> Date {
        let parts = components(of: rule)

        if parts["FREQ"] == "WEEKLY", let byDay = parts["BYDAY"] {
            let targets = byDay.split(separator: ",").compactMap { dayCodes[String($0)] }
            guard !targets.isEmpty else { return date }
            for offset in 0...7 {
                guard let candidate = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
                if targets.contains(calendar.component(.weekday, from: candidate)) {
                    return candidate
                }
            }
            return date
        }

        if parts["FREQ"] == "MONTHLY", let setPos = Int(parts["BYSETPOS"] ?? ""), let byDay = parts["BYDAY"] {
            let weekdays = byDay.split(separator: ",").compactMap { dayCodes[String($0)] }
            if let thisMonth = nthWeekdayMatch(weekdays: weekdays, setPos: setPos, in: date, timeOf: date, calendar: calendar),
               calendar.startOfDay(for: thisMonth) >= calendar.startOfDay(for: date) {
                return thisMonth
            }
            if let nextMonth = calendar.date(byAdding: .month, value: 1, to: date),
               let candidate = nthWeekdayMatch(weekdays: weekdays, setPos: setPos, in: nextMonth, timeOf: date, calendar: calendar) {
                return candidate
            }
            return date
        }

        if parts["FREQ"] == "MONTHLY", let monthDay = Int(parts["BYMONTHDAY"] ?? "") {
            if let thisMonth = settingDay(monthDay, in: date, calendar: calendar),
               calendar.startOfDay(for: thisMonth) >= calendar.startOfDay(for: date) {
                return thisMonth
            }
            if let nextMonth = calendar.date(byAdding: .month, value: 1, to: date),
               let candidate = settingDay(monthDay, in: nextMonth, calendar: calendar) {
                return candidate
            }
            return date
        }

        // Daily and yearly rules, and a bare monthly rule, can all start today.
        return date
    }

    /// Human summary for the row stamp: "MON/WED/FRI", "daily", "every 2
    /// weeks", "the 15th", "last day", "last Fri", "last weekday".
    static func describe(_ rule: String) -> String {
        let parts = components(of: rule)
        guard let freq = parts["FREQ"] else { return "repeats" }
        let interval = Int(parts["INTERVAL"] ?? "1") ?? 1

        if freq == "MONTHLY", let setPos = Int(parts["BYSETPOS"] ?? ""), let byDay = parts["BYDAY"] {
            return monthlyBySetPosLabel(setPos: setPos, byDay: byDay, interval: interval)
        }
        if freq == "MONTHLY", let monthDay = Int(parts["BYMONTHDAY"] ?? "") {
            return monthlyByMonthDayLabel(monthDay: monthDay, interval: interval)
        }
        if let byDay = parts["BYDAY"], freq == "WEEKLY" {
            let names = byDay.split(separator: ",").compactMap { dayAbbreviations[String($0)] }.joined(separator: "/")
            return interval > 1 ? "\(names), every \(interval) wks" : names
        }

        switch (freq, interval) {
        case ("DAILY", 1): return "daily"
        case ("WEEKLY", 1): return "weekly"
        case ("MONTHLY", 1): return "monthly"
        case ("YEARLY", 1): return "yearly"
        case ("DAILY", let n): return "every \(n) days"
        case ("WEEKLY", let n): return "every \(n) weeks"
        case ("MONTHLY", let n): return "every \(n) months"
        case ("YEARLY", let n): return "every \(n) years"
        default: return "repeats"
        }
    }

    // MARK: - Monthly: Nth/last weekday(s) — BYSETPOS + BYDAY

    /// Walks forward month by month (bounded, since every month has a match
    /// for any realistic BYSETPOS) until it finds this month's Nth/last
    /// weekday occurrence — which, since it always advances at least one
    /// full month first, is always after `date` on the first try.
    private static func nextMonthlyBySetPos(after date: Date, weekdays: [Int], setPos: Int, interval: Int, calendar: Calendar) -> Date? {
        guard !weekdays.isEmpty, setPos != 0 else { return nil }

        // `date` is normally already a valid occurrence — the previous due
        // date — in which case this month's own match is `date` itself and
        // never qualifies. But it isn't *guaranteed* to be one: a recurring
        // task's due date can be hand-edited to an arbitrary day. Checking
        // this month first means that doesn't skip straight past an
        // occurrence still ahead of it.
        if let thisMonth = nthWeekdayMatch(weekdays: weekdays, setPos: setPos, in: date, timeOf: date, calendar: calendar),
           thisMonth > date {
            return thisMonth
        }

        var cursor = date
        for _ in 0..<24 {
            guard let advancedMonth = calendar.date(byAdding: .month, value: interval, to: cursor) else { return nil }
            if let candidate = nthWeekdayMatch(weekdays: weekdays, setPos: setPos, in: advancedMonth, timeOf: date, calendar: calendar),
               candidate > date {
                return candidate
            }
            cursor = advancedMonth
        }
        return nil
    }

    /// Every date in the month containing `referenceDate` whose weekday is
    /// in `weekdays`, sorted ascending and indexed by `setPos` — 1-based from
    /// the front if positive, from the back if negative (RRULE's BYSETPOS).
    /// `weekdays` holding all five weekdays plus `setPos == -1` is "the last
    /// weekday of the month".
    private static func nthWeekdayMatch(weekdays: [Int], setPos: Int, in referenceDate: Date, timeOf sourceDate: Date, calendar: Calendar) -> Date? {
        guard let monthRange = calendar.range(of: .day, in: .month, for: referenceDate),
              let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate)) else {
            return nil
        }

        let matches: [Date] = monthRange.compactMap { day in
            guard let candidate = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) else { return nil }
            return weekdays.contains(calendar.component(.weekday, from: candidate)) ? candidate : nil
        }
        guard !matches.isEmpty else { return nil }

        let index = setPos > 0 ? setPos - 1 : matches.count + setPos
        guard matches.indices.contains(index) else { return nil }

        let time = calendar.dateComponents([.hour, .minute, .second], from: sourceDate)
        return calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: time.second ?? 0, of: matches[index])
    }

    private static func monthlyBySetPosLabel(setPos: Int, byDay: String, interval: Int) -> String {
        let weekdays = byDay.split(separator: ",").compactMap { dayAbbreviations[String($0)] }
        let dayLabel = weekdays.count >= 5 ? "weekday" : weekdays.joined(separator: "/")
        let position: String
        switch setPos {
        case -1: position = "last"
        case 1: position = "1st"
        case 2: position = "2nd"
        case 3: position = "3rd"
        case let n where n > 0: position = "\(n)th"
        default: position = "\(-setPos)-to-last"
        }
        let base = "\(position) \(dayLabel)"
        return interval > 1 ? "\(base), every \(interval) mo" : "\(base)/mo"
    }

    // MARK: - Monthly: a specific day of the month — BYMONTHDAY

    /// `day` follows RRULE: positive counts from the start of the month,
    /// negative counts from the end (-1 is the last day). Out-of-range days
    /// — "the 31st" landing on February — clamp to the month's last day
    /// rather than skipping the month entirely: for a todo app, silently
    /// dropping a whole month of "pay rent" risks a missed bill, and a
    /// reminder three days early is a much smaller cost than that.
    private static func nextMonthlyByMonthDay(after date: Date, monthDay: Int, interval: Int, calendar: Calendar) -> Date? {
        // Same reasoning as nextMonthlyBySetPos: check this month's own
        // occurrence before assuming `date` already passed it.
        if let thisMonth = settingDay(monthDay, in: date, calendar: calendar), thisMonth > date {
            return thisMonth
        }
        var cursor = date
        for _ in 0..<24 {
            guard let advanced = calendar.date(byAdding: .month, value: interval, to: cursor) else { return nil }
            if let candidate = settingDay(monthDay, in: advanced, calendar: calendar), candidate > date {
                return candidate
            }
            cursor = advanced
        }
        return nil
    }

    private static func settingDay(_ day: Int, in date: Date, calendar: Calendar) -> Date? {
        guard day != 0, let range = calendar.range(of: .day, in: .month, for: date) else { return nil }
        let daysInMonth = range.count
        let targetDay = day > 0 ? min(day, daysInMonth) : max(daysInMonth + day + 1, 1)

        // `date(bySetting: .day, ...)` resets the time to midnight whenever
        // the day actually has to move, rather than only when it's already
        // at that value — not what "trying to keep lower components the
        // same" suggests. Rebuilding the date explicitly from components
        // carries hour/minute/second across unconditionally instead.
        var components = calendar.dateComponents([.year, .month, .hour, .minute, .second], from: date)
        components.day = targetDay
        return calendar.date(from: components)
    }

    private static func monthlyByMonthDayLabel(monthDay: Int, interval: Int) -> String {
        let base = monthDay == -1 ? "last day" : "the \(ordinal(abs(monthDay)))"
        return interval > 1 ? "\(base), every \(interval) mo" : "\(base)/mo"
    }

    private static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11, _), (12, _), (13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}
