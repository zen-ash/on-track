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

    private func loadAllAsDictionary() async throws -> [UUID: TaskItem] {
        if let cache { return cache }
        _ = try await loadAll()
        return cache ?? [:]
    }

    private func persist(_ items: [UUID: TaskItem]) throws {
        let data = try JSONCoding.encoder.encode(Array(items.values))
        try data.write(to: fileURL, options: .atomic)
    }
}

/// Shared coders. Snake case on the wire matches the Postgres columns exactly,
/// so the same `TaskItem` round-trips through both stores untouched.
enum JSONCoding {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = DateParsing.iso8601(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(raw)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DateParsing.iso8601String(date))
        }
        return e
    }()
}

enum DateParsing {
    /// Postgres hands back timestamps with a variable number of fractional
    /// digits and sometimes no zone, so try the tolerant paths in order.
    // Foundation's date formatters are documented as safe for concurrent
    // formatting once configured, but they aren't marked Sendable.
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let postgresNoZone: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    static func iso8601(_ raw: String) -> Date? {
        if let d = withFraction.date(from: raw) { return d }
        if let d = plain.date(from: raw) { return d }
        // Trim fractional seconds Postgres sometimes emits at odd precisions.
        if let dot = raw.firstIndex(of: "."),
           let plus = raw.range(of: "+", range: dot..<raw.endIndex) ?? raw.range(of: "Z", range: dot..<raw.endIndex) {
            let trimmed = String(raw[raw.startIndex..<dot]) + String(raw[plus.lowerBound...])
            if let d = plain.date(from: trimmed) { return d }
        }
        return postgresNoZone.date(from: String(raw.prefix(19)))
    }

    static func iso8601String(_ date: Date) -> String {
        withFraction.string(from: date)
    }
}
