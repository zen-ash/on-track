import SwiftUI

struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    var subtasks: [TaskItem] = []

    private var doneSubtasks: Int { subtasks.filter(\.isDone).count }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await model.toggleDone(task) }
            } label: {
                InkCheckbox(isDone: task.isDone, seed: task.seed)
            }
            .buttonStyle(.plain)
            // Keeps the tiny checkbox comfortably tappable without moving it.
            .frame(width: 34, height: 34, alignment: .center)
            .contentShape(Rectangle())

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(InkType.body)
                    .foregroundStyle(task.isDone ? Ink.inkSoft : Ink.ink)
                    .strikethrough(task.isDone, color: Ink.ink.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                if !stamps.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(stamps, id: \.text) { stamp in
                            StampLabel(
                                text: stamp.text,
                                filled: stamp.filled,
                                tint: stamp.tint,
                                seed: task.seed &+ UInt64(stamp.text.count)
                            )
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if !subtasks.isEmpty {
                Text("\(doneSubtasks)/\(subtasks.count)")
                    .font(InkType.stamp(10))
                    .foregroundStyle(Ink.inkSoft)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background {
            if task.isOverdue {
                // Late work gets the only colour in the app, and only as a hairline.
                RoughRect(seed: task.seed, wobble: 1.6, corner: 5)
                    .stroke(Ink.alarm.opacity(0.75), lineWidth: 1.6)
            } else if !task.isDone {
                RoughRect(seed: task.seed, wobble: 1.6, corner: 5)
                    .stroke(Ink.ink.opacity(0.20), lineWidth: 1.2)
            }
        }
        .opacity(task.isDone ? 0.55 : 1)
    }

    private struct Stamp {
        let text: String
        var filled: Bool = false
        var tint: Color = Ink.ink
    }

    private var stamps: [Stamp] {
        var out: [Stamp] = []

        if let due = task.dueStamp {
            out.append(Stamp(
                text: due,
                filled: task.isOverdue,
                tint: task.isOverdue ? Ink.alarm : Ink.ink
            ))
        }
        if let priority = task.priorityStamp {
            out.append(Stamp(text: priority, filled: task.priority == 3))
        }
        if let recurrence = task.recurrence {
            out.append(Stamp(text: Recurrence.describe(recurrence)))
        }
        for tag in task.tags.prefix(2) {
            out.append(Stamp(text: "#\(tag)"))
        }
        if task.source == .voice && task.dueStamp == nil {
            out.append(Stamp(text: "spoken"))
        }
        return out
    }
}
