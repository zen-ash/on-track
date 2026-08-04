import Foundation

/// Everything the UI needs from persistence, so the local and Supabase paths are
/// interchangeable and the views never know which one is live.
protocol TaskStore: Sendable {
    func loadAll() async throws -> [TaskItem]
    func upsert(_ tasks: [TaskItem]) async throws
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
