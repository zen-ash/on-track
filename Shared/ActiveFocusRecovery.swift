import Foundation

/// Crash/backgrounding-safe record of whatever Focus session is currently in
/// progress. Lives in the App Group's shared UserDefaults suite, not just
/// `.standard` — the app, the Siri intents, and the widget extension all
/// read and write this exact record, so whichever one touched it last is
/// what's true the next time any of them looks. Still device-local in
/// spirit: a session started on this phone was never meant to "resume"
/// itself on another device, and nothing here syncs through `FocusStore`.
///
/// Elapsed time is never held in a running counter: it's always
/// `accumulatedSeconds + (now - runningSince)`, computed on demand, so a
/// force-quit or a dead battery loses nothing and needs no background
/// execution to survive.
struct ActiveFocusState: Codable, Equatable, Sendable {
    var sessionId: UUID
    var trackId: UUID
    var startedAt: Date
    /// Seconds already banked from earlier run segments of this session.
    var accumulatedSeconds: Int
    /// Non-nil while actively ticking; nil while paused.
    var runningSince: Date?

    var isPaused: Bool { runningSince == nil }

    func elapsedSeconds(at now: Date = Date()) -> Int {
        guard let runningSince else { return accumulatedSeconds }
        return accumulatedSeconds + max(0, Int(now.timeIntervalSince(runningSince)))
    }
}

enum ActiveFocusRecovery {
    private static let key = "activeFocusState"

    /// Falls back to `.standard` only if the App Group suite is somehow
    /// unreachable (entitlements not yet provisioned) — the same
    /// "degrade, don't crash" posture `WidgetSnapshotStore` takes when its
    /// container isn't reachable, just for UserDefaults instead of a file.
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    static func save(_ state: ActiveFocusState) {
        guard let data = try? JSONCoding.encoder.encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    static func load() -> ActiveFocusState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONCoding.decoder.decode(ActiveFocusState.self, from: data)
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }
}
