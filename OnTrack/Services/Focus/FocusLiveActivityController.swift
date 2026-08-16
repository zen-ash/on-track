import ActivityKit
import Foundation

/// Starts, updates, and ends the Focus Live Activity — the Lock Screen and
/// Dynamic Island glance at whatever's currently running. Same standalone
/// shape as `FocusNudgeScheduler`: called from both AppModel's in-app path
/// and `FocusIntentWriter`'s Siri path, neither of which can assume the
/// other one already handled it.
///
/// `Activity.request` can throw — most commonly because the person has Live
/// Activities turned off in Settings, or because the system declines a
/// request made outside the foreground. Every call here is best-effort:
/// Focus itself works exactly the same either way, this is purely an extra
/// glance layered on top.
enum FocusLiveActivityController {
    /// Starts a new activity for `state`, ending any existing one first —
    /// there's never more than one Focus session running at a time, so
    /// there's never more than one activity either.
    static func start(trackName: String, state: ActiveFocusState) async {
        await end()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = FocusActivityAttributes(trackName: trackName)
        let content = ActivityContent(state: contentState(for: state), staleDate: nil)
        _ = try? Activity.request(attributes: attributes, content: content)
    }

    /// Pause/resume only change the numbers, never the track — same
    /// activity, new content.
    static func update(state: ActiveFocusState) async {
        for activity in Activity<FocusActivityAttributes>.activities {
            await activity.update(ActivityContent(state: contentState(for: state), staleDate: nil))
        }
    }

    /// Ends whatever's running, immediately — a session that just stopped
    /// has nothing left to show.
    static func end() async {
        for activity in Activity<FocusActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Covers a relaunch that finds a session already running with nothing
    /// tracking it on the Lock Screen — this feature shipping after a
    /// session was already in progress, or the system having reclaimed the
    /// activity on its own. Does nothing if one's already attached, so this
    /// is safe to call on every `loadFocus()` rather than only sometimes.
    static func reattachIfNeeded(trackName: String, state: ActiveFocusState) async {
        guard Activity<FocusActivityAttributes>.activities.isEmpty else { return }
        await start(trackName: trackName, state: state)
    }

    private static func contentState(for state: ActiveFocusState) -> FocusActivityAttributes.ContentState {
        FocusActivityAttributes.ContentState(accumulatedSeconds: state.accumulatedSeconds, runningSince: state.runningSince)
    }
}
