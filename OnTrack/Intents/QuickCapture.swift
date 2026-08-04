import AppIntents
import Foundation
import SwiftUI

/// Handoff between "something outside the app asked for capture" and the UI.
/// Backed by UserDefaults as well as a notification because at cold launch the
/// intent fires before any view is listening.
enum QuickCaptureBus {
    private static let pendingKey = "pendingQuickCapture"
    static let didChange = Notification.Name("OnTrackQuickCaptureDidChange")
    static let didRequestCapture = Notification.Name("OnTrackDidRequestCapture")

    static func requestCapture() {
        UserDefaults.standard.set(true, forKey: pendingKey)
        NotificationCenter.default.post(name: didRequestCapture, object: nil)
    }

    /// Reads and clears in one go so a request can't fire twice.
    static func consumePendingRequest() -> Bool {
        guard UserDefaults.standard.bool(forKey: pendingKey) else { return false }
        UserDefaults.standard.set(false, forKey: pendingKey)
        return true
    }

    static func announceChange() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

// MARK: - Open the voice capture UI

/// The intent behind Back Tap, the Action Button, and "Hey Siri, capture with
/// On Track". Opens the app straight into listening mode.
struct CaptureWithOnTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture with On Track"
    static let description = IntentDescription("Opens On Track and starts listening so you can speak a task.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickCaptureBus.requestCapture()
        return .result()
    }
}

// MARK: - Add a task without opening the app

/// "Hey Siri, add a task to On Track" — captures and saves entirely in the
/// background, so the phone can stay in your pocket.
struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a task to On Track"
    static let description = IntentDescription("Saves a task. Dates, repeats and priority are worked out for you.")
    static let openAppWhenRun = false

    @Parameter(title: "Task", requestValueDialog: "What needs doing?")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let titles = try await QuickCaptureWriter.save(text: text)
        guard !titles.isEmpty else {
            return .result(dialog: "I didn't catch a task in that.")
        }
        let dialog: IntentDialog = titles.count == 1
            ? "Added \(titles[0])."
            : "Added \(titles.count) tasks."
        return .result(dialog: dialog)
    }
}

// MARK: - Shortcut phrases

struct OnTrackShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureWithOnTrackIntent(),
            phrases: [
                "Capture with \(.applicationName)",
                "Take a note with \(.applicationName)",
                "New task in \(.applicationName)"
            ],
            shortTitle: "Capture",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task to \(.applicationName)",
                "Remind me with \(.applicationName)"
            ],
            shortTitle: "Add task",
            systemImageName: "plus.square"
        )
    }
}

// MARK: - Background writer

/// Saving from an intent can't reach `AppModel`, so this is the standalone path:
/// same parsing, same stores, no UI.
enum QuickCaptureWriter {
    static func save(text: String) async throws -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let auth = SupabaseAuth()
        let session = AppConfig.isBackendConfigured ? await auth.restoreSession() : nil

        let service: any AIService = session != nil ? RemoteAIService(auth: auth) : LocalCaptureParser()
        let store: any TaskStore = session != nil ? SupabaseTaskStore(auth: auth) : LocalTaskStore()

        var result = try? await service.capture(text: trimmed, existingTitles: [])
        if result == nil || result?.tasks.isEmpty == true {
            // Never drop what someone said because the network was unavailable.
            result = try? await LocalCaptureParser().capture(text: trimmed, existingTitles: [])
        }
        guard let captured = result?.tasks, !captured.isEmpty else { return [] }

        let base = Date().timeIntervalSince1970
        let items = captured.enumerated().flatMap { index, task in
            task.materialise(userId: session?.userId, source: .voice, sortIndex: base + Double(index))
        }
        try await store.upsert(items)
        QuickCaptureBus.announceChange()

        return captured.map(\.title)
    }
}
