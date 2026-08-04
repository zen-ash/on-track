#if DEBUG
import Foundation

/// Sample list for screenshots and previews. Launch with the `-seedDemo`
/// argument (Xcode: Product → Scheme → Edit Scheme → Arguments) to fill an empty
/// list. Never runs in release builds, and never overwrites real tasks.
enum DemoSeed {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedDemo")
    }

    static func tasks() -> [TaskItem] {
        let calendar = Calendar.current
        let now = Date()

        func at(days: Int, hour: Int? = nil) -> Date {
            let day = calendar.date(byAdding: .day, value: days, to: now) ?? now
            guard let hour else { return calendar.startOfDay(for: day).addingTimeInterval(9 * 3600) }
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }

        var index = 0.0
        func next() -> Double { index += 1; return index }

        return [
            TaskItem(
                title: "Send the invoice to Meridian",
                status: .open, priority: 3, dueAt: at(days: -2), hasTime: false,
                tags: ["work"], sortIndex: next(), source: .voice
            ),
            TaskItem(
                title: "Book the dentist",
                status: .open, priority: 1, dueAt: at(days: -1), hasTime: false,
                sortIndex: next(), source: .text
            ),
            TaskItem(
                title: "Ship the auth rewrite",
                notes: "Blocked on the migration review.",
                status: .open, priority: 3, dueAt: at(days: 0, hour: 17), hasTime: true,
                tags: ["work", "deep"], estimateMinutes: 180, energy: .high,
                sortIndex: next(), source: .voice
            ),
            TaskItem(
                title: "Gym",
                status: .open, dueAt: at(days: 0, hour: 7), hasTime: true,
                recurrence: "FREQ=WEEKLY;BYDAY=MO,WE,FR",
                tags: ["health"], sortIndex: next(), source: .voice
            ),
            TaskItem(
                title: "Reply to Priya about the weekend",
                status: .open, priority: 2, dueAt: at(days: 0), sortIndex: next(), source: .text
            ),
            TaskItem(
                title: "Pay rent",
                status: .open, priority: 2, dueAt: at(days: 3), hasTime: false,
                recurrence: "FREQ=MONTHLY", sortIndex: next(), source: .voice
            ),
            TaskItem(
                title: "Plan the trip to Lisbon",
                status: .open, dueAt: at(days: 9), tags: ["life"], sortIndex: next(), source: .ai
            ),
            TaskItem(
                title: "Clear the inbox",
                status: .done, dueAt: at(days: 0), sortIndex: next(),
                completedAt: now.addingTimeInterval(-3600), source: .text
            ),
            TaskItem(
                title: "Stand-up notes",
                status: .done, dueAt: at(days: 0), sortIndex: next(),
                completedAt: now.addingTimeInterval(-7200), source: .voice
            )
        ]
    }
}
#endif
