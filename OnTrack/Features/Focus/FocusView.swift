import SwiftUI

/// A single stopwatch against whichever track is picked — not a per-task
/// timer, not a Pomodoro countdown. One thing runs at a time, pauses for a
/// bathroom break without losing the session, and today's totals per track
/// are what's actually worth seeing at a glance.
struct FocusView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var newTrackName = ""
    @State private var pendingArchive: FocusTrack?

    private var activeTracks: [FocusTrack] {
        model.focusTracks.filter { !$0.isArchived }.sorted { $0.sortIndex < $1.sortIndex }
    }

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let active = model.activeFocus,
                           let track = model.focusTracks.first(where: { $0.id == active.trackId }) {
                            runningCard(track: track, state: active)
                        }
                        trackPicker
                        todaySection
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                }
            }
        }
        .confirmationDialog(
            "Archive “\(pendingArchive?.name ?? "")”?",
            isPresented: Binding(
                get: { pendingArchive != nil },
                set: { isPresented in if !isPresented { pendingArchive = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                if let track = pendingArchive {
                    Task { await model.archiveFocusTrack(track) }
                }
                pendingArchive = nil
            }
            Button("Cancel", role: .cancel) { pendingArchive = nil }
        } message: {
            Text("Past time logged against it stays. You won't be able to start it again.")
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Focus")
                        .inkTitle(24)
                        .posterCase(tracking: -0.8)
                        .foregroundStyle(Ink.ink)
                    Text("Where today actually went")
                        .inkStamp(10)
                        .stampCase()
                        .foregroundStyle(Ink.inkSoft)
                }
                Spacer()
                InkIconButton(systemName: "xmark", seed: 1601, accessibilityLabel: "Close") { dismiss() }
            }
            RoughDivider(seed: 1602, opacity: 0.3)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    // MARK: - Running / paused

    private func runningCard(track: FocusTrack, state: ActiveFocusState) -> some View {
        InkCard(seed: track.seed, emphasised: true) {
            VStack(spacing: 14) {
                Text(track.name)
                    .inkHeading(17)
                    .foregroundStyle(Ink.ink)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = state.elapsedSeconds(at: context.date)
                    Text(Self.clockFormat(seconds))
                        .inkDisplay(44)
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink)
                        .accessibilityLabel(Self.spokenDuration(seconds))
                }

                if state.isPaused {
                    StampLabel(text: "paused", tint: Ink.alarm, seed: track.seed &+ 1)
                }

                HStack(spacing: 12) {
                    Button {
                        InkHaptics.tick()
                        if state.isPaused { model.resumeFocus() } else { model.pauseFocus() }
                    } label: {
                        Text(state.isPaused ? "Resume" : "Pause").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(InkOutlineButtonStyle(seed: 1610))

                    Button {
                        Task { await model.stopFocus() }
                    } label: {
                        Text("Stop").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(InkBlockButtonStyle(seed: 1611))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Track picker

    private var trackPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionRule(title: "Tracks", seed: 1620)

            if activeTracks.isEmpty {
                Text("Add a track below to start logging time against it.")
                    .inkBodySmall()
                    .foregroundStyle(Ink.inkSoft)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(activeTracks) { track in
                            trackChip(track)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Add a track", text: $newTrackName)
                    .inkBodySmall()
                    .tint(Ink.ink)
                    .onSubmit { addTrack() }

                Button("Add", action: addTrack)
                    .inkStamp(10)
                    .stampCase()
                    .foregroundStyle(Ink.ink)
                    .disabled(newTrackName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func trackChip(_ track: FocusTrack) -> some View {
        let isActive = model.activeFocus?.trackId == track.id
        return HStack(spacing: 6) {
            Button {
                Task { await model.startFocus(track) }
            } label: {
                Text(track.name)
                    .inkStamp(11)
                    .stampCase()
                    .foregroundStyle(isActive ? Ink.paper : Ink.ink)
            }
            .buttonStyle(.plain)
            .disabled(isActive)
            .accessibilityLabel(isActive ? "\(track.name), currently running" : "Start \(track.name)")

            // Not shown for the active track — archiving out from under a
            // running session is confusing even though it's technically
            // handled (archiveFocusTrack stops it first).
            if !isActive {
                Button {
                    pendingArchive = track
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Ink.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Archive \(track.name)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if isActive {
                RoughRect(seed: track.seed, wobble: 1.5, corner: 4).fill(Ink.ink)
            } else {
                RoughRect(seed: track.seed, wobble: 1.5, corner: 4)
                    .stroke(Ink.ink.opacity(0.4), lineWidth: 1.3)
            }
        }
    }

    private func addTrack() {
        let name = newTrackName
        newTrackName = ""
        Task { await model.addFocusTrack(name: name) }
    }

    // MARK: - Today

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionRule(title: "Today", seed: 1630)

            // Ticks with the running card so a total updates live rather
            // than only once you hit Stop.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let totals = todaysTotals(at: context.date)
                if totals.isEmpty {
                    Text("Nothing logged yet today.")
                        .inkBodySmall()
                        .foregroundStyle(Ink.inkSoft)
                } else {
                    VStack(spacing: 8) {
                        ForEach(totals, id: \.track.id) { entry in
                            totalRow(entry.track, seconds: entry.seconds)
                        }
                    }
                }
            }
        }
    }

    private func todaysTotals(at now: Date) -> [(track: FocusTrack, seconds: Int)] {
        model.focusTracks
            .map { ($0, model.focusTotalSeconds(for: $0, at: now)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    private func totalRow(_ track: FocusTrack, seconds: Int) -> some View {
        HStack {
            Text(track.name)
                .inkBody()
                .foregroundStyle(Ink.ink)
            Spacer()
            Text(Self.clockFormat(seconds))
                .inkStamp(11)
                .foregroundStyle(Ink.inkSoft)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoughRect(seed: track.seed, wobble: 1.4, corner: 4)
                .stroke(Ink.ink.opacity(0.18), lineWidth: 1.2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(track.name): \(Self.spokenDuration(seconds))")
    }

    // MARK: - Formatting

    private static func clockFormat(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
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
