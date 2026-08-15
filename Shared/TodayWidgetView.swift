import SwiftUI
import WidgetKit

/// What the widget shows. Kept in Shared rather than the widget extension so
/// the main app can render this exact view — not a look-alike — in a debug
/// preview, which is the only practical way to check a widget's appearance
/// without dragging one onto a Home Screen by hand.
struct TodayEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskItem]
}

/// Placeholder content for the widget gallery and app previews, so the style
/// is visible even before real data exists.
enum TodaySampleData {
    static let tasks: [TaskItem] = [
        TaskItem(title: "Send the invoice", status: .open, priority: 3, dueAt: Date().addingTimeInterval(-86400), hasTime: false, sortIndex: 1),
        TaskItem(title: "Ship the rewrite", status: .open, dueAt: Date(), hasTime: true, sortIndex: 2),
        TaskItem(title: "Gym", status: .open, dueAt: Date(), hasTime: true, recurrence: "FREQ=WEEKLY;BYDAY=MO,WE,FR", sortIndex: 3),
    ]
}

// MARK: - Classification
// Mirrors AppModel's own openTasks/overdueTasks/todayTasks split. The snapshot
// already contains only open, top-level tasks (WidgetSnapshotStore filters
// that on write), so only the late/today split needs redoing here — and it's
// redone with the exact same TaskItem.isOverdue / isDueToday the app uses,
// not a re-derived approximation.

private extension Array where Element == TaskItem {
    var overdue: [TaskItem] { filter(\.isOverdue) }
    var dueToday: [TaskItem] { filter { !$0.isOverdue && ($0.isDueToday || $0.dueAt == nil) } }
}

// MARK: - View

struct TodayWidgetView: View {
    // WidgetKit's own `\.widgetFamily` is read-only from outside its actual
    // rendering, so it can't be injected via `.environment(...)` for a preview
    // hosted inside the main app. `forcedFamily` is that escape hatch: nil in
    // the real widget (where the environment value is correct), set explicitly
    // when this same view is rendered anywhere else.
    @Environment(\.widgetFamily) private var systemFamily
    let entry: TodayEntry
    var forcedFamily: WidgetFamily? = nil

    private var family: WidgetFamily { forcedFamily ?? systemFamily }

    private var ordered: [TaskItem] { entry.tasks.inWorkingOrder() }
    private var overdue: [TaskItem] { ordered.overdue }
    private var dueToday: [TaskItem] { ordered.dueToday }

    private var mood: MascotMood {
        // doneToday is always 0 here: the snapshot only holds open tasks, so
        // there's nothing to honestly call "pleased" or "triumphant" about —
        // this restrains the widget to moods it actually has grounds for.
        MascotVoice.mood(overdue: overdue.count, dueToday: dueToday.count, doneToday: 0)
    }

    var body: some View {
        switch family {
        case .systemMedium:
            medium
        default:
            small
        }
    }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                MascotView(mood: mood, animated: false)
                    .frame(width: 30, height: 30)
                Text("ON TRACK")
                    .font(InkType.stamp(9))
                    .stampCase()
                    .foregroundStyle(Ink.ink)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 7) {
                countRow(overdue.count, label: "late", alarmed: !overdue.isEmpty)
                RoughDivider(seed: 601, opacity: 0.25)
                countRow(dueToday.count, label: "today", alarmed: false)
            }
        }
        .padding(14)
    }

    // MARK: Medium

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                MascotView(mood: mood, animated: false)
                    .frame(width: 34, height: 34)
                Text("ON TRACK")
                    .font(InkType.stamp(9))
                    .stampCase()
                    .foregroundStyle(Ink.ink)

                Spacer(minLength: 0)

                countRow(overdue.count, label: "late", alarmed: !overdue.isEmpty)
                countRow(dueToday.count, label: "today", alarmed: false)
            }
            .frame(width: 78, alignment: .leading)

            listColumn
        }
        .padding(14)
    }

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            let upcoming = (overdue + dueToday).prefix(4)
            if upcoming.isEmpty {
                Text(MascotVoice.line(for: .bored))
                    .font(InkType.bodySmall)
                    .foregroundStyle(Ink.inkSoft)
            } else {
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { _, task in
                    row(task)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 7) {
            RoughRect(seed: task.seed, wobble: 1.1, corner: 2)
                .stroke(task.isOverdue ? Ink.alarm.opacity(0.8) : Ink.ink.opacity(0.6), lineWidth: 1.5)
                .frame(width: 13, height: 13)
                .padding(.top, 2)

            Text(task.title)
                .font(InkType.bodySmall)
                .foregroundStyle(Ink.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func countRow(_ count: Int, label: String, alarmed: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(count)")
                .font(InkType.display(family == .systemSmall ? 26 : 22))
                .foregroundStyle(alarmed ? Ink.alarm : Ink.ink)
            Text(label)
                .font(InkType.stamp(9))
                .stampCase()
                .foregroundStyle(alarmed ? Ink.alarm : Ink.inkSoft)
        }
    }
}
