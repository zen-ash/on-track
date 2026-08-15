import Foundation

/// On-device JSON store. This is the day-one path — the app is fully usable
/// before any backend exists — and it stays the offline cache afterwards.
actor LocalTaskStore: TaskStore {
    private let fileURL: URL
    private var cache: [UUID: TaskItem]?

    init(filename: String = "tasks.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent(filename)
    }

    func loadAll() async throws -> [TaskItem] {
        try await allCached().filter { $0.deletedAt == nil }
    }

    func loadTrash() async throws -> [TaskItem] {
        try await allCached().filter { $0.deletedAt != nil }
    }

    private func allCached() async throws -> [TaskItem] {
        if let cache { return Array(cache.values) }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cache = [:]
            return []
        }
        let data = try Data(contentsOf: fileURL)
        let items = try JSONCoding.decoder.decode([TaskItem].self, from: data)
        cache = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return items
    }

    func upsert(_ tasks: [TaskItem]) async throws {
        var current = try await loadAllAsDictionary()
        for task in tasks { current[task.id] = task }
        cache = current
        try persist(current)
    }

    func delete(ids: [UUID]) async throws {
        var current = try await loadAllAsDictionary()
        for id in ids { current.removeValue(forKey: id) }
        cache = current
        try persist(current)
    }

    /// Overwrites the file with exactly these tasks.
    ///
    /// Used to mirror the server after a successful fetch, so the list is still
    /// readable with no network. Deletions made on another device propagate
    /// because this replaces rather than merges.
    func replaceAll(_ tasks: [TaskItem]) throws {
        let current = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        cache = current
        try persist(current)
    }

    /// Everything on disk, live and trashed alike — what `upsert`/`delete`
    /// actually mutate. Unlike `loadAll()`, nothing here is filtered out.
    private func loadAllAsDictionary() async throws -> [UUID: TaskItem] {
        if let cache { return cache }
        _ = try await allCached()
        return cache ?? [:]
    }

    private func persist(_ items: [UUID: TaskItem]) throws {
        let data = try JSONCoding.encoder.encode(Array(items.values))
        try data.write(to: fileURL, options: .atomic)
    }
}
