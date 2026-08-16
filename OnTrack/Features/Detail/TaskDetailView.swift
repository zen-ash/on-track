import SwiftUI

struct TaskDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TaskItem
    @State private var hasDueDate: Bool
    @State private var isBreakingDown = false
    @State private var newSubtask = ""
    @State private var newTag = ""

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
                    effortSection
                    tagsEditor
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
                .inkTitle(24)
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

            InkIconButton(systemName: "xmark", seed: 702, accessibilityLabel: "Close") {
                commit()
                dismiss()
            }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionRule(title: "What", seed: 710)
            TextField("Title", text: $draft.title, axis: .vertical)
                .inkTitle(22)
                .foregroundStyle(Ink.ink)
                .tint(Ink.ink)
                .lineLimit(1...4)
        }
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionRule(title: "When", seed: 711)

            Toggle(isOn: $hasDueDate) {
                Text("Has a due date").inkBody().foregroundStyle(Ink.ink)
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
                .inkBody()

                Toggle(isOn: $draft.hasTime) {
                    Text("At a specific time").inkBodySmall().foregroundStyle(Ink.inkSoft)
                }
                .tint(Ink.ink)

                if let recurrence = draft.recurrence {
                    HStack(spacing: 8) {
                        StampLabel(text: "repeats \(Recurrence.describe(recurrence))", filled: true, seed: 712)
                        Button("Stop repeating") { draft.recurrence = nil }
                            .inkStamp(10)
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
                            .inkStamp(11)
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
                    .accessibilityLabel(accessibilityLabel(for: level))
                    .accessibilityAddTraits(draft.priority == level ? .isSelected : [])
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

    private func accessibilityLabel(for level: Int) -> String {
        switch level {
        case 1: return "Low priority"
        case 2: return "Medium priority"
        case 3: return "Urgent priority"
        default: return "No priority"
        }
    }

    // MARK: - Effort (energy + estimate)

    /// Both of these are read by the planning function on the server —
    /// `estimate_minutes`/`energy` in supabase/functions/ai/index.ts — so an
    /// AI guess that's wrong, or a typed task that never got one set at all,
    /// was previously stuck degrading its own planning input with no way to
    /// fix it. Grouped together since they answer the same underlying
    /// question: how much of a day does this actually take.
    private var effortSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionRule(title: "For planning", seed: 717)
            energyPicker
            estimatePicker
        }
    }

    private var energyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Energy").inkBodySmall().foregroundStyle(Ink.inkSoft)
            HStack(spacing: 8) {
                energyButton(nil, label: "none", seed: 730)
                energyButton(.low, label: "low", seed: 731)
                energyButton(.medium, label: "medium", seed: 732)
                energyButton(.high, label: "high", seed: 733)
            }
        }
    }

    private func energyButton(_ value: TaskEnergy?, label: String, seed: UInt64) -> some View {
        let isSelected = draft.energy == value
        return Button {
            InkHaptics.tick()
            draft.energy = value
        } label: {
            Text(label)
                .inkStamp(11)
                .stampCase()
                .foregroundStyle(isSelected ? Ink.paper : Ink.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    if isSelected {
                        RoughRect(seed: seed, wobble: 1.5, corner: 4).fill(Ink.ink)
                    } else {
                        RoughRect(seed: seed, wobble: 1.5, corner: 4)
                            .stroke(Ink.ink.opacity(0.4), lineWidth: 1.3)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value == nil ? "No energy level set" : "\(label) energy")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var estimatePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Roughly how long").inkBodySmall().foregroundStyle(Ink.inkSoft)
            HStack(spacing: 8) {
                ForEach(Array(estimateOptions.enumerated()), id: \.offset) { index, value in
                    estimateButton(value, label: estimateOptionLabel(value), seed: 740 + UInt64(index))
                }
            }
        }
    }

    /// Always includes whatever's actually set, even when it isn't one of
    /// the standard presets — capture can set `estimateMinutes` to any
    /// integer, not just these five, and a picker limited to presets alone
    /// would otherwise show nothing selected for a real value like 90 and
    /// silently read as "no estimate" when one is actually set.
    private var estimateOptions: [Int?] {
        var options: [Int?] = [nil, 15, 30, 60, 120]
        if let current = draft.estimateMinutes, !options.contains(current) {
            options.append(current)
            options.sort { ($0 ?? -1) < ($1 ?? -1) }
        }
        return options
    }

    private func estimateOptionLabel(_ value: Int?) -> String {
        guard let value else { return "none" }
        if value < 60 { return "\(value)m" }
        let hours = value / 60
        let remainder = value % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    private func estimateButton(_ value: Int?, label: String, seed: UInt64) -> some View {
        let isSelected = draft.estimateMinutes == value
        return Button {
            InkHaptics.tick()
            draft.estimateMinutes = value
        } label: {
            Text(label)
                .inkStamp(11)
                .stampCase()
                .foregroundStyle(isSelected ? Ink.paper : Ink.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    if isSelected {
                        RoughRect(seed: seed, wobble: 1.5, corner: 4).fill(Ink.ink)
                    } else {
                        RoughRect(seed: seed, wobble: 1.5, corner: 4)
                            .stroke(Ink.ink.opacity(0.4), lineWidth: 1.3)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value == nil ? "No estimate set" : "About \(label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Tags

    /// Previously read-only decoration: whatever capture happened to guess,
    /// with no way to add, remove, or browse by one. Tapping an existing tag
    /// hands off to Search rather than duplicating a filter here — the same
    /// #tag stamp on a row does the same thing.
    private var tagsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionRule(title: "Tags", seed: 718)

            if !draft.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(draft.tags, id: \.self) { tag in
                            tagChip(tag)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Add a tag", text: $newTag)
                    .inkBodySmall()
                    .tint(Ink.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { addTag() }

                Button("Add", action: addTag)
                    .inkStamp(10)
                    .stampCase()
                    .foregroundStyle(Ink.ink)
                    .disabled(normalizedNewTag.isEmpty)
            }
        }
    }

    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: 6) {
            Button {
                model.pendingSearchQuery = tag
                dismiss()
            } label: {
                Text("#\(tag)")
                    .inkStamp(11)
                    .stampCase()
                    .foregroundStyle(Ink.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter by tag \(tag)")

            Button {
                draft.tags.removeAll { $0 == tag }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Ink.inkFaint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove tag \(tag)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoughRect(seed: tag.inkSeed, wobble: 1.3, corner: 3)
                .stroke(Ink.ink.opacity(0.4), lineWidth: 1.2)
        }
    }

    private var normalizedNewTag: String {
        newTag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    }

    private func addTag() {
        let tag = normalizedNewTag
        guard !tag.isEmpty,
              !draft.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else {
            newTag = ""
            return
        }
        draft.tags.append(tag)
        newTag = ""
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
                    // No swipe-action alternative here — this button is the
                    // only way to toggle a step, so it needs its own label
                    // rather than the row absorbing it the way TaskRow does.
                    .accessibilityLabel(child.title)
                    .accessibilityValue(child.isDone ? "Done" : "Not done")

                    Text(child.title)
                        .inkBodySmall()
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
                    .accessibilityLabel("Remove step")
                }
            }

            HStack(spacing: 10) {
                TextField("Add a step", text: $newSubtask)
                    .inkBodySmall()
                    .tint(Ink.ink)
                    .onSubmit { addSubtask() }

                Button("Add", action: addSubtask)
                    .inkStamp(10)
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
            .inkBodySmall()
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
            .inkStamp(11)
            .stampCase()
            .foregroundStyle(Ink.alarm)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .accessibilityLabel("Delete task")
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
