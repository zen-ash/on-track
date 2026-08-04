import Foundation
import UserNotifications

/// Local notifications for anything with a due date. Rescheduled wholesale on
/// every change — the list is small and it's the only way to stay consistent
/// with a store that can also be edited by the model on the server.
actor Reminders {
    private var didRequestAuthorization = false

    func requestAuthorizationIfNeeded() async {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func sync(with tasks: [TaskItem]) async {
        let center = UNUserNotificationCenter.current()

        // iOS caps pending local notifications at 64; take the soonest.
        let due = tasks
            .filter { $0.status == .open && $0.dueAt != nil && $0.dueAt! > Date() }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            .prefix(60)

        var settings = await center.notificationSettings()
        // Ask the first time there's actually something to remind about, rather
        // than throwing a permission prompt at someone who just opened the app.
        if settings.authorizationStatus == .notDetermined {
            guard !due.isEmpty else { return }
            await requestAuthorizationIfNeeded()
            settings = await center.notificationSettings()
        }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        center.removeAllPendingNotificationRequests()

        for task in due {
            guard let dueAt = task.dueAt else { continue }
            let content = UNMutableNotificationContent()
            content.title = task.title
            content.body = task.isRecurring ? Recurrence.describe(task.recurrence ?? "") : "Due now."
            content.sound = .default
            content.userInfo = ["taskId": task.id.uuidString]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueAt
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
