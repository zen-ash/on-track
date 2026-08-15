import Foundation

/// A deliberately small slice of RRULE — enough for "every day", "every Monday",
/// "Mon/Wed/Fri", and "monthly", which covers essentially everything people
/// actually speak at a todo app.
enum Recurrence {
    private static let dayCodes: [String: Int] = [
        // Calendar weekdays are 1-based from Sunday.
        "SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7
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
        guard parts["FREQ"] == "WEEKLY", let byDay = parts["BYDAY"] else {
            // Daily, monthly and yearly rules can all start today.
            return date
        }
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

    /// Human summary for the row stamp: "MON/WED/FRI", "DAILY", "MONTHLY".
    static func describe(_ rule: String) -> String {
        let parts = components(of: rule)
        guard let freq = parts["FREQ"] else { return "repeats" }
        if let byDay = parts["BYDAY"], freq == "WEEKLY" {
            let names = ["SU": "Sun", "MO": "Mon", "TU": "Tue", "WE": "Wed", "TH": "Thu", "FR": "Fri", "SA": "Sat"]
            return byDay.split(separator: ",").compactMap { names[String($0)] }.joined(separator: "/")
        }
        switch freq {
        case "DAILY": return "daily"
        case "WEEKLY": return "weekly"
        case "MONTHLY": return "monthly"
        case "YEARLY": return "yearly"
        default: return "repeats"
        }
    }
}
