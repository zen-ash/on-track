import Foundation

enum TaskStatus: String, Codable, Sendable, CaseIterable {
    case open
    case done
    case dropped
}

enum TaskEnergy: String, Codable, Sendable, CaseIterable {
    case low, medium, high
}

/// Where a task came from. Drives the little source stamp on the row and lets
/// us tell the model which of its own suggestions the user actually kept.
enum TaskSource: String, Codable, Sendable {
    case voice
    case text
    case ai
    case manual
}

struct TaskItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var userId: UUID?
    var title: String
    var notes: String?
    var status: TaskStatus
    /// 0 = none, 1 = low, 2 = medium, 3 = high. Kept numeric so sorting is trivial.
    var priority: Int
    var dueAt: Date?
    /// False when the user said "Friday" and meant the whole day, true when they
    /// said "Friday at 4". Controls whether we render or announce a time.
    var hasTime: Bool
    /// RRULE-lite, e.g. `FREQ=WEEKLY;BYDAY=MO,WE,FR`. Nil for one-offs.
    var recurrence: String?
    var tags: [String]
    var estimateMinutes: Int?
    var energy: TaskEnergy?
    var parentId: UUID?
    var sortIndex: Double
    var completedAt: Date?
    var source: TaskSource
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID? = nil,
        title: String,
        notes: String? = nil,
        status: TaskStatus = .open,
        priority: Int = 0,
        dueAt: Date? = nil,
        hasTime: Bool = false,
        recurrence: String? = nil,
        tags: [String] = [],
        estimateMinutes: Int? = nil,
        energy: TaskEnergy? = nil,
        parentId: UUID? = nil,
        sortIndex: Double = 0,
        completedAt: Date? = nil,
        source: TaskSource = .manual,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.notes = notes
        self.status = status
        self.priority = priority
        self.dueAt = dueAt
        self.hasTime = hasTime
        self.recurrence = recurrence
        self.tags = tags
        self.estimateMinutes = estimateMinutes
        self.energy = energy
        self.parentId = parentId
        self.sortIndex = sortIndex
        self.completedAt = completedAt
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Encoding

extension TaskItem {
    enum CodingKeys: String, CodingKey {
        case id, userId, title, notes, status, priority, dueAt, hasTime, recurrence
        case tags, estimateMinutes, energy, parentId, sortIndex, completedAt
        case source, createdAt, updatedAt
    }

    /// Written by hand for one reason: **every key must always be present.**
    ///
    /// Swift's synthesised `Codable` uses `encodeIfPresent` for optionals, so a
    /// nil field is omitted from the JSON rather than sent as null. PostgREST
    /// requires every object in a bulk insert to carry an identical key set, so
    /// a batch mixing one task that repeats with one that doesn't is rejected
    /// outright — "All object keys must match" — and the whole write is lost.
    /// Emitting explicit nulls keeps the shape uniform no matter what's set.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(status, forKey: .status)
        try container.encode(priority, forKey: .priority)
        try container.encode(hasTime, forKey: .hasTime)
        try container.encode(tags, forKey: .tags)
        try container.encode(sortIndex, forKey: .sortIndex)
        try container.encode(source, forKey: .source)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)

        // Optionals: encoded unconditionally so nil becomes an explicit null.
        try encodeOptional(userId, forKey: .userId, in: &container)
        try encodeOptional(notes, forKey: .notes, in: &container)
        try encodeOptional(dueAt, forKey: .dueAt, in: &container)
        try encodeOptional(recurrence, forKey: .recurrence, in: &container)
        try encodeOptional(estimateMinutes, forKey: .estimateMinutes, in: &container)
        try encodeOptional(energy, forKey: .energy, in: &container)
        try encodeOptional(parentId, forKey: .parentId, in: &container)
        try encodeOptional(completedAt, forKey: .completedAt, in: &container)
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

// MARK: - Derived state

extension TaskItem {
    var isDone: Bool { status == .done }

    var isOverdue: Bool {
        guard status == .open, let dueAt else { return false }
        // An all-day task isn't late until the day is actually over.
        if hasTime { return dueAt < Date() }
        return Calendar.current.startOfDay(for: dueAt) < Calendar.current.startOfDay(for: Date())
    }

    var isDueToday: Bool {
        guard let dueAt else { return false }
        return Calendar.current.isDateInToday(dueAt)
    }

    var isRecurring: Bool { recurrence?.isEmpty == false }

    /// Short human due string for the row stamp: "TODAY", "TUE", "12 AUG", "2 DAYS LATE".
    var dueStamp: String? {
        guard let dueAt else { return nil }
        let cal = Calendar.current
        let now = Date()

        if isOverdue {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: dueAt), to: cal.startOfDay(for: now)).day ?? 0
            if days <= 0 { return "late" }
            return days == 1 ? "1 day late" : "\(days) days late"
        }

        let formatter = DateFormatter()
        if cal.isDateInToday(dueAt) {
            if hasTime {
                formatter.dateFormat = "h:mm a"
                return formatter.string(from: dueAt)
            }
            return "today"
        }
        if cal.isDateInTomorrow(dueAt) { return "tomorrow" }

        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: dueAt)).day ?? 0
        if days < 7 {
            formatter.dateFormat = "EEE"
            return formatter.string(from: dueAt)
        }
        formatter.dateFormat = "d MMM"
        return formatter.string(from: dueAt)
    }

    var priorityStamp: String? {
        switch priority {
        case 3: return "!!!"
        case 2: return "!!"
        case 1: return "!"
        default: return nil
        }
    }

    /// Stable seed so this task's hand-drawn imperfections never change.
    var seed: UInt64 { id.uuidString.inkSeed }
}

// MARK: - Sorting

extension Array where Element == TaskItem {
    /// Late first, then today, then by priority, then by the user's manual order.
    func inWorkingOrder() -> [TaskItem] {
        sorted { a, b in
            if a.isOverdue != b.isOverdue { return a.isOverdue }
            let aDue = a.dueAt ?? .distantFuture
            let bDue = b.dueAt ?? .distantFuture
            if Calendar.current.isDate(aDue, inSameDayAs: bDue) == false {
                if aDue != bDue { return aDue < bDue }
            }
            if a.priority != b.priority { return a.priority > b.priority }
            return a.sortIndex < b.sortIndex
        }
    }
}
