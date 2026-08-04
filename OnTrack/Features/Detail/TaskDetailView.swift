import SwiftUI

struct TaskDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TaskItem
    @State private var hasDueDate: Bool
    @State private var isBreakingDown = false
    @State private var newSubtask = ""

    init(task: TaskItem) {
        _draft = State(initialValue: task)
        _hasDueDate = State(initialValue: task.dueAt != nil)
    }

    private var subtasks: [TaskItem] {
        model.subtasks(of: draft)
    }

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    titleField
                    schedule
                    priorityPicker
                    subtaskSection
                    notesField
                    dangerZone
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
            }
        }
        .onDisappear { commit() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text(draft.isDone ? "Done" : "Task")
                .font(InkType.title(24))
                .posterCase(tracking: -0.8)
                .foregroundStyle(Ink.ink)

            Spacer()

            Button {
                Task {
                    await model.toggleDone(draft)
                    dismiss()
                }
            } label: {
                Text(draft.isDone ? "Reopen" : "Mark done")
            }
            .buttonStyle(InkOutlineButtonStyle(seed: 701))

            InkIconButton(systemName: "xmark", seed: 702) {
                commit()
                dismiss()
            }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionRule(title: "What", seed: 710)
            TextField("Title", text: $draft.title, axis: .vertical)
                .font(InkType.title(22))
                .foregroundStyle(Ink.ink)
                .tint(Ink.ink)
                .lineLimit(1...4)
        }
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionRule(title: "When", seed: 711)

            Toggle(isOn: $hasDueDate) {
                Text("Has a due date").font(InkType.body).foregroundStyle(Ink.ink)
            }
            .tint(Ink.ink)
            .onChange(of: hasDueDate) { _, isOn in
                draft.dueAt = isOn ? (draft.dueAt ?? Date()) : nil
                if !isOn { draft.recurrence = nil }
            }

            if hasDueDate {
                DatePicker(
                    "Due",
                    selection: Binding(
                        get: { draft.dueAt ?? Date() },
                        set: { draft.dueAt = $0 }
                    ),
                    displayedComponents: draft.hasTime ? [.date, .hourAndMinute] : [.date]
                )
                .datePickerStyle(.compact)
                .tint(Ink.ink)
                .font(InkType.body)

                Toggle(isOn: $draft.hasTime) {
                    Text("At a specific time").font(InkType.bodySmall).foregroundStyle(Ink.inkSoft)
                }
                .tint(Ink.ink)

                if let recurrence = draft.recurrence {
                    HStack(spacing: 8) {
                        StampLabel(text: "repeats \(Recurrence.describe(recurrence))", filled: true, seed: 712)
                        Button("Stop repeating") { draft.recurrence = nil }
                            .font(InkType.stamp(10))
                            .stampCase()
                            .foregroundStyle(Ink.alarm)
                    }
                }
            }
        }
    }

    private var priorityPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionRule(title: "How urgent", seed: 713)

            HStack(spacing: 8) {
                ForEach(0...3, id: \.self) { level in
                    Button {
                        InkHaptics.tick()
                        draft.priority = level
                    } label: {
                        Text(label(for: level))
                            .font(InkType.stamp(11))
                            .stampCase()
                            .foregroundStyle(draft.priority == level ? Ink.paper : Ink.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background {
                                if draft.priority == level {
                                    RoughRect(seed: 720 + UInt64(level), wobble: 1.5, corner: 4).fill(Ink.ink)
                                } else {
                                    RoughRect(seed: 720 + UInt64(level), wobble: 1.5, corner: 4)
                                        .stroke(Ink.ink.opacity(0.4), lineWidth: 1.3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func label(for level: Int) -> String {
        switch level {
        case 1: return "!"
        case 2: return "!!"
        case 3: return "!!!"
        default: return "none"
        }
    }

    private var subtaskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionRule(title: "Steps", trailing: subtasks.isEmpty ? nil : "\(subtasks.filter(\.isDone).count)/\(subtasks.count)", seed: 714)

            ForEach(subtasks) { child in
                HStack(spacing: 10) {
                    Button {
                        Task { await model.toggleDone(child) }
                    } label: {
                        InkCheckbox(isDone: child.isDone, seed: child.seed, size: 21)
                    }
                    .buttonStyle(.plain)

                    Text(child.title)
                        .font(InkType.bodySmall)
                        .strikethrough(child.isDone, color: Ink.ink.opacity(0.6))
                        .foregroundStyle(child.isDone ? Ink.inkSoft : Ink.ink)

                    Spacer(minLength: 0)

                    Button {
                        Task { await model.delete(child) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Ink.inkFaint)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                TextField("Add a step", text: $newSubtask)
                    .font(InkType.bodySmall)
                    .tint(Ink.ink)
                    .onSubmit { addSubtask() }

                Button("Add", action: addSubtask)
                    .font(InkType.stamp(10))
                    .stampCase()
                    .foregroundStyle(Ink.ink)
                    .disabled(newSubtask.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Button {
                Task {
                    isBreakingDown = true
                    await model.breakDown(draft)
                    isBreakingDown = false
                }
            } label: {
                HStack(spacing: 8) {
                    if isBreakingDown {
                        ProgressView().tint(Ink.ink).scaleEffect(0.8)
                    } else {
                        Image(systemName: "wand.and.stars").font(.system(size: 13, weight: .black))
                    }
                    Text(isBreakingDown ? "Thinking" : "Break it down")
                }
            }
            .buttonStyle(InkOutlineButtonStyle(seed: 715))
            .disabled(isBreakingDown)
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionRule(title: "Notes", seed: 716)
            TextField(
                "Anything else",
                text: Binding(get: { draft.notes ?? "" }, set: { draft.notes = $0.isEmpty ? nil : $0 }),
                axis: .vertical
            )
            .font(InkType.bodySmall)
            .foregroundStyle(Ink.ink)
            .tint(Ink.ink)
            .lineLimit(2...8)
        }
    }

    private var dangerZone: some View {
        Button {
            Task {
                await model.delete(draft)
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash").font(.system(size: 13, weight: .black))
                Text("Delete")
            }
            .font(InkType.stamp(11))
            .stampCase()
            .foregroundStyle(Ink.alarm)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private func addSubtask() {
        let title = newSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newSubtask = ""
        let child = TaskItem(
            userId: draft.userId,
            title: title,
            parentId: draft.id,
            sortIndex: (subtasks.map(\.sortIndex).max() ?? draft.sortIndex) + 0.001,
            source: .manual
        )
        Task { await model.update(child) }
    }

    /// Detail edits are saved on the way out rather than on every keystroke.
    private func commit() {
        guard let original = model.tasks.first(where: { $0.id == draft.id }), original != draft else { return }
        Task { await model.update(draft) }
    }
}
