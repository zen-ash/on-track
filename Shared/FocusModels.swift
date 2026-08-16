import Foundation

/// A user-defined category to log time against — "Learning", "Networking",
/// "Job applying". Archived rather than deleted so a past session's track
/// name never goes dangling once you stop using it.
struct FocusTrack: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var userId: UUID?
    var name: String
    var sortIndex: Double
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID? = nil,
        name: String,
        sortIndex: Double = 0,
        archivedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.sortIndex = sortIndex
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Deterministic, not stored — same trick as `TaskItem.seed`, derived
    /// from the id so it's stable without needing its own column (and
    /// without risking an id-hash overflowing Postgres's signed bigint).
    var seed: UInt64 { id.uuidString.inkSeed }

    var isArchived: Bool { archivedAt != nil }
}

extension FocusTrack {
    enum CodingKeys: String, CodingKey {
        case id, userId, name, sortIndex, archivedAt, createdAt, updatedAt
    }

    /// Every key present unconditionally, `archivedAt` included — see
    /// `TaskItem.encode(to:)` for why: PostgREST's bulk upsert rejects a
    /// batch where objects don't share an identical key set.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sortIndex, forKey: .sortIndex)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try encodeOptional(userId, forKey: .userId, in: &container)
        try encodeOptional(archivedAt, forKey: .archivedAt, in: &container)
    }

    private func encodeOptional<T: Encodable>(
        _ value: T?,
        forKey key: CodingKeys,
        in container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }
}

/// One continuous start-to-stop act of tracking time against a track. A
/// pause inside a session doesn't create a new row — it just stops the
/// clock without ending the session, so `accumulatedSeconds` is the total
/// *active* time, already excluding whatever time was spent paused.
struct FocusSession: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var userId: UUID?
    var trackId: UUID
    var startedAt: Date
    /// Nil only transiently in memory while a session is being finalised —
    /// every session that's actually reached the store has one.
    var endedAt: Date?
    var accumulatedSeconds: Int
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID? = nil,
        trackId: UUID,
        startedAt: Date,
        endedAt: Date? = nil,
        accumulatedSeconds: Int = 0,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.trackId = trackId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.accumulatedSeconds = accumulatedSeconds
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension FocusSession {
    enum CodingKeys: String, CodingKey {
        case id, userId, trackId, startedAt, endedAt, accumulatedSeconds, note, createdAt, updatedAt
    }

    /// Same reasoning as `FocusTrack.encode(to:)` and `TaskItem.encode(to:)`.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(trackId, forKey: .trackId)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(accumulatedSeconds, forKey: .accumulatedSeconds)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try encodeOptional(userId, forKey: .userId, in: &container)
        try encodeOptional(endedAt, forKey: .endedAt, in: &container)
        try encodeOptional(note, forKey: .note, in: &container)
    }

    private func encodeOptional<T: Encodable>(
        _ value: T?,
        forKey key: CodingKeys,
        in container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }
}
