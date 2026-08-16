import SwiftUI
import WidgetKit

/// Tasks and Focus in one tile — a third widget alongside `TodayWidget` and
/// `FocusWidget`, not a replacement for either. Read-only and tap-to-open,
/// same posture as both of those.
///
/// The view itself lives in Shared; this file is just the WidgetKit glue.
struct CombinedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.combined, provider: CombinedProvider()) { entry in
            CombinedWidgetView(entry: entry)
                .widgetURL(URL(string: "ontrack://today"))
                .containerBackground(for: .widget) { PaperBackground() }
                .dynamicTypeSize(...DynamicTypeSize.inkWidgetMaxDynamicTypeSize)
        }
        .configurationDisplayName("Tasks & Focus")
        .description("Late/today counts and the running timer, in one tile.")
        .supportedFamilies([.systemMedium])
    }
}

struct CombinedProvider: TimelineProvider {
    func placeholder(in context: Context) -> CombinedEntry {
        CombinedSampleData.entry
    }

    func getSnapshot(in context: Context, completion: @escaping (CombinedEntry) -> Void) {
        // Same "show real data if there is any" reasoning as the other two
        // providers — the gallery preview should look like an actual board,
        // not a stock demo, whenever there's something real to show.
        let tasks = WidgetSnapshotStore.read()
        let (tracks, sessions) = FocusWidgetSnapshotStore.read()
        if tasks.isEmpty && tracks.isEmpty {
            completion(CombinedSampleData.entry)
        } else {
            completion(CombinedEntry(date: Date(), tasks: tasks, tracks: tracks, todaysSessions: sessions, active: ActiveFocusRecovery.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CombinedEntry>) -> Void) {
        let tasks = WidgetSnapshotStore.read()
        let (tracks, sessions) = FocusWidgetSnapshotStore.read()
        let entry = CombinedEntry(date: Date(), tasks: tasks, tracks: tracks, todaysSessions: sessions, active: ActiveFocusRecovery.load())
        // Same 15-minute fallback as Today and Focus — a real change pushes
        // its own reload via WidgetCenter; this only exists so a task or a
        // session doesn't silently drift stale if that reload never fires.
        let nextTick = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextTick)))
    }
}

#Preview("Medium", as: .systemMedium) {
    CombinedWidget()
} timeline: {
    CombinedSampleData.entry
}
