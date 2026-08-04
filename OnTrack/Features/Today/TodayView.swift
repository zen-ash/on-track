import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.openTasks.isEmpty && model.completedToday.isEmpty {
                EmptyState()
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
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
        TaskRow(task: task, subtasks: model.subtasks(of: task))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 3, leading: 20, bottom: 3, trailing: 20))
            .contentShape(Rectangle())
            .onTapGesture { model.selectedTask = task }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    Task { await model.delete(task) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(Ink.alarm)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    Task { await model.toggleDone(task) }
                } label: {
                    Label(task.isDone ? "Reopen" : "Done", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(Ink.ink)
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
                    .font(InkType.title(24))
                    .posterCase(tracking: -0.6)
                    .foregroundStyle(Ink.ink)

                Text("Hold the button and just say it.\nDates, repeats and priority get sorted out for you.")
                    .font(InkType.bodySmall)
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
