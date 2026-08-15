import Foundation

/// Everything the UI needs from persistence, so the local and Supabase paths are
/// interchangeable and the views never know which one is live.
protocol TaskStore: Sendable {
    /// Live tasks only — anything soft-deleted (`deletedAt != nil`) is excluded.
    func loadAll() async throws -> [TaskItem]
    /// The mirror image of `loadAll()`: only soft-deleted tasks, for Trash.
    func loadTrash() async throws -> [TaskItem]
    func upsert(_ tasks: [TaskItem]) async throws
    /// A real, permanent delete — used for the 30-day sweep and "Delete
    /// Forever", never for an ordinary delete (that's an upsert with
    /// `deletedAt` set, so it lands in Trash instead of vanishing outright).
    func delete(ids: [UUID]) async throws
}

extension TaskStore {
    func upsert(_ task: TaskItem) async throws {
        try await upsert([task])
    }
}

enum StoreError: LocalizedError {
    case notSignedIn
    case backendNotConfigured
    case server(status: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You're not signed in."
        case .backendNotConfigured:
            return "No backend configured. Add your Supabase URL and anon key in AppConfig.swift."
        case .server(let status, let message):
            return "Server error \(status): \(message)"
        case .decoding(let detail):
            return "Couldn't read the server response: \(detail)"
        }
    }
}
