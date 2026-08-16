import SwiftUI
import UserNotifications

@main
struct OnTrackApp: App {
    @State private var model = AppModel()
    /// Held here, not just assigned, since UNUserNotificationCenter keeps
    /// only a weak reference to its delegate — nothing else in the app would
    /// otherwise be keeping this one alive.
    @State private var notificationDelegate = NotificationDelegate()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .dynamicTypeSize(...DynamicTypeSize.inkMaxDynamicTypeSize)
                .task {
                    // As early as possible, before anything async — a cold
                    // launch from tapping a notification needs a delegate
                    // already in place to receive that response at all.
                    UNUserNotificationCenter.current().delegate = notificationDelegate
                    await model.bootstrap()
                    consumePendingCapture()
                    consumePendingNotificationAction()

                    #if DEBUG
                    // Jump straight to a screen for design work: -openCapture / -openTyping.
                    let arguments = ProcessInfo.processInfo.arguments
                    if arguments.contains("-openCapture") {
                        model.openQuickCapture(startListening: true)
                    } else if arguments.contains("-openTyping") {
                        model.openQuickCapture(startListening: false)
                    }
                    if arguments.contains("-previewWidget") {
                        model.isPreviewingWidget = true
                    }
                    #endif
                }
                .onOpenURL { url in model.handle(url: url) }
                // Back Tap / Action Button / Siri route through here.
                .onReceive(NotificationCenter.default.publisher(for: QuickCaptureBus.didRequestCapture)) { _ in
                    model.openQuickCapture(startListening: true)
                }
                // A background intent wrote straight to the store — a task,
                // or now a Focus start/pause/stop — pick up the change.
                .onReceive(NotificationCenter.default.publisher(for: QuickCaptureBus.didChange)) { _ in
                    Task {
                        await model.refresh()
                        await model.loadFocus()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    consumePendingCapture()
                    consumePendingNotificationAction()
                    Task { await model.refresh() }
                    // Calendar access can change from iOS Settings while
                    // backgrounded, so it's re-read on every foreground
                    // rather than trusted from whenever it was last checked.
                    Task { await model.refreshCalendarAccessState() }
                    // The live EKEventStoreChanged listener only fires while
                    // the app is actually running — a change made from the
                    // Calendar app itself while backgrounded needs this catch
                    // on the way back in instead.
                    Task { await model.checkForCalendarChangeSinceLastPlan() }
                }
        }
    }

    /// A capture request can arrive before any view exists, so it's parked in
    /// UserDefaults and collected once the UI is up.
    private func consumePendingCapture() {
        if QuickCaptureBus.consumePendingRequest() {
            model.openQuickCapture(startListening: true)
        }
    }

    /// Both call sites run after `model.tasks` is already populated —
    /// `bootstrap()` is awaited first on cold launch, and a warm foreground
    /// only reaches this after the task existed from before backgrounding —
    /// so the lookup by id is expected to succeed rather than racing a load.
    private func consumePendingNotificationAction() {
        guard let pending = PendingNotificationAction.consume(),
              let task = model.tasks.first(where: { $0.id == pending.taskId }) else { return }
        switch pending.kind {
        case .open:
            model.selectedTask = task
        case .markDone:
            Task { await model.toggleDone(task) }
        case .snooze:
            Task { await model.snooze(task) }
        }
    }
}
