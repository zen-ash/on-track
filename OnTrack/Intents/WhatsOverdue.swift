import AppIntents
import Foundation

/// "Hey Siri, what's overdue in On Track" — reads today's late tasks back out
/// loud without opening the app. Read-only counterpart to the two capture
/// intents in QuickCapture.swift; registered alongside them there, so the
/// full set of shortcut phrases lives in one place.
struct WhatsOverdueIntent: AppIntent {
    static let title: LocalizedStringResource = "What's overdue in On Track"
    static let description = IntentDescription("Reads back what's overdue. Read-only — nothing changes, and the app never opens.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await OverdueSummary.speak()))
    }
}

/// The actual work, kept separate from the intent so it's plain Swift to
/// test — same reasoning as `QuickCaptureWriter`: an intent can't reach the
/// running `AppModel`, so this reads for itself.
enum OverdueSummary {
    /// A live read, not the widget's cached snapshot: a device that only ever
    /// hears from Siri and never opens the app would otherwise be stuck
    /// speaking whatever was true whenever the snapshot last happened to be
    /// written, which might be a relaunch — or a sync — ago.
    static func speak() async -> String {
        let auth = SupabaseAuth()
        let session = AppConfig.isBackendConfigured ? await auth.restoreSession() : nil
        let store: any TaskStore = session != nil ? SupabaseTaskStore(auth: auth) : LocalTaskStore()

        let tasks = (try? await store.loadAll()) ?? []
        return phrase(for: tasks)
    }

    /// Pure, so the wording can be checked without touching a store or Siri.
    /// Oldest-due-first, same ordering the app uses everywhere else, capped
    /// at three named titles so Siri isn't reading out a database dump.
    static func phrase(for tasks: [TaskItem]) -> String {
        let overdue = tasks
            .filter { $0.status == .open && $0.parentId == nil && $0.isOverdue }
            .inWorkingOrder()

        guard !overdue.isEmpty else { return "Nothing's overdue." }
        if overdue.count == 1 { return "One thing's late: \(overdue[0].title)." }

        let named = overdue.prefix(3).map(\.title)
        let remainder = overdue.count - named.count
        var pieces = named
        if remainder > 0 {
            pieces.append(remainder == 1 ? "1 more" : "\(remainder) more")
        }
        return "\(overdue.count) things are late: \(naturalJoin(pieces))."
    }

    /// "a" · "a and b" · "a, b, and c" — an Oxford comma, because Siri reading
    /// "a b and c" back with no pause is worse than one extra comma.
    private static func naturalJoin(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        let connector = items.count == 2 ? " and " : ", and "
        return items.dropLast().joined(separator: ", ") + connector + last
    }
}
