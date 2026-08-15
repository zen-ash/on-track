import Foundation

/// The bridge between the app and the widget.
///
/// The widget extension is a separate process — it can't see `AppModel` or
/// call into Supabase with the app's session, and shouldn't need to. Instead
/// the app writes a small, capped snapshot of the list to the App Group
/// container every time `tasks` changes, and the widget just reads that file.
///
/// The snapshot holds full `TaskItem` values rather than pre-computed counts
/// on purpose: "late" and "today" depend on the clock at *render* time, not
/// capture time, so the widget re-derives them itself from `isOverdue` /
/// `isDueToday` — the same computed properties the app uses — rather than
/// trusting a label baked in whenever the app last happened to write.
enum WidgetSnapshotStore {
    private static let filename = "widget-snapshot.json"
    /// Plenty for a small/medium widget's use, and keeps the file — which gets
    /// rewritten on every list change — small and quick to write.
    private static let cap = 40

    private static var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(filename)
    }

    /// Called by the app after any change to the list. Silently does nothing if
    /// the App Group isn't reachable (e.g. entitlements not yet provisioned) —
    /// the widget just shows its empty state in that case, not a crash.
    static func write(_ tasks: [TaskItem]) {
        guard let fileURL else { return }
        let snapshot = tasks
            .filter { $0.parentId == nil }
            .inWorkingOrder()
            .prefix(cap)
        guard let data = try? JSONCoding.encoder.encode(Array(snapshot)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Called by the widget. Never throws — a missing or unreadable snapshot
    /// just means an empty list, which the widget renders as its own
    /// "nothing yet" state rather than an error.
    static func read() -> [TaskItem] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONCoding.decoder.decode([TaskItem].self, from: data)) ?? []
    }
}
