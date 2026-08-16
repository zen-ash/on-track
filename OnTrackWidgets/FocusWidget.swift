import SwiftUI
import WidgetKit

/// The Home Screen widget for Focus: what's running right now, or today's
/// totals if nothing is. Read-only and tap-to-open, same posture as
/// `TodayWidget` — see `FocusWidgetView`'s doc comment for why interactive
/// buttons aren't here yet.
///
/// The view itself lives in Shared; this file is just the WidgetKit glue.
struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.focus, provider: FocusProvider()) { entry in
            FocusWidgetView(entry: entry)
                .widgetURL(URL(string: "ontrack://focus"))
                .containerBackground(for: .widget) { PaperBackground() }
                .dynamicTypeSize(...DynamicTypeSize.inkWidgetMaxDynamicTypeSize)
        }
        .configurationDisplayName("Focus")
        .description("What's running right now, and today's totals per track.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FocusProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusEntry {
        FocusEntry(date: Date(), tracks: FocusSampleData.tracks, todaysSessions: FocusSampleData.sessions, active: FocusSampleData.active)
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusEntry) -> Void) {
        // The gallery preview gets real data if there is any, matching how
        // TodayProvider does it — what someone sees while choosing this
        // widget should look like their actual tracks, not a stock demo.
        let (tracks, sessions) = FocusWidgetSnapshotStore.read()
        if tracks.isEmpty {
            completion(FocusEntry(date: Date(), tracks: FocusSampleData.tracks, todaysSessions: FocusSampleData.sessions, active: FocusSampleData.active))
        } else {
            completion(FocusEntry(date: Date(), tracks: tracks, todaysSessions: sessions, active: ActiveFocusRecovery.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusEntry>) -> Void) {
        let (tracks, sessions) = FocusWidgetSnapshotStore.read()
        let entry = FocusEntry(date: Date(), tracks: tracks, todaysSessions: sessions, active: ActiveFocusRecovery.load())
        // The app (and the Siri Focus intents) push a reload on every real
        // change via WidgetCenter. This is only the fallback, matching
        // TodayProvider's own 15-minute safety net — a live running session
        // ticks on its own via Text(_:style:.timer) either way, so this
        // doesn't need to be frequent to stay honest.
        let nextTick = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextTick)))
    }
}

#Preview("Small", as: .systemSmall) {
    FocusWidget()
} timeline: {
    FocusEntry(date: .now, tracks: FocusSampleData.tracks, todaysSessions: FocusSampleData.sessions, active: FocusSampleData.active)
}

#Preview("Medium", as: .systemMedium) {
    FocusWidget()
} timeline: {
    FocusEntry(date: .now, tracks: FocusSampleData.tracks, todaysSessions: FocusSampleData.sessions, active: FocusSampleData.active)
}
