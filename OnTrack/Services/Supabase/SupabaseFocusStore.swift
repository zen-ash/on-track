import Foundation

/// PostgREST-backed store for Focus, same shape as `SupabaseTaskStore` — no
/// user_id filter on any query on purpose, RLS is what actually scopes it.
struct SupabaseFocusStore: FocusStore {
    let auth: SupabaseAuth
    private let tracksTable = "focus_tracks"
    private let sessionsTable = "focus_sessions"

    func loadTracks() async throws -> [FocusTrack] {
        let data = try await request(
            table: tracksTable,
            method: "GET",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "sort_index.asc")
            ],
            body: nil
        )
        do {
            return try JSONCoding.decoder.decode([FocusTrack].self, from: data)
        } catch {
            throw StoreError.decoding(String(describing: error))
        }
    }

    func upsertTracks(_ tracks: [FocusTrack]) async throws {
        guard !tracks.isEmpty else { return }
        let userId = await auth.currentUserId()
        let stamped = tracks.map { track -> FocusTrack in
            var copy = track
            copy.userId = track.userId ?? userId
            return copy
        }
        let body = try JSONCoding.encoder.encode(stamped)
        _ = try await request(
            table: tracksTable,
            method: "POST",
            query: [],
            body: body,
            extraHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"]
        )
    }

    func loadSessions(since: Date) async throws -> [FocusSession] {
        let data = try await request(
            table: sessionsTable,
            method: "GET",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "started_at", value: "gte.\(DateParsing.iso8601String(since))"),
                URLQueryItem(name: "order", value: "started_at.desc")
            ],
            body: nil
        )
        do {
            return try JSONCoding.decoder.decode([FocusSession].self, from: data)
        } catch {
            throw StoreError.decoding(String(describing: error))
        }
    }

    func upsertSessions(_ sessions: [FocusSession]) async throws {
        guard !sessions.isEmpty else { return }
        let userId = await auth.currentUserId()
        let stamped = sessions.map { session -> FocusSession in
            var copy = session
            copy.userId = session.userId ?? userId
            return copy
        }
        let body = try JSONCoding.encoder.encode(stamped)
        _ = try await request(
            table: sessionsTable,
            method: "POST",
            query: [],
            body: body,
            extraHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"]
        )
    }

    // MARK: - Transport

    @discardableResult
    private func request(
        table: String,
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
