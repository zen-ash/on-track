import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    /// Ending a series is the one swipe action that can't just be undone with a
    /// toast in any obviously-reversible-feeling way, so it gets an actual
    /// question instead of a silent full-swipe.
    @State private var pendingEndSeries: TaskItem?
    @State private var searchText = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Top-level tasks only — subtasks aren't shown as rows of their own
    /// anywhere else in this list either. Matches title, notes and tags;
    /// deliberately not scoped to today or to open tasks, since the whole
    /// point is finding something the grouped sections wouldn't surface —
    /// including a task finished weeks ago.
    private var searchResults: [TaskItem] {
        guard isSearching else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return model.tasks
            .filter { $0.parentId == nil }
            .filter { task in
                task.title.range(of: query, options: options) != nil ||
                    (task.notes?.range(of: query, options: options) != nil) ||
                    task.tags.contains { $0.range(of: query, options: options) != nil }
            }
            .inWorkingOrder()
    }

    var body: some View {
        Group {
            if model.tasks.isEmpty {
                EmptyState()
            } else {
                VStack(spacing: 0) {
                    searchField
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                    list
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "End “\(pendingEndSeries?.title ?? "")”?",
            isPresented: Binding(
                get: { pendingEndSeries != nil },
                set: { isPresented in if !isPresented { pendingEndSeries = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("End series", role: .destructive) {
                if let task = pendingEndSeries {
                    Task { await model.delete(task) }
                }
                pendingEndSeries = nil
            }
            Button("Cancel", role: .cancel) { pendingEndSeries = nil }
        } message: {
            Text("This stops every future occurrence, not just this one. You can undo right after.")
        }
        // Set by tapping a #tag stamp anywhere, including from inside a
        // task's own detail sheet — this is the one place that actually
        // owns the search field, so it's what consumes the request.
        .onChange(of: model.pendingSearchQuery) { _, newValue in
            guard let newValue else { return }
            searchText = newValue
            model.pendingSearchQuery = nil
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Ink.inkSoft)
                .accessibilityHidden(true)

            // Left un-combined with the icon/clear button on purpose: a
            // TextField needs to stay its own element for VoiceOver to be
            // able to focus and type into it at all.
            TextField("Search tasks", text: $searchText)
                .inkBody()
                .foregroundStyle(Ink.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Search tasks")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoughRect(seed: 450, wobble: 1.6, corner: 5)
                .stroke(Ink.ink.opacity(0.3), lineWidth: 1.3)
        }
    }

    private var list: some View {
        List {
            if isSearching {
                if searchResults.isEmpty {
                    Text("No tasks match “\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))”")
                        .inkBodySmall()
                        .foregroundStyle(Ink.inkSoft)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .padding(.top, 24)
                } else {
                    Section {
                        ForEach(searchResults) { task in
                            row(task)
                        }
                    } header: {
                        SectionRule(title: "Results", trailing: "\(searchResults.count)", seed: 405)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                    }
                }
            } else if model.openTasks.isEmpty && model.completedToday.isEmpty {
                // Nothing live today, but model.tasks isn't empty — otherwise
                // this screen wouldn't have a search field at all — so this is
                // older history rather than a true fresh-install empty state.
                Text(model.moodLine)
                    .inkBodySmall()
                    .foregroundStyle(Ink.inkSoft)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.top, 24)
            } else {
                section("Late", tasks: model.overdueTasks, seed: 401, alarming: true)
                section("Today", tasks: model.todayTasks, seed: 402)
                section("Next", tasks: model.upcomingTasks, seed: 403)

                if !model.completedToday.isEmpty {
                    Section {
                        ForEach(model.completedToday) { task in
                            row(task)
                        }
                    } header: {
                        SectionRule(title: "Done today", trailing: "\(model.completedToday.count)", seed: 404)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                    }
                }
            }

            // Breathing room above the capture bar.
            Color.clear.frame(height: 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .listSectionSpacing(.custom(2))
        .contentMargins(.top, 2, for: .scrollContent)
        .refreshable { await model.refresh() }
    }

    @ViewBuilder
    private func section(_ title: String, tasks: [TaskItem], seed: UInt64, alarming: Bool = false) -> some View {
        if !tasks.isEmpty {
            Section {
                ForEach(tasks) { task in
                    row(task)
                }
            } header: {
                SectionRule(title: title, trailing: "\(tasks.count)", seed: seed)
                    .foregroundStyle(alarming ? Ink.alarm : Ink.ink)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
            }
        }
    }

    private func row(_ task: TaskItem) -> some View {
        // An open recurring task gets Skip/End instead of a single Delete —
        // otherwise one swipe silently ends the whole series with no way to
        // say "not this one" and no warning it's gone for good.
        let offersRecurringActions = task.isRecurring && !task.isDone

        return TaskRow(task: task, subtasks: model.subtasks(of: task))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 3, leading: 20, bottom: 3, trailing: 20))
            .contentShape(Rectangle())
            .onTapGesture { model.selectedTask = task }
            .swipeActions(edge: .trailing, allowsFullSwipe: !offersRecurringActions) {
                if offersRecurringActions {
                    Button {
                        Task { await model.skipRecurrence(task) }
                    } label: {
                        Label("Skip", systemImage: "arrow.uturn.forward")
                    }
                    .tint(Ink.ink)

                    Button(role: .destructive) {
                        pendingEndSeries = task
                    } label: {
                        Label("End", systemImage: "trash")
                    }
                    .tint(Ink.alarm)
                } else {
                    Button(role: .destructive) {
                        Task { await model.delete(task) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(Ink.alarm)
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    Task { await model.toggleDone(task) }
                } label: {
                    Label(task.isDone ? "Reopen" : "Done", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(Ink.ink)
            }
            // Swipe actions alone can be unreliable to reach with VoiceOver's
            // gestures, so the same set is repeated explicitly here — double-
            // tap opens detail (matching the sighted tap), the rest show up
            // in the actions rotor.
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.selectedTask = task }
            .accessibilityActions {
                Button(task.isDone ? "Reopen" : "Mark done") {
                    Task { await model.toggleDone(task) }
                }
                if offersRecurringActions {
                    Button("Skip") {
                        Task { await model.skipRecurrence(task) }
                    }
                    Button("End series", role: .destructive) {
                        pendingEndSeries = task
                    }
                } else {
                    Button("Delete", role: .destructive) {
                        Task { await model.delete(task) }
                    }
                }
                // The row combines its children for VoiceOver (see TaskRow),
                // so a #tag stamp's own tap target isn't otherwise reachable
                // — repeated here the same way swipe actions already are,
                // capped at the same two tags the stamps themselves show.
                if task.tags.count > 0 {
                    Button("Filter by tag \(task.tags[0])") {
                        model.pendingSearchQuery = task.tags[0]
                    }
                }
                if task.tags.count > 1 {
                    Button("Filter by tag \(task.tags[1])") {
                        model.pendingSearchQuery = task.tags[1]
                    }
                }
            }
    }
}

// MARK: - Empty state

private struct EmptyState: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                InkSplatter(seed: 0xBAD, count: 9)
                    .frame(width: 210, height: 190)
                    .opacity(0.5)
                MascotView(mood: .bored)
                    .frame(width: 150, height: 150)
            }

            VStack(spacing: 6) {
                Text(model.moodLine)
                    .inkTitle(24)
                    .posterCase(tracking: -0.6)
                    .foregroundStyle(Ink.ink)

                Text("Hold the button and just say it.\nDates, repeats and priority get sorted out for you.")
                    .inkBodySmall()
                    .foregroundStyle(Ink.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
