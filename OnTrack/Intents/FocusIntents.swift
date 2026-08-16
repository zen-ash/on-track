import AppIntents
import Foundation
import WidgetKit

/// A track, exposed to Siri/Shortcuts as a real entity rather than a plain
/// string — so "start focusing on Learning" gets genuine disambiguation
/// ("did you mean Learning or LinkedIn?") and the Shortcuts app can offer an
/// actual picker of your current tracks, instead of a name match that just
/// silently fails on a mishear or a typo.
struct FocusTrackEntity: AppEntity {
    let id: UUID
    let name: String

    init(track: FocusTrack) {
        id = track.id
        name = track.name
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Focus Track"
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static let defaultQuery = FocusTrackEntityQuery()
}

struct FocusTrackEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [FocusTrackEntity] {
        let all = try await FocusIntentWriter.loadActiveTracks()
        return all.filter { identifiers.contains($0.id) }.map(FocusTrackEntity.init(track:))
    }

    /// Backs the spoken/typed-text path ("focus on learning") with a loose
    /// substring match, while `entities(for:)` above still backs the exact
    /// picker path from the Shortcuts app.
    func entities(matching string: String) async throws -> [FocusTrackEntity] {
        let all = try await FocusIntentWriter.loadActiveTracks()
        let lowered = string.lowercased()
        return all
            .filter { $0.name.lowercased().contains(lowered) }
            .map(FocusTrackEntity.init(track:))
    }

    /// What the Shortcuts app / Siri disambiguation shows when it lists your
    /// tracks rather than matching a typed name — archived ones excluded,
    /// same as the picker inside the app itself.
    func suggestedEntities() async throws -> [FocusTrackEntity] {
        try await FocusIntentWriter.loadActiveTracks().map(FocusTrackEntity.init(track:))
    }
}

// MARK: - Start / resume

/// "Hey Siri, start focusing on Learning" — starts a fresh session, or
/// resumes one that's currently paused on the same track. Any other track
/// still running or paused gets finalised first, the same "only one thing
/// at a time" rule the in-app Focus tab follows.
struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Focus"
    static let description = IntentDescription("Starts tracking time against one of your Focus tracks. Resumes it if it was paused.")
    static let openAppWhenRun = false

    @Parameter(title: "Track")
    var track: FocusTrackEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await FocusIntentWriter.start(trackId: track.id, trackName: track.name)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Pause

/// "Hey Siri, pause focus" — stops the clock without ending the session, the
/// same bathroom-break case the in-app Pause button covers.
struct PauseFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Focus"
    static let description = IntentDescription("Pauses whatever's currently running, without ending the session.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await FocusIntentWriter.pause()))
    }
}

// MARK: - Stop

/// "Hey Siri, stop focusing" — ends whatever's running or paused and logs it.
struct StopFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Focus"
    static let description = IntentDescription("Ends whatever's currently running or paused, and logs the time.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await FocusIntentWriter.stop()))
    }
}

// MARK: - Background writer

/// Same reasoning as `QuickCaptureWriter`: an intent can't reach the running
/// `AppModel`, so this reads and writes `ActiveFocusState`/`FocusStore` for
/// itself, using the exact same crash-safe recovery record the app's own
/// Focus tab reads and writes — whichever one touched it last is what's true
/// the next time either looks.
enum FocusIntentWriter {
    private static func store() async -> (store: any FocusStore, userId: UUID?) {
        let auth = SupabaseAuth()
        let session = AppConfig.isBackendConfigured ? await auth.restoreSession() : nil
        let store: any FocusStore = session != nil ? SupabaseFocusStore(auth: auth) : LocalFocusStore()
        return (store, session?.userId)
    }

    static func loadActiveTracks() async throws -> [FocusTrack] {
        let (store, _) = await store()
        return try await store.loadTracks()
            .filter { !$0.isArchived }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    static func start(trackId: UUID, trackName: String) async -> String {
        let (store, userId) = await store()

        if var current = ActiveFocusRecovery.load() {
            if current.trackId == trackId {
                guard current.isPaused else { return "Already focusing on \(trackName)." }
                let now = Date()
                current.runningSince = now
                ActiveFocusRecovery.save(current)
                announceChange()
                reloadWidget()
                await FocusNudgeScheduler.schedule(trackName: trackName, runningSince: now)
                await FocusLiveActivityController.update(state: current)
                return "Resumed \(trackName)."
            }
            await finalise(current, store: store, userId: userId)
        }

        let now = Date()
        let state = ActiveFocusState(sessionId: UUID(), trackId: trackId, startedAt: now, accumulatedSeconds: 0, runningSince: now)
        ActiveFocusRecovery.save(state)
        announceChange()
        reloadWidget()
        await FocusNudgeScheduler.schedule(trackName: trackName, runningSince: now)
        await FocusLiveActivityController.start(trackName: trackName, state: state)
        return "Focusing on \(trackName)."
    }

    static func pause() async -> String {
        guard var state = ActiveFocusRecovery.load() else { return "Nothing's running right now." }
        guard let runningSince = state.runningSince else { return "Already paused." }
        state.accumulatedSeconds += max(0, Int(Date().timeIntervalSince(runningSince)))
        state.runningSince = nil
        ActiveFocusRecovery.save(state)
        announceChange()
        reloadWidget()
        FocusNudgeScheduler.cancel() // paused is clearly still-attended.
        await FocusLiveActivityController.update(state: state)
        return "Paused."
    }

    static func stop() async -> String {
        guard let state = ActiveFocusRecovery.load() else { return "Nothing's running right now." }
        let (store, userId) = await store()
        let seconds = await finalise(state, store: store, userId: userId)
        announceChange()
        return seconds > 0 ? "Logged \(spoken(seconds))." : "Stopped."
    }

    @discardableResult
    private static func finalise(_ state: ActiveFocusState, store: any FocusStore, userId: UUID?) async -> Int {
        var state = state
        if let runningSince = state.runningSince {
            state.accumulatedSeconds += max(0, Int(Date().timeIntervalSince(runningSince)))
        }
        ActiveFocusRecovery.clear()
        FocusNudgeScheduler.cancel() // whatever was running is finalised either way — start()'s track-switch case re-arms it for the new track right after this returns.
        await FocusLiveActivityController.end() // same reasoning — start()'s track-switch case re-attaches right after.
        guard state.accumulatedSeconds > 0 else {
            reloadWidget() // activeFocus still cleared, even with nothing logged.
            return 0
        }

        let session = FocusSession(
            id: state.sessionId,
            userId: userId,
            trackId: state.trackId,
            startedAt: state.startedAt,
            endedAt: Date(),
            accumulatedSeconds: state.accumulatedSeconds
        )
        try? await store.upsertSessions([session])
        // A real session was logged — today's totals actually changed, so
        // the file snapshot (not just ActiveFocusState) needs rewriting too.
        let tracks = (try? await store.loadTracks()) ?? []
        let sessions = (try? await store.loadSessions(since: Calendar.current.startOfDay(for: Date()))) ?? []
        FocusWidgetSnapshotStore.write(tracks: tracks, todaysSessions: sessions)
        reloadWidget()
        return state.accumulatedSeconds
    }

    private static func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.focus)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.combined) // same reasoning as AppModel's own combined reload — Siri's writes need to reach it too.
    }

    private static func spoken(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 1 { return "under a minute" }
        if minutes == 1 { return "1 minute" }
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        return "\(hours)h \(remainder)m"
    }

    /// Wakes a running app's foreground listener the same way a background
    /// capture already does — QuickCaptureBus exists for exactly this, no
    /// need for a second bus just for Focus.
    private static func announceChange() {
        QuickCaptureBus.announceChange()
    }
}
