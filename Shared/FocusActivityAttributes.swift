import ActivityKit
import Foundation

/// Drives the Lock Screen and Dynamic Island presentation of whatever Focus
/// session is currently running — a glance at the timer that doesn't need
/// unlocking the phone to check.
///
/// `trackName` is fixed for the life of the activity rather than looked up
/// live: a session never changes track mid-flight, so there's nothing to
/// keep in sync there.
///
/// Read-only, tap to open — same posture as the Home Screen widget, and the
/// same reason: a button here would run through `Button(intent:)`, which
/// executes in the widget extension's own process, and that process doesn't
/// share Keychain access with the app (no `keychain-access-groups`
/// entitlement configured). A Stop tap could silently resolve against the
/// wrong store for a signed-in account, so this stays glance-only until that
/// gap is actually closed.
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Seconds already banked from earlier run segments of this session.
        var accumulatedSeconds: Int
        /// Non-nil while actively ticking; nil while paused — same shape as
        /// `ActiveFocusState`, deliberately, so the two never drift apart on
        /// what "running" means.
        var runningSince: Date?
    }

    let trackName: String
}
