import SwiftUI
import WidgetKit

/// The Home Screen widget: "N late, N today" at a glance, in the same ink on
/// paper as the app. Read-only and non-interactive on purpose — tapping opens
/// the app rather than trying to reproduce swipe-to-complete inside a
/// periodically-snapshotted widget, where a custom press animation or haptic
/// wouldn't mean anything anyway.
///
/// The view itself (`TodayWidgetView`) lives in Shared — this file is just the
/// WidgetKit-specific glue: the configuration and the timeline provider.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.today, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .widgetURL(URL(string: "ontrack://today"))
                .containerBackground(for: .widget) { PaperBackground() }
        }
        .configurationDisplayName("Today")
        .description("Late and due-today counts, at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), tasks: TodaySampleData.tasks)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        // The gallery preview gets real data if there is any, so what people
        // see while choosing a widget looks like their actual list.
        let tasks = WidgetSnapshotStore.read()
        completion(TodayEntry(date: Date(), tasks: tasks.isEmpty ? TodaySampleData.tasks : tasks))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let tasks = WidgetSnapshotStore.read()
        let entry = TodayEntry(date: Date(), tasks: tasks)
        // The app pushes a reload on every real change via WidgetCenter. This
        // is only the fallback — it re-renders on a plain clock tick so a task
        // due at 5pm still flips into "late" at 5:01pm even if the app never
        // reopens to trigger it, since isOverdue/isDueToday key off "now".
        let nextTick = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextTick)))
    }
}

#Preview("Small", as: .systemSmall) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, tasks: TodaySampleData.tasks)
}

#Preview("Medium", as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, tasks: TodaySampleData.tasks)
}
