import SwiftUI

/// Every write here replaces the whole row, so two devices editing the same
/// task close together don't merge — whichever lands last on the server
/// silently wins. This is where that stops being silent: what this device
/// had, what actually stuck, and a way to put yours back if theirs wasn't
/// what you wanted.
struct ConflictsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: 0) {
                header

                if model.conflicts.isEmpty {
                    EmptyConflicts()
                } else {
                    list
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Conflicts")
                        .inkTitle(24)
                        .posterCase(tracking: -0.8)
                        .foregroundStyle(Ink.ink)
                    Text("Edited on more than one device")
                        .inkStamp(10)
                        .stampCase()
                        .foregroundStyle(Ink.inkSoft)
                }
                Spacer()
                InkIconButton(systemName: "xmark", seed: 1901, accessibilityLabel: "Close") { dismiss() }
            }
            RoughDivider(seed: 1902, opacity: 0.3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var list: some View {
        List {
            ForEach(model.conflicts) { conflict in
                row(conflict)
            }
            Color.clear.frame(height: 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    private func row(_ conflict: TaskConflict) -> some View {
        ConflictRow(conflict: conflict)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 3, leading: 20, bottom: 3, trailing: 20))
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    Task { await model.resolveConflictKeepingMine(conflict) }
                } label: {
                    Label("Restore mine", systemImage: "arrow.uturn.backward")
                }
                .tint(Ink.ink)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    model.dismissConflict(conflict)
                } label: {
                    Label("Keep theirs", systemImage: "checkmark")
                }
                .tint(Ink.inkSoft)
            }
            .accessibilityActions {
                Button("Restore mine") {
                    Task { await model.resolveConflictKeepingMine(conflict) }
                }
                Button("Keep theirs") {
                    model.dismissConflict(conflict)
                }
            }
    }
}

// MARK: - Row

private struct ConflictRow: View {
    let conflict: TaskConflict

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(conflict.theirs.title)
                .inkBody()
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            ForEach(diffLines, id: \.self) { line in
                Text(line)
                    .inkBodySmall()
                    .foregroundStyle(Ink.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            StampLabel(text: changedLabel, seed: conflict.taskId.uuidString.inkSeed)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background {
            RoughRect(seed: conflict.taskId.uuidString.inkSeed, wobble: 1.6, corner: 5)
                .stroke(Ink.ink.opacity(0.14), lineWidth: 1.2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([conflict.theirs.title] + diffLines + [changedLabel]).joined(separator: ". "))
    }

    /// What's legible to say about the version that lost — title first since
    /// it's what's actually shown in the list everywhere else, then whatever
    /// else changed. Falls back to something honest rather than nothing at
    /// all when the only differences are in fields not worth spelling out
    /// here (tags, estimate, energy).
    private var diffLines: [String] {
        let mine = conflict.mine
        let theirs = conflict.theirs
        var lines: [String] = []

        if mine.title != theirs.title {
            lines.append("You had it as “\(mine.title)”")
        }
        if mine.status != theirs.status {
            lines.append("You had it \(statusLabel(mine.status))")
        }
        if mine.dueAt != theirs.dueAt || mine.hasTime != theirs.hasTime {
            lines.append("You had it due \(mine.dueStamp ?? "with no date")")
        }
        if mine.notes != theirs.notes {
            lines.append("Your notes were different")
        }
        if lines.isEmpty {
            lines.append("Your version was different")
        }
        return lines
    }

    private func statusLabel(_ status: TaskStatus) -> String {
        switch status {
        case .open: return "not done"
        case .done: return "done"
        case .dropped: return "dropped"
        }
    }

    private var changedLabel: String {
        let cal = Calendar.current
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: conflict.detectedAt),
            to: cal.startOfDay(for: Date())
        ).day ?? 0
        if days <= 0 { return "changed elsewhere today" }
        if days == 1 { return "changed elsewhere yesterday" }
        return "changed elsewhere \(days) days ago"
    }
}

// MARK: - Empty state

private struct EmptyConflicts: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            InkSplatter(seed: 0xC0F1, count: 7)
                .frame(width: 140, height: 120)
                .opacity(0.4)

            VStack(spacing: 6) {
                Text("Nothing to resolve")
                    .inkTitle(22)
                    .posterCase(tracking: -0.6)
                    .foregroundStyle(Ink.ink)

                Text("If an edit here ever loses a race\nwith another device, it'll show up here.")
                    .inkBodySmall()
                    .foregroundStyle(Ink.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
    }
}
