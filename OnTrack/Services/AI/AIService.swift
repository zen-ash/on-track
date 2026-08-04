import Foundation

// MARK: - Wire types
// These mirror the JSON schemas the Edge Function enforces on the model, so a
// well-formed response decodes here without any defensive munging.

/// One task the model extracted from what you said or typed.
struct CapturedTask: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var notes: String?
    var dueAt: Date?
    var hasTime: Bool = false
    var priority: Int = 0
    var tags: [String] = []
    var recurrence: String?
    var estimateMinutes: Int?
    var energy: TaskEnergy?
    var subtasks: [String] = []

    private enum CodingKeys: String, CodingKey {
        case title, notes, dueAt, hasTime, priority, tags, recurrence, estimateMinutes, energy, subtasks
    }

    init(
        title: String,
        notes: String? = nil,
        dueAt: Date? = nil,
        hasTime: Bool = false,
        priority: Int = 0,
        tags: [String] = [],
        recurrence: String? = nil,
        estimateMinutes: Int? = nil,
        energy: TaskEnergy? = nil,
        subtasks: [String] = []
    ) {
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.hasTime = hasTime
        self.priority = priority
        self.tags = tags
        self.recurrence = recurrence
        self.estimateMinutes = estimateMinutes
        self.energy = energy
        self.subtasks = subtasks
    }

    /// Converts to a real task, expanding subtasks into children of the parent.
    func materialise(userId: UUID?, source: TaskSource, sortIndex: Double) -> [TaskItem] {
        let parent = TaskItem(
            userId: userId,
            title: title,
            notes: notes,
            priority: priority,
            dueAt: dueAt,
            hasTime: hasTime,
            recurrence: recurrence,
            tags: tags,
            estimateMinutes: estimateMinutes,
            energy: energy,
            sortIndex: sortIndex,
            source: source
        )
        let children = subtasks.enumerated().map { index, childTitle in
            TaskItem(
                userId: userId,
                title: childTitle,
                parentId: parent.id,
                sortIndex: sortIndex + Double(index + 1) / 1000,
                source: .ai
            )
        }
        return [parent] + children
    }
}

struct CaptureResult: Codable, Sendable {
    var tasks: [CapturedTask]
    /// One short line the creature says back. Nil when there's nothing to add.
    var reply: String?
}

/// A slot in the day rather than a hard clock time — the plan should survive
/// contact with reality.
enum PlanSlot: String, Codable, Sendable, CaseIterable {
    case now, morning, afternoon, evening

    var label: String {
        switch self {
        case .now: return "Right now"
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        }
    }
}

struct PlanItem: Codable, Sendable, Identifiable {
    var taskId: UUID
    var slot: PlanSlot
    /// Why this, why now. Shown under the task in the plan review.
    var reason: String
    var order: Int

    var id: UUID { taskId }
}

struct DayPlan: Codable, Sendable {
    /// The one thing that matters today, in the model's words.
    var focus: String
    var items: [PlanItem]
    /// Tasks it thinks you should drop or defer, with no ceremony.
    var deferIds: [UUID]
    var note: String?
}

struct ChatReply: Codable, Sendable {
    var message: String
    /// True when the model changed the database, so the client knows to refetch.
    var didMutate: Bool
}

struct ChatTurn: Codable, Sendable, Identifiable, Hashable {
    enum Role: String, Codable, Sendable { case user, assistant }
    var id: UUID = UUID()
    var role: Role
    var text: String
    var at: Date = Date()

    private enum CodingKeys: String, CodingKey { case role, text }
}

// MARK: - Service

protocol AIService: Sendable {
    /// Turns raw speech or typing into structured tasks.
    func capture(text: String, existingTitles: [String]) async throws -> CaptureResult
    /// Proposes today's plan across the open list.
    func plan(tasks: [TaskItem]) async throws -> DayPlan
    /// Conversational edit surface. The server runs the tool loop against the DB.
    func chat(history: [ChatTurn], tasks: [TaskItem]) async throws -> ChatReply
    /// Expands one vague task into concrete next actions.
    func breakdown(task: TaskItem) async throws -> [String]

    /// False for the on-device fallback, so the UI can be honest about what's off.
    var isFullyCapable: Bool { get }
}

enum AIError: LocalizedError {
    case notConfigured
    case notSignedIn
    case transport(String)
    case server(status: Int, message: String)
    case badResponse(String)
    case unsupportedLocally(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI isn't connected yet. Add your Supabase details in AppConfig.swift and deploy the ai function."
        case .notSignedIn:
            return "Sign in to use this."
        case .transport(let detail):
            return "Network problem: \(detail)"
        case .server(let status, let message):
            return status == 401 ? "Your session expired. Sign in again." : "AI error \(status): \(message)"
        case .badResponse(let detail):
            return "The model returned something unexpected: \(detail)"
        case .unsupportedLocally(let feature):
            return "\(feature) needs the backend. Right now you're running on-device only."
        }
    }
}
