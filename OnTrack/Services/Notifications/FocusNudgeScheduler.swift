import Foundation
import UserNotifications

/// "Still going?" — the one case Focus otherwise says nothing about: a
/// session left running for hours because you got up and forgot about it,
/// not because you're actually still at it. A local notification, not
/// anything that needs the app or a server, so it fires whether the app is
/// open, backgrounded, or was force-quit an hour ago.
///
/// Standalone by design, the same reasoning as `FocusIntentWriter` and
/// `ActiveFocusRecovery`: called from both AppModel (the in-app start/pause/
/// resume/stop path) and FocusIntentWriter (the Siri path), neither of which
/// can assume the other one is what's running.
enum FocusNudgeScheduler {
    private static let identifier = "focus-still-going-nudge"
    /// How long a session has to run *continuously* — not accumulated
    /// across pauses — before this fires. A pause-and-resume rhythm across
    /// a whole afternoon is normal use; one unbroken multi-hour stretch is
    /// what actually suggests the stop button got forgotten, not the timer.
    static let threshold: TimeInterval = 2 * 3600

    /// Schedules (or reschedules) the nudge for `runningSince + threshold`.
    /// Safe to call whenever a session starts running, including a resume —
    /// always clears any existing pending nudge first, so there's never more
    /// than one in flight.
    static func schedule(trackName: String, runningSince: Date) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let fireDate = runningSince.addingTimeInterval(threshold)
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0 else { return } // already past the threshold; nothing to schedule

        var settings = await center.notificationSettings()
        // Same "ask when there's actually something to ask about" posture
        // Reminders.requestAuthorizationIfNeeded() takes, not asked proactively.
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            settings = await center.notificationSettings()
        }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        // Registered here too, not just from Reminders.sync — a Focus-only
        // user who's never had a due task wouldn't otherwise have this
        // category registered at all by the time a session actually starts.
        NotificationDelegate.registerCategories()

        let content = UNMutableNotificationContent()
        content.title = "Still going?"
        content.body = "\(trackName) has been running for 2 hours straight."
        content.sound = .default
        content.categoryIdentifier = NotificationDelegate.focusNudgeCategoryIdentifier

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Called on pause and stop — paused means you're clearly still around,
    /// and stopped means there's nothing left to nudge about.
    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
