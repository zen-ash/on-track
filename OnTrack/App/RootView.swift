import SwiftUI
#if DEBUG
import WidgetKit
#endif

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ZStack {
            PaperBackground()

            VStack(spacing: 0) {
                Masthead()
                TodayView()
                CaptureBar()
            }

            if let banner = model.banner {
                BannerView(message: banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: banner.id) {
                        // `id: banner.id` cancels this task the instant a second
                        // banner replaces the first. `try?` would swallow that
                        // cancellation and fall through to clearing `banner`
                        // anyway — wiping out the *new* banner microseconds
                        // after it appeared. Only a sleep that ran to completion
                        // gets to dismiss it.
                        do {
                            try await Task.sleep(for: .seconds(3.5))
                            withAnimation(.easeOut(duration: 0.25)) { model.banner = nil }
                        } catch {}
                    }
            }

            if let pendingUndo = model.pendingUndo {
                UndoToastView(pending: pendingUndo) {
                    InkHaptics.tick()
                    model.confirmUndo()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: pendingUndo.id) {
                    // Same reasoning as the banner above: a swallowed
                    // cancellation here would let a superseded toast's timer
                    // dismiss whatever toast replaced it.
                    do {
                        try await Task.sleep(for: .seconds(4))
                        model.dismissUndo()
                    } catch {}
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.banner)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.pendingUndo)
        // A view merely appearing on screen isn't proactively spoken by
        // VoiceOver unless focus already happens to be there — for a
        // transient message like these, that's exactly the case where it'd
        // otherwise go unheard entirely.
        .onChange(of: model.banner) { _, newValue in
            guard let newValue else { return }
            AccessibilityNotification.Announcement(newValue.text).post()
        }
        .onChange(of: model.pendingUndo) { _, newValue in
            guard let newValue else { return }
            AccessibilityNotification.Announcement(newValue.message).post()
        }
        .sheet(isPresented: $model.isCaptureOpen) {
            CaptureSheet(startListening: model.captureStartsListening)
                .presentationDetents([.height(420), .large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Ink.paper)
        }
        .sheet(item: $model.selectedTask) { task in
            TaskDetailView(task: task)
                .presentationBackground(Ink.paper)
        }
        .sheet(isPresented: routeBinding(for: .chat)) {
            ChatView().presentationBackground(Ink.paper)
        }
        .sheet(isPresented: routeBinding(for: .plan)) {
            PlanView().presentationBackground(Ink.paper)
        }
        .sheet(isPresented: routeBinding(for: .settings)) {
            SettingsView().presentationBackground(Ink.paper)
        }
        #if DEBUG
        .sheet(isPresented: $model.isPreviewingWidget) {
            WidgetPreviewSheet()
        }
        #endif
    }

    /// The route is a single value, but sheets each want their own Bool.
    private func routeBinding(for route: Route) -> Binding<Bool> {
        Binding(
            get: { model.route == route },
            set: { isPresented in
                if isPresented {
                    model.route = route
                } else if model.route == route {
                    model.route = .today
                }
            }
        )
    }
}

// MARK: - Masthead

private struct Masthead: View {
    @Environment(AppModel.self) private var model

    private var dateStamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: -2) {
                    Text("On Track")
                        .inkDisplay(38)
                        .posterCase(tracking: -1.6)
                        .foregroundStyle(Ink.ink)
                    Text(dateStamp)
                        .inkStamp(10)
                        .stampCase()
                        .foregroundStyle(Ink.inkSoft)
                }

                Spacer()

                HStack(spacing: 8) {
                    InkIconButton(systemName: "bolt.fill", seed: 101, accessibilityLabel: "Plan my day") {
                        InkHaptics.tick()
                        model.route = .plan
                    }
                    InkIconButton(systemName: "bubble.left.fill", seed: 102, accessibilityLabel: "Chat") {
                        InkHaptics.tick()
                        model.route = .chat
                    }
                    InkIconButton(systemName: "line.3.horizontal", seed: 103, accessibilityLabel: "Menu") {
                        InkHaptics.tick()
                        model.route = .settings
                    }
                }
            }

            if model.mood.isWorthShowing {
                MascotBanner(mood: model.mood, line: model.moodLine)
            }

            RoughDivider(seed: 77, opacity: 0.35)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.mood)
    }
}

// MARK: - Capture bar

private struct CaptureBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            RoughDivider(seed: 88, opacity: 0.3)
                .padding(.horizontal, 20)

            HStack(spacing: 12) {
                Button {
                    InkHaptics.thud()
                    model.openQuickCapture(startListening: true)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "waveform")
                            .font(.system(size: 17, weight: .black))
                        Text("Speak it")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(InkBlockButtonStyle(seed: 210))

                Button {
                    InkHaptics.tick()
                    model.openQuickCapture(startListening: false)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .black))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(InkOutlineButtonStyle(seed: 211))
                .accessibilityLabel("Type a task")
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
        }
    }
}

#if DEBUG
// MARK: - Widget preview (debug only)

/// Renders the real `TodayWidgetView` — not a lookalike — at approximate
/// widget tile sizes, using whatever is actually in `model.tasks`. The only
/// practical way to check a widget's appearance without Xcode's GUI or
/// dragging one onto a real Home Screen.
private struct WidgetPreviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var entry: TodayEntry {
        TodayEntry(date: Date(), tasks: model.tasks)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Small").inkStamp(11).stampCase()
                tile(width: 155, height: 155) {
                    TodayWidgetView(entry: entry, forcedFamily: .systemSmall)
                }

                Text("Medium").inkStamp(11).stampCase()
                tile(width: 329, height: 155) {
                    TodayWidgetView(entry: entry, forcedFamily: .systemMedium)
                }

                Button("Close") { dismiss() }
                    .buttonStyle(InkOutlineButtonStyle(seed: 999))
            }
            .padding(24)
        }
        .background(Color(white: 0.85))
    }

    private func tile(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(width: width, height: height)
            .background(PaperBackground())
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(radius: 6)
            // Matches the real widget's own cap, so this preview shows what
            // it would actually look like rather than the app's wider range.
            .dynamicTypeSize(...DynamicTypeSize.inkWidgetMaxDynamicTypeSize)
    }
}
#endif

// MARK: - Undo toast

/// Sits above the capture bar rather than up with the banner — a delete, a
/// skip, and "couldn't reach the server" are different registers of news, and
/// stacking both at the top would make an unrelated error look like it undoes
/// the thing you just did.
private struct UndoToastView: View {
    let pending: PendingUndo
    let onUndo: () -> Void

    var body: some View {
        VStack {
            Spacer()

            HStack(spacing: 14) {
                Text(pending.message)
                    .inkBodySmall()
                    .foregroundStyle(Ink.paper)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Button(action: onUndo) {
                    Text("Undo")
                        .inkStamp(11)
                        .stampCase()
                        .foregroundStyle(Ink.paper)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                RoughRect(seed: 909, wobble: 1.8, corner: 5)
                    .fill(Ink.ink)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 86)
        }
    }
}

// MARK: - Banner

private struct BannerView: View {
    let message: BannerMessage

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: message.isError ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .black))
                    .accessibilityHidden(true)
                Text(message.text)
                    .inkBodySmall()
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Ink.paper)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                RoughRect(seed: 313, wobble: 1.8, corner: 5)
                    .fill(message.isError ? Ink.alarm : Ink.ink)
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .padding(.top, 4)
    }
}
