import SwiftUI

/// Everything soft-deleted in the last 30 days, recoverable until then. The
/// undo toast on the main list only covers the few seconds right after a
/// delete — this is where a task lands once that window closes, so "delete"
/// no longer has to mean "gone for good" by default.
struct TrashView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// A permanent delete gets an actual question — unlike restoring, there's
    /// no toast, no second Trash, nothing after this.
    @State private var pendingPermanentDelete: TaskItem?

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: 0) {
                header

                if model.isLoadingTrash && model.trashedTasks.isEmpty {
                    Spacer()
                    ProgressView().tint(Ink.ink)
                    Spacer()
                } else if model.trashedTasks.isEmpty {
                    EmptyTrash()
                } else {
                    list
                }
            }
        }
        .task { await model.loadTrash() }
        .confirmationDialog(
            "Delete “\(pendingPermanentDelete?.title ?? "")” forever?",
            isPresented: Binding(
                get: { pendingPermanentDelete != nil },
                set: { isPresented in if !isPresented { pendingPermanentDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete forever", role: .destructive) {
                if let task = pendingPermanentDelete {
                    Task { await model.permanentlyDelete(task) }
                }
                pendingPermanentDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingPermanentDelete = nil }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Trash")
                        .inkTitle(24)
                        .posterCase(tracking: -0.8)
                        .foregroundStyle(Ink.ink)
                    Text("Kept for 30 days")
                        .inkStamp(10)
                        .stampCase()
                        .foregroundStyle(Ink.inkSoft)
                }
                Spacer()
                InkIconButton(systemName: "xmark", seed: 1801, accessibilityLabel: "Close") { dismiss() }
            }
            RoughDivider(seed: 1802, opacity: 0.3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var list: some View {
        List {
            ForEach(model.trashedTasks) { task in
                row(task)
            }
            Color.clear.frame(height: 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .refreshable { await model.loadTrash() }
    }

    private func row(_ task: TaskItem) -> some View {
        TrashRow(task: task)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 3, leading: 20, bottom: 3, trailing: 20))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    pendingPermanentDelete = task
                } label: {
                    Label("Delete Forever", systemImage: "trash.fill")
                }
                .tint(Ink.alarm)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    Task { await model.restoreFromTrash(task) }
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .tint(Ink.ink)
            }
            .accessibilityActions {
                Button("Restore") {
                    Task { await model.restoreFromTrash(task) }
                }
                Button("Delete Forever", role: .destructive) {
                    pendingPermanentDelete = task
                }
            }
    }
}

// MARK: - Row

private struct TrashRow: View {
    let task: TaskItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .inkBody()
                    .foregroundStyle(Ink.inkSoft)
                    .strikethrough(true, color: Ink.inkSoft.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 5) {
                    StampLabel(text: deletedLabel, seed: task.seed)
                    StampLabel(
                        text: daysLeftLabel,
                        tint: isExpiringSoon ? Ink.alarm : Ink.ink,
                        seed: task.seed &+ 1
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background {
            RoughRect(seed: task.seed, wobble: 1.6, corner: 5)
                .stroke(Ink.ink.opacity(0.14), lineWidth: 1.2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(task.title). \(deletedLabel). \(daysLeftLabel).")
    }

    private var deletedLabel: String {
        guard let deletedAt = task.deletedAt else { return "Deleted" }
        let cal = Calendar.current
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: deletedAt),
            to: cal.startOfDay(for: Date())
        ).day ?? 0
        if days <= 0 { return "Deleted today" }
        if days == 1 { return "Deleted yesterday" }
        return "Deleted \(days) days ago"
    }

    private var daysUntilPurge: Int {
        guard let deletedAt = task.deletedAt else { return 0 }
        let cal = Calendar.current
        let purgeDate = cal.date(byAdding: .day, value: 30, to: deletedAt) ?? deletedAt
        return cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: Date()),
            to: cal.startOfDay(for: purgeDate)
        ).day ?? 0
    }

    private var isExpiringSoon: Bool { daysUntilPurge <= 3 }

    private var daysLeftLabel: String {
        let days = daysUntilPurge
        if days <= 0 { return "purges today" }
        if days == 1 { return "1 day left" }
        return "\(days) days left"
    }
}

// MARK: - Empty state

private struct EmptyTrash: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            InkSplatter(seed: 0x7A54, count: 7)
                .frame(width: 140, height: 120)
                .opacity(0.4)

            VStack(spacing: 6) {
                Text("Nothing here")
                    .inkTitle(22)
                    .posterCase(tracking: -0.6)
                    .foregroundStyle(Ink.ink)

                Text("Deleted tasks stick around for 30 days\nbefore they're gone for good.")
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
