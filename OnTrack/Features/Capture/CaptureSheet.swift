import SwiftUI

/// The single capture surface. Whether you got here from the Back Tap gesture,
/// the Action Button, Control Centre, Siri or the in-app button, this is what
/// opens — one path, one behaviour.
struct CaptureSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var startListening: Bool

    @State private var transcriber = VoiceTranscriber()
    @State private var typed = ""
    @State private var phase: Phase = .idle
    @State private var created: [CapturedTask] = []
    @State private var reply: String?
    @FocusState private var isTypingFocused: Bool

    private enum Phase: Equatable {
        case idle
        case listening
        case typing
        case working
        case done
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            switch phase {
            case .done:
                resultView
            default:
                captureView
            }

            Spacer(minLength: 0)
            controls
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .background(PaperBackground())
        .task {
            if startListening {
                await beginListening()
            } else {
                phase = .typing
                isTypingFocused = true
            }
        }
        .onDisappear {
            Task { await transcriber.stop() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(InkType.title(24))
                    .posterCase(tracking: -0.8)
                    .foregroundStyle(Ink.ink)
                Text(subhead)
                    .font(InkType.stamp(10))
                    .stampCase()
                    .foregroundStyle(Ink.inkSoft)
            }

            Spacer()

            MascotView(mood: mascotMood)
                .frame(width: 46, height: 46)

            InkIconButton(systemName: "xmark", seed: 501) {
                Task {
                    await transcriber.stop()
                    dismiss()
                }
            }
        }
        .padding(.bottom, 14)
    }

    private var captureView: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoughDivider(seed: 502, opacity: 0.3)

            if phase == .typing {
                TextField("What needs doing?", text: $typed, axis: .vertical)
                    .font(InkType.body)
                    .foregroundStyle(Ink.ink)
                    .tint(Ink.ink)
                    .focused($isTypingFocused)
                    .lineLimit(1...6)
                    .submitLabel(.done)
                    .onSubmit { Task { await save(text: typed, source: .text) } }
            } else {
                transcriptView
            }

            if phase == .listening {
                Waveform(level: transcriber.level)
                    .frame(height: 44)
            }

            if case .failed(let message) = transcriber.state {
                Text(message)
                    .font(InkType.bodySmall)
                    .foregroundStyle(Ink.alarm)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var transcriptView: some View {
        ScrollView {
            Group {
                if transcriber.combinedText.isEmpty {
                    Text(phase == .working ? "Working on it…" : "Listening. Say the thing.")
                        .foregroundStyle(Ink.inkFaint)
                } else {
                    Text(transcriptText)
                }
            }
            .font(InkType.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 84, maxHeight: 180)
    }

    /// Committed text is solid, the in-flight guess is ghosted — you can watch
    /// the recogniser make up its mind.
    private var transcriptText: AttributedString {
        var final = AttributedString(transcriber.finalText)
        final.foregroundColor = Ink.ink

        guard !transcriber.volatileText.isEmpty else { return final }

        var volatile = AttributedString((transcriber.finalText.isEmpty ? "" : " ") + transcriber.volatileText)
        volatile.foregroundColor = Ink.inkSoft
        return final + volatile
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoughDivider(seed: 503, opacity: 0.3)

            if let reply, !reply.isEmpty {
                Text(reply)
                    .font(InkType.heading(17))
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(created) { task in
                InkCard(seed: task.title.inkSeed) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(task.title)
                            .font(InkType.body)
                            .foregroundStyle(Ink.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 5) {
                            if let due = task.dueAt {
                                StampLabel(text: Self.stamp(for: due, hasTime: task.hasTime), seed: 611)
                            }
                            if let recurrence = task.recurrence {
                                StampLabel(text: Recurrence.describe(recurrence), seed: 612)
                            }
                            if task.priority > 0 {
                                StampLabel(text: String(repeating: "!", count: task.priority), filled: task.priority == 3, seed: 613)
                            }
                            ForEach(task.tags.prefix(2), id: \.self) { tag in
                                StampLabel(text: "#\(tag)", seed: 614)
                            }
                        }

                        if !task.subtasks.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(task.subtasks, id: \.self) { step in
                                    Text("— \(step)")
                                        .font(InkType.bodySmall)
                                        .foregroundStyle(Ink.inkSoft)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            switch phase {
            case .listening:
                Button {
                    Task { await finishListening() }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "stop.fill").font(.system(size: 15, weight: .black))
                        Text("Stop & save")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(InkBlockButtonStyle(seed: 520))

            case .typing:
                Button {
                    Task { await save(text: typed, source: .text) }
                } label: {
                    Text("Save").frame(maxWidth: .infinity)
                }
                .buttonStyle(InkBlockButtonStyle(seed: 521))
                .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)

                Button {
                    Task { await beginListening() }
                } label: {
                    Image(systemName: "waveform").font(.system(size: 16, weight: .black))
                }
                .buttonStyle(InkOutlineButtonStyle(seed: 522))

            case .working:
                HStack(spacing: 10) {
                    ProgressView().tint(Ink.ink)
                    Text("Sorting that out…")
                        .font(InkType.stamp(11)).stampCase()
                        .foregroundStyle(Ink.inkSoft)
                }
                .frame(maxWidth: .infinity)

            case .done:
                Button {
                    dismiss()
                } label: {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(InkBlockButtonStyle(seed: 523))

                Button {
                    resetForAnother()
                } label: {
                    Image(systemName: "plus").font(.system(size: 16, weight: .black))
                }
                .buttonStyle(InkOutlineButtonStyle(seed: 524))

            case .idle:
                Button {
                    Task { await beginListening() }
                } label: {
                    Text("Start listening").frame(maxWidth: .infinity)
                }
                .buttonStyle(InkBlockButtonStyle(seed: 525))
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Behaviour

    private func beginListening() async {
        phase = .listening
        isTypingFocused = false
        InkHaptics.thud()
        await transcriber.start()
        if case .failed = transcriber.state {
            // No mic, no model, no problem — fall back to typing rather than dead-ending.
            phase = .typing
            isTypingFocused = true
        }
    }

    private func finishListening() async {
        let text = await transcriber.stop()
        await save(text: text, source: .voice)
    }

    private func save(text: String, source: TaskSource) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            dismiss()
            return
        }
        phase = .working
        let result = await model.capture(text: trimmed, source: source)
        created = result?.tasks ?? []
        reply = result?.reply
        if created.isEmpty {
            InkHaptics.nope()
            phase = .typing
            typed = trimmed
            isTypingFocused = true
        } else {
            InkHaptics.done()
            phase = .done
        }
    }

    private func resetForAnother() {
        created = []
        reply = nil
        typed = ""
        transcriber.reset()
        Task { await beginListening() }
    }

    // MARK: - Copy

    private var headline: String {
        switch phase {
        case .listening: return "Listening"
        case .working: return "Reading it"
        case .done: return created.count == 1 ? "Added" : "Added \(created.count)"
        default: return "Capture"
        }
    }

    private var subhead: String {
        switch phase {
        case .listening: return "On device — nothing is uploaded"
        case .typing: return model.isFullyCapable ? "Dates and repeats get parsed" : "On-device parsing"
        case .done: return "Swipe down to close"
        default: return "Say it or type it"
        }
    }

    private var mascotMood: MascotMood {
        switch phase {
        case .listening: return .listening
        case .working: return .thinking
        case .done: return .pleased
        default: return .watching
        }
    }

    private static func stamp(for date: Date, hasTime: Bool) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = hasTime ? "'today' h:mm a" : "'today'"
        } else if Calendar.current.isDateInTomorrow(date) {
            formatter.dateFormat = hasTime ? "'tomorrow' h:mm a" : "'tomorrow'"
        } else {
            formatter.dateFormat = hasTime ? "d MMM h:mm a" : "d MMM"
        }
        return formatter.string(from: date)
    }
}

// MARK: - Waveform

/// Ink bars that respond to the mic. Deliberately chunky and irregular rather
/// than a smooth sine — it should look drawn, not synthesised.
private struct Waveform: View {
    var level: Float
    private let barCount = 26

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let spacing: CGFloat = 3
                let barWidth = (size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)
                var rng = SeededRNG(0x5EED)

                for i in 0..<barCount {
                    // Centre bars react most, so the shape reads as a voice.
                    let distanceFromCentre = abs(CGFloat(i) - CGFloat(barCount - 1) / 2) / (CGFloat(barCount) / 2)
                    let envelope = 1 - distanceFromCentre * 0.75
                    let wobble = 0.55 + 0.45 * sin(t * 9 + Double(i) * 0.7)
                    let idle = rng.value(in: 0.06...0.14)
                    let height = max(
                        size.height * idle,
                        size.height * CGFloat(level) * envelope * CGFloat(wobble)
                    )

                    let x = CGFloat(i) * (barWidth + spacing)
                    let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(Ink.ink))
                }
            }
        }
    }
}
