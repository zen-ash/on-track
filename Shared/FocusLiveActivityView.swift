import SwiftUI

// MARK: - Derived state

extension FocusActivityAttributes.ContentState {
    var isPaused: Bool { runningSince == nil }

    func elapsedSeconds(at now: Date) -> Int {
        guard let runningSince else { return accumulatedSeconds }
        return accumulatedSeconds + max(0, Int(now.timeIntervalSince(runningSince)))
    }

    /// Same trick as the widget: a virtual start date that already accounts
    /// for banked time, so `Text(_:style:.timer)` ticks on its own with no
    /// per-second refresh from anywhere.
    func virtualStart(at now: Date) -> Date {
        (runningSince ?? now).addingTimeInterval(-Double(accumulatedSeconds))
    }
}

private func clockFormat(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m" }
    return seconds > 0 ? "<1m" : "0m"
}

// MARK: - Lock Screen / banner

/// The Lock Screen presentation — also what shows in StandBy and as the
/// fallback on devices without a Dynamic Island. Same "track name, live
/// timer or paused stamp" shape as the Home Screen widget's small size, just
/// wider.
struct FocusLiveActivityView: View {
    let attributes: FocusActivityAttributes
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "timer")
                        .font(.system(size: 12, weight: .black))
                    Text("FOCUS")
                        .inkStamp(9)
                        .stampCase()
                }
                .foregroundStyle(Ink.inkSoft)

                Text(attributes.trackName)
                    .inkHeading(17)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            timerBlock
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var timerBlock: some View {
        if state.isPaused {
            VStack(alignment: .trailing, spacing: 4) {
                Text(clockFormat(state.accumulatedSeconds))
                    .inkDisplay(24)
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink)
                Text("PAUSED")
                    .inkStamp(9)
                    .stampCase()
                    .foregroundStyle(Ink.alarm)
            }
        } else {
            Text(state.virtualStart(at: Date()), style: .timer)
                .inkDisplay(28)
                .monospacedDigit()
                .foregroundStyle(Ink.ink)
        }
    }

    private var accessibilityDescription: String {
        let status = state.isPaused ? "paused" : "running"
        return "Focus, \(attributes.trackName), \(status)"
    }
}

// MARK: - Dynamic Island

struct FocusIslandExpandedLeading: View {
    let attributes: FocusActivityAttributes

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .black))
            Text(attributes.trackName)
                .inkBodySmall()
                .lineLimit(1)
        }
        .foregroundStyle(Ink.ink)
    }
}

struct FocusIslandExpandedTrailing: View {
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isPaused {
                Text("PAUSED")
                    .inkStamp(10)
                    .stampCase()
                    .foregroundStyle(Ink.alarm)
            } else {
                Text(state.virtualStart(at: Date()), style: .timer)
                    .inkStamp(15)
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink)
            }
        }
    }
}

struct FocusIslandCompactLeading: View {
    var body: some View {
        Image(systemName: "timer")
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(Ink.ink)
    }
}

/// The compact-trailing region is narrow, so a paused session gets a plain
/// glyph rather than a word that would just get clipped.
struct FocusIslandCompactTrailing: View {
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 11, weight: .bold))
            } else {
                Text(state.virtualStart(at: Date()), style: .timer)
                    .inkStamp(13)
                    .monospacedDigit()
            }
        }
        .foregroundStyle(Ink.ink)
    }
}

struct FocusIslandMinimal: View {
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        Image(systemName: state.isPaused ? "pause.fill" : "timer")
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(Ink.ink)
    }
}
