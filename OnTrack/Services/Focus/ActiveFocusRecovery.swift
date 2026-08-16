import Foundation

/// Crash/backgrounding-safe record of whatever Focus session is currently in
/// progress. Deliberately device-local — UserDefaults, not synced through
/// `FocusStore` — since a session started on this phone shouldn't try to
/// "resume" itself on another device.
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

    static func save(_ state: ActiveFocusState) {
        guard let data = try? JSONCoding.encoder.encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> ActiveFocusState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONCoding.decoder.decode(ActiveFocusState.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
