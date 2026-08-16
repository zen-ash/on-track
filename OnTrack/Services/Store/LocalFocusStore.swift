import Foundation

/// On-device JSON store for Focus, same shape as `LocalTaskStore` — day-one
/// path before any backend exists, offline cache afterwards.
actor LocalFocusStore: FocusStore {
    private let tracksURL: URL
    private let sessionsURL: URL
    private var tracksCache: [UUID: FocusTrack]?
    private var sessionsCache: [UUID: FocusSession]?

    init(tracksFilename: String = "focus-tracks.json", sessionsFilename: String = "focus-sessions.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tracksURL = dir.appendingPathComponent(tracksFilename)
        sessionsURL = dir.appendingPathComponent(sessionsFilename)
    }

    func loadTracks() async throws -> [FocusTrack] {
        Array(try await allTracks().values)
    }

    func upsertTracks(_ tracks: [FocusTrack]) async throws {
        var current = try await allTracks()
        for track in tracks { current[track.id] = track }
        tracksCache = current
        try persist(current, to: tracksURL)
    }

    func loadSessions(since: Date) async throws -> [FocusSession] {
        try await allSessions().values.filter { $0.startedAt >= since }
    }

    func upsertSessions(_ sessions: [FocusSession]) async throws {
        var current = try await allSessions()
        for session in sessions { current[session.id] = session }
        sessionsCache = current
        try persist(current, to: sessionsURL)
    }

    /// Mirrors the server after a successful fetch, same contract as
    /// `LocalTaskStore.replaceAll`.
    func replaceAll(tracks: [FocusTrack], sessions: [FocusSession]) throws {
        let trackDict = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let sessionDict = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        tracksCache = trackDict
        sessionsCache = sessionDict
        try persist(trackDict, to: tracksURL)
        try persist(sessionDict, to: sessionsURL)
    }

    private func allTracks() async throws -> [UUID: FocusTrack] {
        if let tracksCache { return tracksCache }
        guard FileManager.default.fileExists(atPath: tracksURL.path) else {
            tracksCache = [:]
            return [:]
        }
        let data = try Data(contentsOf: tracksURL)
        let items = try JSONCoding.decoder.decode([FocusTrack].self, from: data)
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        tracksCache = dict
        return dict
    }

    private func allSessions() async throws -> [UUID: FocusSession] {
        if let sessionsCache { return sessionsCache }
        guard FileManager.default.fileExists(atPath: sessionsURL.path) else {
            sessionsCache = [:]
            return [:]
        }
        let data = try Data(contentsOf: sessionsURL)
        let items = try JSONCoding.decoder.decode([FocusSession].self, from: data)
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        sessionsCache = dict
        return dict
    }

    private func persist<T: Encodable>(_ items: [UUID: T], to url: URL) throws {
        let data = try JSONCoding.encoder.encode(Array(items.values))
        try data.write(to: url, options: .atomic)
    }
}
