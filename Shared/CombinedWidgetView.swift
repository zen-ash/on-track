import SwiftUI
import WidgetKit

/// Tasks and Focus side by side, for anyone who wants both without placing
/// two separate tiles. `TodayWidget` and `FocusWidget` stay exactly as they
/// are — this is a third option, reading the same two snapshots they
/// already write.
///
/// Medium only: there's no small-widget layout that fits both domains
/// without either turning into a single unreadable number.
struct CombinedEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskItem]
    let tracks: [FocusTrack]
    let todaysSessions: [FocusSession]
    let active: ActiveFocusState?
}

enum CombinedSampleData {
    static var entry: CombinedEntry {
        CombinedEntry(date: Date(), tasks: TodaySampleData.tasks, tracks: FocusSampleData.tracks, todaysSessions: FocusSampleData.sessions, active: FocusSampleData.active)
    }
}

// MARK: - Derived state
// The same classification TodayWidgetView and FocusWidgetView each already
// do for their own entry types — small enough that duplicating it here beats
// threading a shared protocol through three widgets for one filter.

private extension CombinedEntry {
    var overdue: [TaskItem] { tasks.inWorkingOrder().filter(\.isOverdue) }
    var dueToday: [TaskItem] { tasks.inWorkingOrder().filter { !$0.isOverdue && ($0.isDueToday || $0.dueAt == nil) } }

    var activeTrack: FocusTrack? {
        guard let active else { return nil }
        return tracks.first { $0.id == active.trackId }
    }

    func totalSeconds(for track: FocusTrack, at now: Date) -> Int {
        let logged = todaysSessions.filter { $0.trackId == track.id }.reduce(0) { $0 + $1.accumulatedSeconds }
        guard let active, active.trackId == track.id else { return logged }
        return logged + active.elapsedSeconds(at: now)
    }

    func sortedTotals(at now: Date) -> [(track: FocusTrack, seconds: Int)] {
        tracks.map { ($0, totalSeconds(for: $0, at: now)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }
}

// MARK: - View

struct CombinedWidgetView: View {
    let entry: CombinedEntry

    private var overdue: [TaskItem] { entry.overdue }
    private var dueToday: [TaskItem] { entry.dueToday }
    private var totals: [(track: FocusTrack, seconds: Int)] { entry.sortedTotals(at: entry.date) }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            tasksColumn
            focusColumn
        }
        .padding(14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts = ["On Track"]
        parts.append(overdue.isEmpty ? "nothing late" : "\(overdue.count) late")
        parts.append(dueToday.isEmpty ? "nothing due today" : "\(dueToday.count) due today")
        if let track = entry.activeTrack, let active = entry.active {
            parts.append("Focus: \(track.name), \(active.isPaused ? "paused" : "running")")
        } else if let top = totals.first {
            parts.append("Focus today: \(top.track.name)")
        }
        return parts.joined(separator: ". ")
    }

    // MARK: Tasks column

    private var tasksColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ON TRACK")
                .inkStamp(9)
                .stampCase()
                .foregroundStyle(Ink.inkSoft)

            Spacer(minLength: 0)

            countRow(overdue.count, label: "late", alarmed: !overdue.isEmpty)
            countRow(dueToday.count, label: "today", alarmed: false)
        }
        .frame(width: 92, alignment: .leading)
    }

    private func countRow(_ count: Int, label: String, alarmed: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(count)")
                .inkDisplay(22)
                .foregroundStyle(alarmed ? Ink.alarm : Ink.ink)
            Text(label)
                .inkStamp(9)
                .stampCase()
                .foregroundStyle(alarmed ? Ink.alarm : Ink.inkSoft)
        }
    }

    // MARK: Focus column

    private var focusColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .black))
                Text("FOCUS")
                    .inkStamp(9)
                    .stampCase()
            }
            .foregroundStyle(Ink.inkSoft)

            Spacer(minLength: 0)

            if let track = entry.activeTrack, let active = entry.active {
                activeBlock(track: track, active: active)
            } else if let top = totals.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.clockFormat(top.seconds))
                        .inkDisplay(20)
                        .foregroundStyle(Ink.ink)
                    Text(top.track.name)
                        .inkStamp(9)
                        .stampCase()
                        .foregroundStyle(Ink.inkSoft)
                        .lineLimit(1)
                }
            } else {
                Text("Nothing logged today")
                    .inkBodySmall()
                    .foregroundStyle(Ink.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activeBlock(track: FocusTrack, active: ActiveFocusState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.name)
                .inkHeading(14)
                .foregroundStyle(Ink.ink)
                .lineLimit(1)

            if active.isPaused {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.clockFormat(active.elapsedSeconds(at: entry.date)))
                        .inkDisplay(20)
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink)
                    Text("PAUSED")
                        .inkStamp(9)
                        .stampCase()
                        .foregroundStyle(Ink.alarm)
                }
            } else {
                Text(virtualStart(for: active), style: .timer)
                    .inkDisplay(20)
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink)
            }
        }
    }

    private func virtualStart(for active: ActiveFocusState) -> Date {
        (active.runningSince ?? entry.date).addingTimeInterval(-Double(active.accumulatedSeconds))
    }

    private static func clockFormat(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return seconds > 0 ? "<1m" : "0m"
    }
}
