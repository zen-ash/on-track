import SwiftUI

/// Morning triage. The model proposes an order and a focus; you accept the whole
/// thing or walk away. Deliberately not editable inline — arguing with the plan
/// is what the chat surface is for.
struct PlanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: 0) {
                header

                if model.isPlanning {
                    working
                } else if let plan = model.plan {
                    planBody(plan)
                } else {
                    intro
                }
            }
        }
        .task {
            if model.plan == nil && !model.isPlanning {
                await model.buildPlan()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Today's plan")
                        .font(InkType.title(24))
                        .posterCase(tracking: -0.8)
                        .foregroundStyle(Ink.ink)
                    Text(model.isFullyCapable ? "Proposed, not imposed" : "On-device triage")
                        .font(InkType.stamp(10))
                        .stampCase()
                        .foregroundStyle(Ink.inkSoft)
                }
                Spacer()
                InkIconButton(systemName: "xmark", seed: 901) {
                    model.dismissPlan()
                    dismiss()
                }
            }
            RoughDivider(seed: 902, opacity: 0.32)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var working: some View {
        VStack(spacing: 16) {
            Spacer()
            MascotView(mood: .thinking).frame(width: 110, height: 110)
            Text("Reading your list")
                .font(InkType.stamp(11)).stampCase()
                .foregroundStyle(Ink.inkSoft)
            Spacer()
        }
    }

    private var intro: some View {
        VStack(spacing: 16) {
            Spacer()
            MascotView(mood: .watching).frame(width: 110, height: 110)
            Text("Nothing to plan.")
                .font(InkType.title(20)).posterCase()
                .foregroundStyle(Ink.ink)
            Button("Try again") { Task { await model.buildPlan() } }
                .buttonStyle(InkOutlineButtonStyle(seed: 903))
            Spacer()
        }
    }

    private func planBody(_ plan: DayPlan) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    focusCard(plan)

                    ForEach(PlanSlot.allCases, id: \.self) { slot in
                        let items = plan.items.filter { $0.slot == slot }.sorted { $0.order < $1.order }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionRule(title: slot.label, trailing: "\(items.count)", seed: 910 + UInt64(slot.rawValue.count))
                                ForEach(items) { item in
                                    planRow(item)
                                }
                            }
                        }
                    }

                    if !plan.deferIds.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionRule(title: "Push to tomorrow", trailing: "\(plan.deferIds.count)", seed: 930)
                            ForEach(plan.deferIds, id: \.self) { id in
                                if let task = model.tasks.first(where: { $0.id == id }) {
                                    Text(task.title)
                                        .font(InkType.bodySmall)
                                        .foregroundStyle(Ink.inkSoft)
                                        .strikethrough(color: Ink.inkFaint)
                                }
                            }
                        }
                    }

                    if let note = plan.note, !note.isEmpty {
                        Text(note)
                            .font(InkType.bodySmall)
                            .foregroundStyle(Ink.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        await model.applyPlan()
                        dismiss()
                    }
                } label: {
                    Text("Use this plan").frame(maxWidth: .infinity)
                }
                .buttonStyle(InkBlockButtonStyle(seed: 940))

                Button {
                    Task { await model.buildPlan() }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .black))
                }
                .buttonStyle(InkOutlineButtonStyle(seed: 941))
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
    }

    private func focusCard(_ plan: DayPlan) -> some View {
        InkCard(seed: 950, emphasised: true) {
            VStack(alignment: .leading, spacing: 7) {
                Text("The one that matters")
                    .font(InkType.stamp(10)).stampCase()
                    .foregroundStyle(Ink.inkSoft)
                Text(plan.focus)
                    .font(InkType.title(21))
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func planRow(_ item: PlanItem) -> some View {
        Group {
            if let task = model.tasks.first(where: { $0.id == item.taskId }) {
                HStack(alignment: .top, spacing: 11) {
                    Text(String(format: "%02d", item.order + 1))
                        .font(InkType.stamp(12))
                        .foregroundStyle(Ink.inkSoft)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(InkType.body)
                            .foregroundStyle(Ink.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.reason)
                            .font(InkType.bodySmall)
                            .foregroundStyle(Ink.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
        }
    }
}
