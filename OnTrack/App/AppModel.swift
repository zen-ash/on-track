import EventKit
import Foundation
import Network
import Observation
import SwiftUI
import WidgetKit

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
    /// Armed by delete, skip, and marking a task done — the one place all three
    /// converge so the toast and its 4-second window live in a single spot.
    var pendingUndo: PendingUndo?
    #if DEBUG
    /// Lets -previewWidget render the real TodayWidgetView inside the app,
    /// since there's no way to drag a widget onto the Home Screen from the
    /// command line.
    var isPreviewingWidget = false
    #endif

    /// Off until the user turns it on in Setup. Calendar access is more
    /// sensitive than anything else this app touches, so unlike notifications
    /// it never gets requested on the app's own initiative — only this toggle
    /// triggers the system prompt.
    var calendarAwarenessEnabled: Bool {
        didSet { UserDefaults.standard.set(calendarAwarenessEnabled, forKey: Self.calendarAwarenessKey) }
    }
    /// EventKit's own answer, independent of the toggle above — the user can
    /// turn the toggle on and still decline the system prompt, or revoke
    /// access later from iOS Settings while the app is backgrounded.
    private(set) var calendarAccessState: CalendarService.AccessState = .notDetermined
    private static let calendarAwarenessKey = "calendarAwarenessEnabled"
    /// Set when the calendar changes after a plan already exists for the day
    /// — "your 2pm got cancelled" territory. Cleared by rebuilding, waving it
    /// off, or the existing plan itself going away.
    var calendarChangeNotice: CalendarChangeNotice?

    /// AI surfaces
    private(set) var plan: DayPlan?
    private(set) var isPlanning = false
    var chatHistory: [ChatTurn] = []
    private(set) var isChatting = false
    private(set) var isDeletingAccount = false

    /// Populated on demand by `loadTrash()` when the Trash screen opens, not
    /// kept live like `tasks` — nothing else in the app needs to react to it.
    private(set) var trashedTasks: [TaskItem] = []
    private(set) var isLoadingTrash = false

    // MARK: - Dependencies

    private let localStore = LocalTaskStore()
    private var remoteStore: SupabaseTaskStore?
    private let localAI = LocalCaptureParser()
    private var remoteAI: RemoteAIService?
    private let auth = SupabaseAuth()
    private let reminders = Reminders()
    private let calendarService = CalendarService()
    private let pending = PendingWrites()
    /// Computed rather than stored: it holds nothing but a reference to `auth`,
    /// and @Observable can't synthesise storage for a lazy property.
    private var accountService: AccountService { AccountService(auth: auth) }
    private let connectivity = NWPathMonitor()

    /// Ids with a store write in flight right now. `refresh()` consults this so
    /// a concurrent read that started before the write landed can't clobber it —
    /// see `merge(current:inFlight:...)`. Never touched by any view, so it's
    /// exempt from observation tracking.
    @ObservationIgnored private var inFlightIDs: Set<UUID> = []

    /// The full soft-deleted set behind `trashedTasks` (which hides a
    /// subtask trashed alongside its parent) — kept around so
    /// `restoreFromTrash`/`permanentlyDelete` can find and carry those
    /// subtasks along without a second network round trip.
    @ObservationIgnored private var trashedRaw: [TaskItem] = []

    /// The busy blocks the current plan was actually built against, so a
    /// later calendar-change notification has something to compare the fresh
    /// read to. Empty whenever calendar awareness wasn't in play for it.
    @ObservationIgnored private var planBusyBlocksSnapshot: [BusyBlock] = []
    /// Runs for the app's lifetime once started; there's no toggle-driven
    /// start/stop because checkForCalendarChangeSinceLastPlan() already no-ops
    /// cheaply whenever calendar awareness is off or there's no plan to be
    /// stale, and EKEventStoreChanged notifications require nothing this
    /// doesn't already have permission to listen for.
    @ObservationIgnored private var calendarChangeObserver: Task<Void, Never>?

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

    init() {
        calendarAwarenessEnabled = UserDefaults.standard.bool(forKey: Self.calendarAwarenessKey)
    }

    func bootstrap() async {
        if AppConfig.isBackendConfigured, let restored = await auth.restoreSession() {
            adopt(session: restored)
        }
        await refresh()
        await refreshCalendarAccessState()
        startWatchingConnectivity()
        startWatchingCalendarChanges()
        // Fire-and-forget: nothing on screen waits for this, and the Trash
        // view applies the same 30-day cutoff itself if this hasn't run yet.
        Task { await purgeExpiredTrash() }

        #if DEBUG
        if DemoSeed.isRequested && tasks.isEmpty {
            let sample = DemoSeed.tasks()
            applyLocally(sample)
            try? await store.upsert(sample)
            // Every other mutator calls this after writing; seeding bypassed
            // it, which meant the widget snapshot never got written and a
            // screenshot run showed a populated list but an empty widget.
            await notifyDataChanged()
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
        // Send anything still queued while we can still authenticate as this user.
        await flushPending()
        await pending.clearAll()

        await auth.signOut()
        session = nil
        remoteStore = nil
        remoteAI = nil
        plan = nil
        chatHistory = []

        // The local store is now a mirror of the signed-in user's list, so it
        // has to be cleared — otherwise their tasks reappear in local mode.
        try? await localStore.replaceAll([])
        await refresh()
    }

    /// Permanently deletes the account and every task on the server, then wipes
    /// every local trace. Required by App Store guideline 5.1.1(v), but it also
    /// has to be honest: for an anonymous account there is no recovery path at
    /// all, because the credential in the Keychain *is* the account.
    @discardableResult
    func deleteAccount() async -> Bool {
        guard session != nil else { return false }
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await accountService.deleteAccount()
        } catch {
            show(error)
            return false
        }

        // Server side is gone; now remove everything held on the device.
        await pending.clearAll()
        try? await localStore.replaceAll([])
        await auth.signOut()

        session = nil
        remoteStore = nil
        remoteAI = nil
        plan = nil
        chatHistory = []
        tasks = []
        selectedTask = nil
        await notifyDataChanged()

        show(message: "Account deleted. Nothing is left on the server.")
        return true
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

        // An offline launch can't restore the session, which would otherwise
        // strand the app in local mode until the next relaunch. Retry here so
        // regaining connectivity is enough to reconnect.
        if AppConfig.isBackendConfigured, session == nil,
           let restored = await auth.restoreSession() {
            adopt(session: restored)
        }

        // Send anything queued offline before reading, so the server is current.
        await flushPending()

        let outstanding = await pending.snapshot()

        // Captured right before the network read: if a delete, an undo, or a
        // skip lands in between this line and `loadAll()` returning, the read
        // it raced against is stale, not the in-memory state — see `merge`.
        let beforeFetch = tasks
        let inFlightAtFetch = inFlightIDs

        do {
            let loaded = try await store.loadAll()
            // Mirror the server so the list stays readable without a network.
            if remoteStore != nil {
                try? await localStore.replaceAll(loaded)
            }
            // Whatever is still queued never reached the server. Merging it back
            // in is what stops a refresh from deleting work captured offline.
            tasks = Self.merge(
                current: beforeFetch,
                inFlight: inFlightAtFetch,
                server: loaded,
                pendingUpserts: outstanding.upserts,
                pendingDeletes: Set(outstanding.deletes)
            )
        } catch {
            // Offline. Fall back to the last synced copy plus anything queued,
            // rather than showing an empty list — reading the list is the one
            // thing that should never require a network.
            guard remoteStore != nil else {
                show(error)
                return
            }
            let cached = (try? await localStore.loadAll()) ?? []
            tasks = Self.merge(
                current: beforeFetch,
                inFlight: inFlightAtFetch,
                server: cached,
                pendingUpserts: outstanding.upserts,
                pendingDeletes: Set(outstanding.deletes)
            )
            // Deliberately silent: being offline is a state, not an error, and
            // the queue means nothing is at risk.
        }

        await notifyDataChanged()
    }

    /// Local edits win over a same-or-older server snapshot.
    ///
    /// Two separate reasons a task in `current` might not match `server`:
    /// queued writes (`pendingUpserts`/`pendingDeletes`, already durable on
    /// disk, applied last so they always win) and writes that were merely in
    /// flight — issued, not yet confirmed — at the moment `server` was read
    /// (`inFlight`, sourced from `current`). Without the second case, a
    /// refresh whose read straddles a delete, an undo, or a skip can silently
    /// resurrect the row being deleted or drop the one just restored, because
    /// nothing about that write ever touched the offline retry queue.
    ///
    /// Anything else missing from `server` is trusted as a real deletion —
    /// one made on another device — and stays gone, matching
    /// `LocalTaskStore.replaceAll`'s contract that a refresh propagates
    /// deletions rather than merging around them.
    private static func merge(
        current: [TaskItem],
        inFlight: Set<UUID>,
        server: [TaskItem],
        pendingUpserts: [TaskItem],
        pendingDeletes: Set<UUID>
    ) -> [TaskItem] {
        var byID = Dictionary(server.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })

        for id in inFlight {
            if let local = currentByID[id] {
                byID[id] = local
            } else {
                byID.removeValue(forKey: id)
            }
        }

        for item in pendingUpserts { byID[item.id] = item }
        for id in pendingDeletes { byID.removeValue(forKey: id) }
        return Array(byID.values)
    }

    /// Best effort. If it fails we're still offline and the queue simply waits.
    private func flushPending() async {
        guard remoteStore != nil else { return }
        let outstanding = await pending.snapshot()
        guard !outstanding.upserts.isEmpty || !outstanding.deletes.isEmpty else { return }

        if !outstanding.upserts.isEmpty {
            do {
                try await store.upsert(outstanding.upserts)
                await pending.clearUpserts(outstanding.upserts.map(\.id))
            } catch {
                return
            }
        }
        if !outstanding.deletes.isEmpty {
            do {
                try await store.delete(ids: outstanding.deletes)
                await pending.clearDeletes(outstanding.deletes)
            } catch {
                return
            }
        }
    }

    /// Flush the moment the network comes back, rather than waiting for the
    /// user to background and reopen the app.
    private func startWatchingConnectivity() {
        // @Sendable is required: NWPathMonitor's handler is not declared
        // Sendable, so without it the closure inherits this type's @MainActor
        // isolation and traps when called on the monitor's own queue.
        connectivity.pathUpdateHandler = { @Sendable [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                guard let self, self.remoteStore != nil else { return }
                if await !self.pending.isEmpty {
                    await self.refresh()
                }
            }
        }
        connectivity.start(queue: DispatchQueue(label: "com.aayush.ontrack.connectivity"))
    }

    /// EKEventStoreChanged is coarse and system-wide — it fires for any
    /// change to any calendar, not just today's, and not just ones this app
    /// would call "busy". checkForCalendarChangeSinceLastPlan() is what
    /// decides whether a given firing actually meant anything.
    private func startWatchingCalendarChanges() {
        calendarChangeObserver?.cancel()
        calendarChangeObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                guard let self else { return }
                await self.checkForCalendarChangeSinceLastPlan()
            }
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
        var spawnedId: UUID?

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
            spawnedId = spawned.id
        }

        applyLocally(toWrite)
        InkHaptics.done()

        // Only the forward action arms undo — reopening is already the undo of
        // an earlier "done", and shouldn't chain into a second toast.
        if markingDone {
            pendingUndo = PendingUndo(
                message: "Done: “\(task.title)”",
                restore: [task],
                removeIfUndone: spawnedId.map { [$0] } ?? []
            )
        }

        let ids = toWrite.map(\.id)
        inFlightIDs.formUnion(ids)
        defer { inFlightIDs.subtract(ids) }
        do {
            try await store.upsert(toWrite)
            await notifyDataChanged()
        } catch {
            await queueForLater(toWrite, error: error)
        }
    }

    func add(_ captured: [CapturedTask], source: TaskSource) async {
        guard !captured.isEmpty else { return }
        let base = (tasks.map(\.sortIndex).max() ?? 0) + 1
        let items = captured.enumerated().flatMap { index, task in
            task.materialise(userId: session?.userId, source: source, sortIndex: base + Double(index))
        }
        applyLocally(items)
        let ids = items.map(\.id)
        inFlightIDs.formUnion(ids)
        defer { inFlightIDs.subtract(ids) }
        do {
            try await store.upsert(items)
            await notifyDataChanged()
        } catch {
            await queueForLater(items, error: error)
        }
    }

    func update(_ task: TaskItem) async {
        var updated = task
        updated.updatedAt = Date()
        applyLocally([updated])
        inFlightIDs.insert(updated.id)
        defer { inFlightIDs.remove(updated.id) }
        do {
            try await store.upsert([updated])
            await notifyDataChanged()
        } catch {
            await queueForLater([updated], error: error)
        }
    }

    /// A soft delete, not a real one: the row is upserted with `deletedAt`
    /// set rather than removed from the store, so it lands in Trash instead
    /// of vanishing the moment the undo toast times out. `PendingUndo` still
    /// restores from `removed` — the untouched pre-delete copies — so
    /// confirming undo within the toast's window is a second, independent
    /// path back to the same place Trash would eventually offer.
    func delete(_ task: TaskItem) async {
        let removed = [task] + subtasks(of: task)
        let ids = removed.map(\.id)
        tasks.removeAll { ids.contains($0.id) }
        pendingUndo = PendingUndo(message: "Deleted “\(task.title)”", restore: removed, removeIfUndone: [])

        let deletedAt = Date()
        let trashed = removed.map { item -> TaskItem in
            var copy = item
            copy.deletedAt = deletedAt
            copy.updatedAt = deletedAt
            return copy
        }

        inFlightIDs.formUnion(ids)
        defer { inFlightIDs.subtract(ids) }
        do {
            try await store.upsert(trashed)
            await notifyDataChanged()
        } catch {
            await pending.enqueueUpserts(trashed)
        }
    }

    // MARK: - Trash

    /// How long a deleted task stays recoverable before the sweep in
    /// `purgeExpiredTrash()` removes it for real.
    private static let trashRetentionDays = 30

    private static func trashCutoff() -> Date {
        Calendar.current.date(byAdding: .day, value: -trashRetentionDays, to: Date()) ?? .distantPast
    }

    /// Fetches everything soft-deleted in the last 30 days. Only top-level
    /// rows are shown — a subtask trashed alongside its parent (the common
    /// case: deleting a task takes its subtasks with it) isn't worth a row of
    /// its own, since restoring or purging the parent already carries it
    /// along. A subtask deleted on its own, with its parent still live, does
    /// get a row — `restoreFromTrash`/`permanentlyDelete` key off `trashedRaw`
    /// to know which case they're in.
    func loadTrash() async {
        isLoadingTrash = true
        defer { isLoadingTrash = false }
        do {
            let cutoff = Self.trashCutoff()
            let live = try await store.loadTrash().filter { ($0.deletedAt ?? .distantPast) >= cutoff }
            let liveIDs = Set(live.map(\.id))
            trashedRaw = live
            trashedTasks = live
                .filter { $0.parentId == nil || !liveIDs.contains($0.parentId!) }
                .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        } catch {
            show(error)
        }
    }

    /// Clears `deletedAt` on this row and any of its own subtasks that were
    /// trashed alongside it, and moves them back into the live list.
    func restoreFromTrash(_ task: TaskItem) async {
        let group = [task] + trashedRaw.filter { $0.parentId == task.id }
        let restored = group.map { item -> TaskItem in
            var copy = item
            copy.deletedAt = nil
            copy.updatedAt = Date()
            return copy
        }
        let ids = Set(restored.map(\.id))
        trashedTasks.removeAll { ids.contains($0.id) }
        trashedRaw.removeAll { ids.contains($0.id) }
        applyLocally(restored)

        do {
            try await store.upsert(restored)
            await notifyDataChanged()
        } catch {
            await pending.enqueueUpserts(restored)
        }
    }

    /// Deletes this row for real, right now — the one place `store.delete`
    /// still means "gone," not "trashed." Cascades to any subtask trashed
    /// alongside it, same grouping `restoreFromTrash` uses.
    func permanentlyDelete(_ task: TaskItem) async {
        let group = [task] + trashedRaw.filter { $0.parentId == task.id }
        let ids = group.map(\.id)
        trashedTasks.removeAll { ids.contains($0.id) }
        trashedRaw.removeAll { ids.contains($0.id) }

        do {
            try await store.delete(ids: ids)
        } catch {
            await pending.enqueueDeletes(ids)
        }
    }

    /// Best-effort background hygiene, run once per launch. Anything past its
    /// 30 days is purged for real; a failure here just means the next launch
    /// (or the next time Trash is opened, which applies the same cutoff) gets
    /// another attempt — nothing user-facing depends on this succeeding.
    private func purgeExpiredTrash() async {
        do {
            let cutoff = Self.trashCutoff()
            let expired = try await store.loadTrash().filter { ($0.deletedAt ?? .distantPast) < cutoff }
            guard !expired.isEmpty else { return }
            try await store.delete(ids: expired.map(\.id))
        } catch {
            // Silent: see doc comment above.
        }
    }

    /// Moves a recurring task to its next occurrence in place — same id, same
    /// notes/tags/subtasks, only the due date changes. The alternative to
    /// deleting it outright when "not this one" is what you mean, not "never
    /// again."
    func skipRecurrence(_ task: TaskItem) async {
        guard let rule = task.recurrence,
              let due = task.dueAt,
              let next = Recurrence.nextDate(after: due, rule: rule) else { return }

        var updated = task
        updated.dueAt = next
        updated.updatedAt = Date()
        applyLocally([updated])
        InkHaptics.tick()
        pendingUndo = PendingUndo(message: "Skipped “\(task.title)”", restore: [task], removeIfUndone: [])

        inFlightIDs.insert(updated.id)
        defer { inFlightIDs.remove(updated.id) }
        do {
            try await store.upsert([updated])
            await notifyDataChanged()
        } catch {
            await queueForLater([updated], error: error)
        }
    }

    /// Reverses whatever's currently toasted: restores the pre-action snapshot
    /// and removes anything that action spawned (a recurring task's next
    /// occurrence, on undoing "done"). The action itself already happened —
    /// this is a second write, not a rollback of one still in flight.
    func confirmUndo() {
        guard let undo = pendingUndo else { return }
        pendingUndo = nil

        Task {
            let ids = undo.restore.map(\.id) + undo.removeIfUndone
            inFlightIDs.formUnion(ids)
            defer { inFlightIDs.subtract(ids) }

            if !undo.removeIfUndone.isEmpty {
                tasks.removeAll { undo.removeIfUndone.contains($0.id) }
                try? await store.delete(ids: undo.removeIfUndone)
            }
            applyLocally(undo.restore)
            do {
                try await store.upsert(undo.restore)
                await notifyDataChanged()
            } catch {
                await queueForLater(undo.restore, error: error)
            }
        }
    }

    /// Lets the toast's own timer (or a second undo-able action superseding
    /// this one) clear it without reversing anything.
    func dismissUndo() {
        pendingUndo = nil
    }

    /// A write that didn't reach the server is queued rather than lost, and the
    /// message says so — "couldn't reach the model" was misleading when the
    /// task itself also hadn't been saved.
    private func queueForLater(_ items: [TaskItem], error: Error) async {
        guard remoteStore != nil else {
            show(error)
            return
        }
        await pending.enqueueUpserts(items)
        show(message: "Saved on this phone. It'll sync when you're back online.")
    }

    /// The one place every mutator converges on, so the widget and local
    /// notifications can't drift out of sync with what the list actually says.
    private func notifyDataChanged() async {
        // Cheap, local, and has no permission dialog to block on, so — unlike
        // reminders below — this runs even during a seeded demo/screenshot run.
        WidgetSnapshotStore.write(tasks)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.today)

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
                // Shown first so that if the write also fails, the sync notice
                // from `add` replaces it — where the task ended up matters more
                // than which parser produced it.
                if case AIError.rateLimited(let message) = error {
                    // Hitting a cap isn't a failure to explain away: say what
                    // happened, and note the task was still captured.
                    show(message: "\(message) Saved using on-device parsing.")
                } else {
                    show(message: "Parsed on this phone — the model wasn't reachable.")
                }
                await add(fallback.tasks, source: source)
                return fallback
            }
            show(error)
            return nil
        }
    }

    func buildPlan() async {
        isPlanning = true
        defer { isPlanning = false }
        // A fresh plan is itself the update a pending notice was offering —
        // whether the user got here by accepting it or just hit refresh.
        calendarChangeNotice = nil
        do {
            let busy = (calendarAwarenessEnabled && calendarAccessState == .authorized)
                ? await calendarService.busyBlocks(on: Date())
                : []
            planBusyBlocksSnapshot = busy
            plan = try await ai.plan(tasks: tasks, calendarBusy: busy)
        } catch {
            show(error)
        }
    }

    // MARK: - Calendar

    /// Called by the Settings toggle. Turning it off never touches EventKit —
    /// there's no permission to ask to stop doing something. Turning it on
    /// requests access only if that hasn't already been decided; if it has
    /// (either way), this just re-reads the answer.
    func setCalendarAwareness(enabled: Bool) async {
        calendarAwarenessEnabled = enabled
        guard enabled else { return }
        await calendarService.requestAccess()
        await refreshCalendarAccessState()
    }

    /// The system permission can change underneath the app — revoked from iOS
    /// Settings while backgrounded, or decided for the first time just now —
    /// so this re-reads it rather than trusting whatever was true at launch.
    func refreshCalendarAccessState() async {
        calendarAccessState = await calendarService.accessState
    }

    /// Called after a live EKEventStoreChanged notification, and again on
    /// every foreground — the live notification only fires while the app
    /// itself is running, so a change made from the Calendar app while On
    /// Track was backgrounded would otherwise go unnoticed until the next
    /// plan was built anyway, silently.
    func checkForCalendarChangeSinceLastPlan() async {
        guard plan != nil, !isPlanning,
              calendarAwarenessEnabled, calendarAccessState == .authorized else { return }

        let current = await calendarService.busyBlocks(on: Date())
        guard let notice = CalendarChangeNotice.forChange(from: planBusyBlocksSnapshot, to: current) else { return }

        calendarChangeNotice = notice
        // Recorded now, not just on rebuild — otherwise a second change
        // arriving before the user acts on the first notice would compare
        // against an already-stale snapshot and never notice anything new.
        planBusyBlocksSnapshot = current
    }

    func rebuildPlanForCalendarChange() async {
        calendarChangeNotice = nil
        await buildPlan()
    }

    func dismissCalendarChangeNotice() {
        calendarChangeNotice = nil
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
        calendarChangeNotice = nil
        route = .today
        let ids = updates.map(\.id)
        inFlightIDs.formUnion(ids)
        defer { inFlightIDs.subtract(ids) }
        do {
            try await store.upsert(updates)
        } catch {
            show(error)
        }
    }

    func dismissPlan() {
        plan = nil
        calendarChangeNotice = nil
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
            let ids = children.map(\.id)
            inFlightIDs.formUnion(ids)
            defer { inFlightIDs.subtract(ids) }
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
        case "today":
            // Where the Home Screen widget's tap target lands. Today is
            // already the default screen, but naming the route explicitly
            // means that stays true even if the default ever changes.
            route = .today
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

/// A reversible action waiting out its toast. `restore` is the exact
/// pre-action snapshot to write back; `removeIfUndone` is anything the action
/// spawned that undo should also remove (a recurring task's next occurrence,
/// created the moment its predecessor was marked done).
struct PendingUndo: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let restore: [TaskItem]
    let removeIfUndone: [UUID]
}

/// "Your 2pm got cancelled — want an updated plan?" The comparison never
/// touches what either block *is*, only when — consistent with busy blocks
/// never carrying a title anywhere else in the app.
struct CalendarChangeNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String

    /// nil when there's nothing worth saying — the two snapshots match, or
    /// the diff isn't the kind of thing this can describe a single time for.
    static func forChange(from old: [BusyBlock], to new: [BusyBlock]) -> CalendarChangeNotice? {
        guard old != new else { return nil }

        let removed = old.filter { !new.contains($0) }
        let added = new.filter { !old.contains($0) }

        let message: String
        if removed.count == 1, added.isEmpty {
            message = "Your \(timeLabel(removed[0].start)) commitment is gone — want an updated plan?"
        } else if added.count == 1, removed.isEmpty {
            message = "Something new landed on your calendar at \(timeLabel(added[0].start)) — want an updated plan?"
        } else {
            message = "Your calendar changed since this plan was built — want an updated plan?"
        }
        return CalendarChangeNotice(message: message)
    }

    private static func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
