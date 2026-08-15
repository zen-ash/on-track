import Foundation

/// PostgREST-backed store. Row level security scopes every query to the signed-in
/// user, so there's no user_id filter here on purpose — the database enforces it.
struct SupabaseTaskStore: TaskStore {
    let auth: SupabaseAuth
    private let table = "tasks"

    func loadAll() async throws -> [TaskItem] {
        let data = try await request(
            method: "GET",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "deleted_at", value: "is.null"),
                URLQueryItem(name: "order", value: "sort_index.asc")
            ],
            body: nil
        )
        do {
            return try JSONCoding.decoder.decode([TaskItem].self, from: data)
        } catch {
            throw StoreError.decoding(String(describing: error))
        }
    }

    func loadTrash() async throws -> [TaskItem] {
        let data = try await request(
            method: "GET",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "deleted_at", value: "not.is.null"),
                URLQueryItem(name: "order", value: "deleted_at.desc")
            ],
            body: nil
        )
        do {
            return try JSONCoding.decoder.decode([TaskItem].self, from: data)
        } catch {
            throw StoreError.decoding(String(describing: error))
        }
    }

    func upsert(_ tasks: [TaskItem]) async throws {
        guard !tasks.isEmpty else { return }
        let userId = await auth.currentUserId()
        let stamped = tasks.map { task -> TaskItem in
            var copy = task
            // RLS checks user_id on insert; fill it in rather than trusting the caller.
            copy.userId = task.userId ?? userId
            return copy
        }
        let body = try JSONCoding.encoder.encode(stamped)
        _ = try await request(
            method: "POST",
            query: [],
            body: body,
            extraHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"]
        )
    }

    func delete(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        let list = ids.map(\.uuidString).joined(separator: ",")
        _ = try await request(
            method: "DELETE",
            query: [URLQueryItem(name: "id", value: "in.(\(list))")],
            body: nil,
            extraHeaders: ["Prefer": "return=minimal"]
        )
    }

    // MARK: - Transport

    @discardableResult
    private func request(
        method: String,
        query: [URLQueryItem],
        body: Data?,
        extraHeaders: [String: String] = [:]
    ) async throws -> Data {
        guard let base = AppConfig.restBaseURL else { throw StoreError.backendNotConfigured }
        let token = try await auth.validAccessToken()

        var components = URLComponents(url: base.appendingPathComponent(table), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (key, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StoreError.server(status: -1, message: "No response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw StoreError.server(status: http.statusCode, message: SupabaseAuth.errorMessage(from: data))
        }
        return data
    }
}
