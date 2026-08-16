import SwiftUI
#if DEBUG
import WidgetKit
#endif

/// The app's two persistent screens — what to do, and what you're actually
/// doing right now. Plan/Chat/Settings stay reachable as sheets from the
/// To-Do tab's header rather than getting tabs of their own: they're each a
/// brief errand, not something you'd sit in for a while the way either of
/// these two is.
private enum MainTab: Hashable {
    case today
    case focus
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedTab: MainTab = .today

    var body: some View {
        @Bindable var model = model

        ZStack {
            PaperBackground()

            VStack(spacing: 0) {
                Group {
                    switch selectedTab {
                    case .today:
                        VStack(spacing: 0) {
                            Masthead()
                            TodayView()
                            CaptureBar()
                        }
                    case .focus:
                        FocusView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                TabBar(selected: $selectedTab)
            }
            // The Focus widget's tap target: a deep link has no tab of its
            // own to land on, so it asks via `route` the same way it would
            // ask for a sheet, and this is what actually acts on it.
            .onChange(of: model.route) { _, newValue in
                guard newValue == .focus else { return }
                selectedTab = .focus
                model.route = .today
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
        .onChange(of: model.calendarChangeNotice) { _, newValue in
            guard let newValue else { return }
            AccessibilityNotification.Announcement(newValue.message).post()
        }
        // A real question, not a status update — unlike the banner/toast
        // above, this doesn't auto-dismiss, since missing it just means the
        // plan quietly goes on being stale rather than anything reversible.
        .confirmationDialog(
            model.calendarChangeNotice?.message ?? "",
            isPresented: Binding(
                get: { model.calendarChangeNotice != nil },
                set: { isPresented in if !isPresented { model.dismissCalendarChangeNotice() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Update the plan") {
                Task {
                    await model.rebuildPlanForCalendarChange()
                    model.route = .plan
                }
            }
            Button("Not now", role: .cancel) {
                model.dismissCalendarChangeNotice()
            }
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

// MARK: - Tab bar

/// Hand-drawn on purpose, not SwiftUI's native `TabView` — this app has no
/// system chrome anywhere else (no navigation bars, no native search field),
/// and a stock tab bar would be the one part of the screen that didn't look
/// like it belonged to it.
private struct TabBar: View {
    @Binding var selected: MainTab

    var body: some View {
        VStack(spacing: 0) {
            RoughDivider(seed: 70, opacity: 0.32)
            HStack(spacing: 0) {
                tabButton(.today, label: "To-Do", systemName: "checklist")
                tabButton(.focus, label: "Timer", systemName: "timer")
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .background(Ink.paper)
    }

    private func tabButton(_ tab: MainTab, label: String, systemName: String) -> some View {
        let isSelected = selected == tab
        return Button {
            guard selected != tab else { return }
            InkHaptics.tick()
            selected = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .black))
                Text(label)
                    .inkStamp(10)
                    .stampCase()
            }
            .foregroundStyle(isSelected ? Ink.ink : Ink.inkFaint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Masthead

private struct Masthead: View {
    @Environment(AppModel.self) private var model
    @State private var isShowingConflicts = false

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

            // Lives here rather than tucked in Settings — a silently
            // overwritten edit is exactly the kind of thing that shouldn't
            // need a trip through a menu to notice.
            if !model.conflicts.isEmpty {
                ConflictBanner(count: model.conflicts.count) {
                    InkHaptics.tick()
                    isShowingConflicts = true
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
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.conflicts.count)
        .sheet(isPresented: $isShowingConflicts) {
            ConflictsView().presentationBackground(Ink.paper)
        }
    }
}

/// Tappable summary row — count and a chevron, not the conflicts themselves,
/// since resolving one is a real decision (which version to keep) that
/// deserves its own screen rather than being squeezed into the header.
private struct ConflictBanner: View {
    let count: Int
    let action: () -> Void

    private var message: String {
        count == 1 ? "1 task changed on another device" : "\(count) tasks changed on another device"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Ink.alarm)
                    .accessibilityHidden(true)
                Text(message)
                    .inkBodySmall()
                    .foregroundStyle(Ink.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Ink.inkFaint)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoughRect(seed: 105, wobble: 1.6, corner: 5)
                    .stroke(Ink.alarm.opacity(0.6), lineWidth: 1.4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(message)
        .accessibilityHint("Opens the list to review and resolve them.")
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

    private var focusEntry: FocusEntry {
        FocusEntry(date: Date(), tracks: model.focusTracks, todaysSessions: model.todaysFocusSessions, active: model.activeFocus)
    }

    private var combinedEntry: CombinedEntry {
        CombinedEntry(date: Date(), tasks: model.tasks, tracks: model.focusTracks, todaysSessions: model.todaysFocusSessions, active: model.activeFocus)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Today — Small").inkStamp(11).stampCase()
                tile(width: 155, height: 155) {
                    TodayWidgetView(entry: entry, forcedFamily: .systemSmall)
                }

                Text("Today — Medium").inkStamp(11).stampCase()
                tile(width: 329, height: 155) {
                    TodayWidgetView(entry: entry, forcedFamily: .systemMedium)
                }

                Text("Focus — Small").inkStamp(11).stampCase()
                tile(width: 155, height: 155) {
                    FocusWidgetView(entry: focusEntry, forcedFamily: .systemSmall)
                }

                Text("Focus — Medium").inkStamp(11).stampCase()
                tile(width: 329, height: 155) {
                    FocusWidgetView(entry: focusEntry, forcedFamily: .systemMedium)
                }

                Text("Tasks & Focus — Medium").inkStamp(11).stampCase()
                tile(width: 329, height: 155) {
                    CombinedWidgetView(entry: combinedEntry)
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
            // 86 clears the capture bar alone; the tab bar underneath it
            // now adds its own height below that on every screen, not just
            // the To-Do tab, since this toast is a global overlay.
            .padding(.bottom, 86 + 64)
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
