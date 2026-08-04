import Foundation
import Observation
import SwiftUI

/// Which screen is up. Kept as explicit state rather than NavigationPath because
/// quick-capture can be launched from outside the app and must be able to take
/// over regardless of where the user was.
enum Route: Hashable {
    case today
    case chat
    case plan
    case settings
}

@MainActor
@Observable
final class AppModel {
    // MARK: - State

    private(set) var tasks: [TaskItem] = []
    private(set) var isLoading = false
    var route: Route = .today

    /// Nil until sign-in, and stays nil forever in local mode.
    private(set) var session: Session?
    var isLocalMode: Bool { !AppConfig.isBackendConfigured }

    /// Presentation
    var isCaptureOpen = false
    var captureStartsListening = false
    var selectedTask: TaskItem?
    var banner: BannerMessage?

    /// AI surfaces
    private(set) var plan: DayPlan?
    private(set) var isPlanning = false
    var chatHistory: [ChatTurn] = []
    private(set) var isChatting = false

    // MARK: - Dependencies

    private let localStore = LocalTaskStore()
    private var remoteStore: SupabaseTaskStore?
    private let localAI = LocalCaptureParser()
    private var remoteAI: RemoteAIService?
    private let auth = SupabaseAuth()
    private let reminders = Reminders()

    /// The store that owns the truth right now.
    private var store: any TaskStore {
        remoteStore ?? localStore
    }

    /// The model that answers right now. Falls back to on-device when there's no
    /// backend or no session.
    var ai: any AIService {
        remoteAI ?? localAI
    }

    var isFullyCapable: Bool { ai.isFullyCapable }

    // MARK: - Lifecycle

    func bootstrap() async {
        if AppConfig.isBackendConfigured, let restored = await auth.restoreSession() {
            adopt(session: restored)
        }
        await refresh()

        #if DEBUG
        if DemoSeed.isRequested && tasks.isEmpty {
            let sample = DemoSeed.tasks()
            applyLocally(sample)
            try? await store.upsert(sample)
        }
        #endif
    }

    private func adopt(session: Session) {
        self.session = session
        self.remoteStore = SupabaseTaskStore(auth: auth)
        self.remoteAI = RemoteAIService(auth: auth)
    }

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async {
        do {
            let session = try await auth.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
            adopt(session: session)
            try await migrateLocalTasksIfNeeded()
            await refresh()
        } catch {
            show(error)
        }
    }

    func continueWithoutAccount() async {
        // Anonymous Supabase user: gives real sync + AI without Apple's paid
        // developer program, and can be upgraded to a real account later.
        do {
            let session = try await auth.signInAnonymously()
            adopt(session: session)
            try await migrateLocalTasksIfNeeded()
            await refresh()
        } catch {
            show(error)
        }
    }

    func signOut() async {
        await auth.signOut()
        session = nil
        remoteStore = nil
        remoteAI = nil
        plan = nil
        chatHistory = []
        await refresh()
    }

    /// Anything captured before signing in should follow the user up to the server.
    private func migrateLocalTasksIfNeeded() async throws {
        let local = try await localStore.loadAll()
        guard !local.isEmpty, let remoteStore else { return }
        let stamped = local.map { task -> TaskItem in
            var copy = task
            copy.userId = session?.userId
            return copy
        }
        try await remoteStore.upsert(stamped)
        try await localStore.delete(ids: local.map(\.id))
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tasks = try await store.loadAll()
            await syncReminders()
        } catch {
            show(error)
        }
    }

    // MARK: - Derived views of the list

    /// Top-level open tasks, late first.
    var openTasks: [TaskItem] {
        tasks.filter { $0.status == .open && $0.parentId == nil }.inWorkingOrder()
    }

    var overdueTasks: [TaskItem] {
        openTasks.filter(\.isOverdue)
    }

    var todayTasks: [TaskItem] {
        openTasks.filter { !$0.isOverdue && ($0.isDueToday || $0.dueAt == nil) }
    }

    var upcomingTasks: [TaskItem] {
        openTasks.filter { !$0.isOverdue && !$0.isDueToday && $0.dueAt != nil }
    }

    var completedToday: [TaskItem] {
        tasks.filter { task in
            guard task.status == .done, let at = task.completedAt else { return false }
            return Calendar.current.isDateInToday(at)
        }
    }

    func subtasks(of task: TaskItem) -> [TaskItem] {
        tasks.filter { $0.parentId == task.id }.sorted { $0.sortIndex < $1.sortIndex }
    }

    var mood: MascotMood {
        if isChatting || isPlanning { return .thinking }
        return MascotVoice.mood(
            overdue: overdueTasks.count,
            dueToday: todayTasks.count,
            doneToday: completedToday.count
        )
    }

    var moodLine: String {
        MascotVoice.line(
            for: mood,
            overdue: overdueTasks.count,
            done: completedToday.count,
            remaining: openTasks.count
        )
    }

    // MARK: - Mutations

    func toggleDone(_ task: TaskItem) async {
        var updated = task
        let markingDone = task.status != .done
        updated.status = markingDone ? .done : .open
        updated.completedAt = markingDone ? Date() : nil
        updated.updatedAt = Date()

        var toWrite = [updated]

        // A recurring task doesn't end when you finish it — it moves.
        if markingDone,
           let rule = task.recurrence,
           let due = task.dueAt,
           let next = Recurrence.nextDate(after: due, rule: rule) {
            var spawned = task
            spawned.id = UUID()
            spawned.dueAt = next
            spawned.status = .open
            spawned.completedAt = nil
            spawned.createdAt = Date()
            spawned.updatedAt = Date()
            toWrite.append(spawned)
        }

        applyLocally(toWrite)
        InkHaptics.done()

        do {
            try await store.upsert(toWrite)
            await syncReminders()
        } catch {
            show(error)
            await refresh()
        }
    }

    func add(_ captured: [CapturedTask], source: TaskSource) async {
        guard !captured.isEmpty else { return }
        let base = (tasks.map(\.sortIndex).max() ?? 0) + 1
        let items = captured.enumerated().flatMap { index, task in
            task.materialise(userId: session?.userId, source: source, sortIndex: base + Double(index))
        }
        applyLocally(items)
        do {
            try await store.upsert(items)
            await syncReminders()
        } catch {
            show(error)
        }
    }

    func update(_ task: TaskItem) async {
        var updated = task
        updated.updatedAt = Date()
        applyLocally([updated])
        do {
            try await store.upsert([updated])
            await syncReminders()
        } catch {
            show(error)
        }
    }

    func delete(_ task: TaskItem) async {
        let children = subtasks(of: task).map(\.id)
        let ids = [task.id] + children
        tasks.removeAll { ids.contains($0.id) }
        do {
            try await store.delete(ids: ids)
            await syncReminders()
        } catch {
            show(error)
        }
    }

    private func syncReminders() async {
        #if DEBUG
        // Seeded demo data is for screenshots — it shouldn't schedule dozens of
        // real notifications on the device it's running on.
        if DemoSeed.isRequested { return }
        #endif
        await reminders.sync(with: tasks)
    }

    /// Optimistic local write so the UI never waits on the network.
    private func applyLocally(_ items: [TaskItem]) {
        for item in items {
            if let index = tasks.firstIndex(where: { $0.id == item.id }) {
                tasks[index] = item
            } else {
                tasks.append(item)
            }
        }
    }

    // MARK: - AI

    func capture(text: String, source: TaskSource) async -> CaptureResult? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        do {
            let result = try await ai.capture(text: trimmed, existingTitles: openTasks.map(\.title))
            await add(result.tasks, source: source)
            return result
        } catch {
            // Never lose what someone said. If the model is unreachable, parse
            // it on device and keep going.
            if let fallback = try? await localAI.capture(text: trimmed, existingTitles: []), !fallback.tasks.isEmpty {
                await add(fallback.tasks, source: source)
                show(message: "Saved offline — couldn't reach the model.")
                return fallback
            }
            show(error)
            return nil
        }
    }

    func buildPlan() async {
        isPlanning = true
        defer { isPlanning = false }
        do {
            plan = try await ai.plan(tasks: tasks)
        } catch {
            show(error)
        }
    }

    func applyPlan() async {
        guard let plan else { return }
        // The plan's ordering becomes the list's ordering.
        var updates: [TaskItem] = []
        for item in plan.items {
            guard var task = tasks.first(where: { $0.id == item.taskId }) else { continue }
            task.sortIndex = Double(item.order)
            task.updatedAt = Date()
            updates.append(task)
        }
        for id in plan.deferIds {
            guard var task = tasks.first(where: { $0.id == id }) else { continue }
            // Defer, don't delete — pushing to tomorrow is reversible.
            task.dueAt = Calendar.current.date(byAdding: .day, value: 1, to: task.dueAt ?? Date())
            task.updatedAt = Date()
            updates.append(task)
        }
        applyLocally(updates)
        self.plan = nil
        route = .today
        do {
            try await store.upsert(updates)
        } catch {
            show(error)
        }
    }

    func dismissPlan() {
        plan = nil
    }

    func send(chatMessage text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chatHistory.append(ChatTurn(role: .user, text: trimmed))
        isChatting = true
        defer { isChatting = false }

        do {
            let reply = try await ai.chat(history: chatHistory, tasks: tasks)
            chatHistory.append(ChatTurn(role: .assistant, text: reply.message))
            if reply.didMutate { await refresh() }
        } catch {
            chatHistory.append(ChatTurn(role: .assistant, text: error.localizedDescription))
        }
    }

    func breakDown(_ task: TaskItem) async {
        do {
            let steps = try await ai.breakdown(task: task)
            let base = (subtasks(of: task).map(\.sortIndex).max() ?? task.sortIndex) + 0.001
            let children = steps.enumerated().map { index, title in
                TaskItem(
                    userId: session?.userId,
                    title: title,
                    parentId: task.id,
                    sortIndex: base + Double(index) / 1000,
                    source: .ai
                )
            }
            applyLocally(children)
            try await store.upsert(children)
        } catch {
            show(error)
        }
    }

    // MARK: - Quick capture entry point

    /// Called by the deep link, the App Intent, and the in-app button alike.
    func openQuickCapture(startListening: Bool) {
        captureStartsListening = startListening
        isCaptureOpen = true
    }

    func handle(url: URL) {
        guard url.scheme == AppConfig.appScheme else { return }
        switch url.host {
        case "capture":
            openQuickCapture(startListening: true)
        case "type":
            openQuickCapture(startListening: false)
        case "plan":
            route = .plan
        case "chat":
            route = .chat
        default:
            break
        }
    }

    // MARK: - Messaging

    func show(_ error: Error) {
        banner = BannerMessage(text: error.localizedDescription, isError: true)
    }

    func show(message: String) {
        banner = BannerMessage(text: message, isError: false)
    }
}

struct BannerMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var isError: Bool
}
