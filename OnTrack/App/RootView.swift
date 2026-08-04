import SwiftUI

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
                        try? await Task.sleep(for: .seconds(3.5))
                        withAnimation(.easeOut(duration: 0.25)) { model.banner = nil }
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.banner)
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
                        .font(InkType.display(38))
                        .posterCase(tracking: -1.6)
                        .foregroundStyle(Ink.ink)
                    Text(dateStamp)
                        .font(InkType.stamp(10))
                        .stampCase()
                        .foregroundStyle(Ink.inkSoft)
                }

                Spacer()

                HStack(spacing: 8) {
                    InkIconButton(systemName: "bolt.fill", seed: 101) {
                        InkHaptics.tick()
                        model.route = .plan
                    }
                    InkIconButton(systemName: "bubble.left.fill", seed: 102) {
                        InkHaptics.tick()
                        model.route = .chat
                    }
                    InkIconButton(systemName: "line.3.horizontal", seed: 103) {
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
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
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
                Text(message.text)
                    .font(InkType.bodySmall)
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
