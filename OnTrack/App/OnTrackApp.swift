import SwiftUI

@main
struct OnTrackApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task {
                    await model.bootstrap()
                    consumePendingCapture()

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
                // A background intent wrote straight to the store; pick up the change.
                .onReceive(NotificationCenter.default.publisher(for: QuickCaptureBus.didChange)) { _ in
                    Task { await model.refresh() }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    consumePendingCapture()
                    Task { await model.refresh() }
                    // Calendar access can change from iOS Settings while
                    // backgrounded, so it's re-read on every foreground
                    // rather than trusted from whenever it was last checked.
                    Task { await model.refreshCalendarAccessState() }
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
}
