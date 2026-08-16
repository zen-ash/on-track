import Foundation
import UserNotifications

/// Bridges a tapped or actioned due-task notification back to a task.
///
/// UNUserNotificationCenterDelegate runs in-process for local notifications,
/// but there's still no reliable way to reach the one live AppModel instance
/// from a plain delegate object — it isn't part of the SwiftUI view tree, and
/// a cold launch can deliver the response before any view exists at all. So
/// this uses the same stash-and-consume shape as QuickCaptureBus rather than
/// inventing a second one: park what happened, let OnTrackApp pick it up
/// once it's actually running.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let categoryIdentifier = "TASK_DUE"
    static let doneActionIdentifier = "TASK_DONE"
    static let snoozeActionIdentifier = "TASK_SNOOZE"

    /// Without this, a due-task notification is silently swallowed while the
    /// app is already open — UNUserNotificationCenter only shows one in the
    /// foreground if the delegate explicitly asks it to.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Handles a plain tap and both custom actions the same way: figure out
    /// which task and what was asked for, stash it, and let it foreground —
    /// both actions are declared `.foreground` on purpose, so the real
    /// mutation always goes through AppModel's normal methods (toggleDone,
    /// snooze) instead of a second, easily-drifting copy of that logic
    /// running headless in the background.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let idString = response.notification.request.content.userInfo["taskId"] as? String,
              let taskId = UUID(uuidString: idString) else { return }

        let kind: PendingNotificationAction.Kind
        switch response.actionIdentifier {
        case Self.doneActionIdentifier: kind = .markDone
        case Self.snoozeActionIdentifier: kind = .snooze
        default: kind = .open // UNNotificationDefaultActionIdentifier — a plain tap
        }
        PendingNotificationAction.stash(taskId: taskId, kind: kind)
    }

    /// Registering is cheap and idempotent, so `Reminders.sync` just calls
    /// this every time rather than gating it behind first-launch state — an
    /// account that already granted permission in an earlier version of the
    /// app, before this existed, still needs it to run.
    static func registerCategories() {
        let done = UNNotificationAction(identifier: doneActionIdentifier, title: "Done", options: [.foreground])
        let snooze = UNNotificationAction(identifier: snoozeActionIdentifier, title: "Snooze 1 hour", options: [.foreground])
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [done, snooze],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

/// Same handoff shape as QuickCaptureBus, for the same reason: the delegate
/// can fire before any view — or AppModel itself — exists yet.
enum PendingNotificationAction {
    enum Kind: String {
        case open, markDone, snooze
    }

    private static let taskIdKey = "pendingNotificationTaskId"
    private static let kindKey = "pendingNotificationKind"

    static func stash(taskId: UUID, kind: Kind) {
        UserDefaults.standard.set(taskId.uuidString, forKey: taskIdKey)
        UserDefaults.standard.set(kind.rawValue, forKey: kindKey)
    }

    /// Reads and clears in one go so the same tap can't be replayed twice.
    static func consume() -> (taskId: UUID, kind: Kind)? {
        guard let idString = UserDefaults.standard.string(forKey: taskIdKey),
              let taskId = UUID(uuidString: idString),
              let kindString = UserDefaults.standard.string(forKey: kindKey),
              let kind = Kind(rawValue: kindString) else { return nil }
        UserDefaults.standard.removeObject(forKey: taskIdKey)
        UserDefaults.standard.removeObject(forKey: kindKey)
        return (taskId, kind)
    }
}
