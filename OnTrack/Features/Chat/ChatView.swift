import SwiftUI

/// Conversational surface over the whole list. The model can read and edit
/// tasks through tools on the server, so "push everything this week back two
/// days" is a real instruction, not a search box.
struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private let suggestions = [
        "What should I do first?",
        "What's overdue?",
        "Move everything today to tomorrow",
        "Break down my biggest task"
    ]

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: 0) {
                header
                transcript
                composer
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Talk to it")
                        .inkTitle(24)
                        .posterCase(tracking: -0.8)
                        .foregroundStyle(Ink.ink)
                    Text(model.isFullyCapable ? "It can change your list" : "Needs the backend")
                        .inkStamp(10)
                        .stampCase()
                        .foregroundStyle(Ink.inkSoft)
                }
                Spacer()
                // Purely decorative here — the "thinking" indicator lower in
                // the transcript already says so in words while it's active.
                MascotView(mood: model.isChatting ? .thinking : .watching)
                    .frame(width: 42, height: 42)
                    .accessibilityHidden(true)
                InkIconButton(systemName: "xmark", seed: 801, accessibilityLabel: "Close") { dismiss() }
            }
            RoughDivider(seed: 802, opacity: 0.32)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.chatHistory.isEmpty {
                        emptyPrompt
                    }

                    ForEach(model.chatHistory) { turn in
                        bubble(turn)
                            .id(turn.id)
                    }

                    if model.isChatting {
                        HStack(spacing: 10) {
                            MascotView(mood: .thinking).frame(width: 30, height: 30)
                            Text("thinking")
                                .inkStamp(10).stampCase()
                                .foregroundStyle(Ink.inkSoft)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
            }
            .onChange(of: model.chatHistory.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(model.chatHistory.last?.id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask it anything about your list.")
                .inkHeading(18)
                .foregroundStyle(Ink.ink)

            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    draft = suggestion
                    send()
                } label: {
                    HStack {
                        Text(suggestion)
                            .inkBodySmall()
                            .foregroundStyle(Ink.ink)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Ink.inkSoft)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(
                        RoughRect(seed: suggestion.inkSeed, wobble: 1.5, corner: 4)
                            .stroke(Ink.ink.opacity(0.32), lineWidth: 1.3)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
    }

    private func bubble(_ turn: ChatTurn) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if turn.role == .user { Spacer(minLength: 40) }

            Text(turn.text)
                .inkBody()
                .foregroundStyle(turn.role == .user ? Ink.paper : Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background {
                    if turn.role == .user {
                        RoughRect(seed: turn.id.uuidString.inkSeed, wobble: 1.7, corner: 5).fill(Ink.ink)
                    } else {
                        RoughRect(seed: turn.id.uuidString.inkSeed, wobble: 1.7, corner: 5)
                            .stroke(Ink.ink.opacity(0.5), lineWidth: 1.4)
                    }
                }

            if turn.role == .assistant { Spacer(minLength: 40) }
        }
        // Alignment and colour carry "who said this" visually — a screen
        // reader gets neither, so it needs to be said explicitly.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(turn.role == .user ? "You" : "On Track") said: \(turn.text)")
    }

    private var composer: some View {
        VStack(spacing: 0) {
            RoughDivider(seed: 803, opacity: 0.3).padding(.horizontal, 22)

            HStack(spacing: 10) {
                TextField("Say what you want changed", text: $draft, axis: .vertical)
                    .inkBody()
                    .foregroundStyle(Ink.ink)
                    .tint(Ink.ink)
                    .focused($isFocused)
                    .lineLimit(1...4)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(
                        RoughRect(seed: 804, wobble: 1.6, corner: 5)
                            .stroke(Ink.ink.opacity(0.4), lineWidth: 1.4)
                    )

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(Ink.paper)
                        .frame(width: 44, height: 44)
                        .background(RoughRect(seed: 805, wobble: 1.6, corner: 5).fill(Ink.ink))
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || model.isChatting)
                .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    private func send() {
        let text = draft
        draft = ""
        InkHaptics.tick()
        Task { await model.send(chatMessage: text) }
    }
}
