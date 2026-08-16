import Foundation

/// The Focus counterpart to `WidgetSnapshotStore`. `ActiveFocusState`
/// already lives in the shared App Group suite and covers "what's running
/// right now" — this covers the one thing that doesn't fit there: today's
/// totals, which need every track and every session started today, not
/// just the live one. The widget still never touches the network or a real
/// `FocusStore` — it only ever reads this file.
enum FocusWidgetSnapshotStore {
    private static let filename = "focus-widget-snapshot.json"

    private struct Snapshot: Codable {
        var tracks: [FocusTrack]
        var todaysSessions: [FocusSession]
    }

    private static var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(filename)
    }

    /// Called by the app (and by the Siri Focus intents) after any change to
    /// tracks or today's sessions. Silently does nothing if the App Group
    /// isn't reachable, same as `WidgetSnapshotStore.write` — the widget
    /// just shows its own empty state rather than crashing.
    static func write(tracks: [FocusTrack], todaysSessions: [FocusSession]) {
        guard let fileURL else { return }
        let snapshot = Snapshot(tracks: tracks, todaysSessions: todaysSessions)
        guard let data = try? JSONCoding.encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func read() -> (tracks: [FocusTrack], todaysSessions: [FocusSession]) {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONCoding.decoder.decode(Snapshot.self, from: data) else {
            return ([], [])
        }
        return (snapshot.tracks, snapshot.todaysSessions)
    }
}
