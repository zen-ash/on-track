import SwiftUI
import WidgetKit

/// What the Focus widget shows. Kept in Shared, same reasoning as
/// `TodayWidgetView`: the main app can render this exact view in a debug
/// preview, not a look-alike.
///
/// Read-only, tap to open — same posture the Today widget already takes.
/// Interactive Pause/Stop needs the widget extension's own process to
/// correctly tell a local session from a synced one, which depends on
/// Keychain sharing this app doesn't have configured yet; safer to ship the
/// glanceable read than to risk a Stop tap silently logging to the wrong
/// place for a signed-in account.
struct FocusEntry: TimelineEntry {
    let date: Date
    let tracks: [FocusTrack]
    let todaysSessions: [FocusSession]
    let active: ActiveFocusState?
}

enum FocusSampleData {
    static let tracks: [FocusTrack] = [
        FocusTrack(name: "Learning", sortIndex: 1),
        FocusTrack(name: "Networking", sortIndex: 2),
        FocusTrack(name: "Building", sortIndex: 3)
    ]

    static var sessions: [FocusSession] {
        [
            FocusSession(trackId: tracks[1].id, startedAt: Date().addingTimeInterval(-2400), endedAt: Date().addingTimeInterval(-1800), accumulatedSeconds: 600),
            FocusSession(trackId: tracks[2].id, startedAt: Date().addingTimeInterval(-7200), endedAt: Date().addingTimeInterval(-3600), accumulatedSeconds: 3600)
        ]
    }

    static var active: ActiveFocusState {
        ActiveFocusState(sessionId: UUID(), trackId: tracks[0].id, startedAt: Date().addingTimeInterval(-620), accumulatedSeconds: 0, runningSince: Date().addingTimeInterval(-620))
    }
}

// MARK: - Derived state

private extension FocusEntry {
    func totalSeconds(for track: FocusTrack, at now: Date) -> Int {
        let logged = todaysSessions.filter { $0.trackId == track.id }.reduce(0) { $0 + $1.accumulatedSeconds }
        guard let active, active.trackId == track.id else { return logged }
        return logged + active.elapsedSeconds(at: now)
    }

    /// Every track with any time today, most time first — same ordering
    /// FocusView's own "Today" section uses.
    func sortedTotals(at now: Date) -> [(track: FocusTrack, seconds: Int)] {
        tracks.map { ($0, totalSeconds(for: $0, at: now)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    var activeTrack: FocusTrack? {
        guard let active else { return nil }
        return tracks.first { $0.id == active.trackId }
    }
}

// MARK: - View

struct FocusWidgetView: View {
    @Environment(\.widgetFamily) private var systemFamily
    let entry: FocusEntry
    var forcedFamily: WidgetFamily? = nil

    private var family: WidgetFamily { forcedFamily ?? systemFamily }
    private var totals: [(track: FocusTrack, seconds: Int)] { entry.sortedTotals(at: entry.date) }

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                medium
            default:
                small
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts = ["Focus"]
        if let track = entry.activeTrack, let active = entry.active {
            let state = active.isPaused ? "paused" : "running"
            parts.append("\(track.name), \(state), \(Self.spokenDuration(active.elapsedSeconds(at: entry.date)))")
        }
        if totals.isEmpty {
            parts.append("Nothing logged today")
        } else {
            parts.append("Today: " + totals.prefix(3).map { "\($0.track.name), \(Self.spokenDuration($0.seconds))" }.joined(separator: ", "))
        }
        return parts.joined(separator: ". ")
    }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Spacer(minLength: 0)
            if let track = entry.activeTrack, let active = entry.active {
                activeBlock(track: track, active: active, compact: true)
            } else {
                idleSummary
            }
        }
        .padding(14)
    }

    // MARK: Medium

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                header
                if let track = entry.activeTrack, let active = entry.active {
                    activeBlock(track: track, active: active, compact: false)
                } else {
                    Text("Nothing running")
                        .inkBodySmall()
                        .foregroundStyle(Ink.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 132, alignment: .leading)

            totalsColumn
        }
        .padding(14)
    }

    // MARK: Shared pieces

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .black))
            Text("FOCUS")
                .inkStamp(9)
                .stampCase()
            Spacer(minLength: 0)
        }
        .foregroundStyle(Ink.ink)
    }

    private var idleSummary: some View {
        Group {
            if let top = totals.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.clockFormat(top.seconds))
                        .inkDisplay(24)
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
    }

    private func activeBlock(track: FocusTrack, active: ActiveFocusState, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(track.name)
                .inkHeading(compact ? 14 : 16)
                .foregroundStyle(Ink.ink)
                .lineLimit(1)

            if active.isPaused {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.clockFormat(active.elapsedSeconds(at: entry.date)))
                        .inkDisplay(compact ? 22 : 26)
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink)
                    // StampLabel itself lives in the main app's design
                    // system, not Shared, so this is the same look built by
                    // hand from what Shared already exports.
                    Text("PAUSED")
                        .inkStamp(10)
                        .stampCase()
                        .foregroundStyle(Ink.alarm)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            RoughRect(seed: track.seed, wobble: 1.3, corner: 2)
                                .stroke(Ink.alarm.opacity(0.5), lineWidth: 1.1)
                        }
                }
            } else {
                // A virtual start date that already accounts for banked
                // time, so the system renders the live tick itself — no
                // per-second widget refresh needed for this to stay honest.
                Text(virtualStart(for: active), style: .timer)
                    .inkDisplay(compact ? 22 : 26)
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink)
            }
        }
    }

    private var totalsColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            let shown = totals.prefix(4)
            if shown.isEmpty {
                Text("Nothing logged today")
                    .inkBodySmall()
                    .foregroundStyle(Ink.inkSoft)
            } else {
                ForEach(Array(shown), id: \.track.id) { item in
                    HStack(spacing: 6) {
                        Text(item.track.name)
                            .inkBodySmall()
                            .foregroundStyle(Ink.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Self.clockFormat(item.seconds))
                            .inkStamp(10)
                            .foregroundStyle(Ink.inkSoft)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func virtualStart(for active: ActiveFocusState) -> Date {
        (active.runningSince ?? entry.date).addingTimeInterval(-Double(active.accumulatedSeconds))
    }

    // MARK: - Formatting

    private static func clockFormat(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        // A genuine short session (a 45-second check-in) shouldn't read as
        // "0m" — indistinguishable from nothing having happened at all.
        return seconds > 0 ? "<1m" : "0m"
    }

    private static func spokenDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hour\(h == 1 ? "" : "s")") }
        if m > 0 || h == 0 { parts.append("\(m) minute\(m == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }
}
