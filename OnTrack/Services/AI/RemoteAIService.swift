import Foundation

/// Calls the `ai` Edge Function. The OpenAI key lives on the server and never
/// touches the device — the function verifies the caller's JWT and does all the
/// model work and database mutation itself.
struct RemoteAIService: AIService {
    let auth: SupabaseAuth
    var isFullyCapable: Bool { true }

    // MARK: - Requests

    private struct CaptureRequest: Encodable {
        let text: String
        let existingTitles: [String]
        let now: String
        let timezone: String
    }

    private struct PlanRequest: Encodable {
        let tasks: [TaskItem]
        let now: String
        let timezone: String
    }

    private struct ChatRequest: Encodable {
        let history: [ChatTurn]
        let now: String
        let timezone: String
    }

    private struct BreakdownRequest: Encodable {
        let title: String
        let notes: String?
        let now: String
    }

    private struct BreakdownResponse: Decodable {
        let steps: [String]
    }

    // MARK: - AIService

    func capture(text: String, existingTitles: [String]) async throws -> CaptureResult {
        try await call(
            action: "capture",
            body: CaptureRequest(
                text: text,
                // Sent so the model can spot duplicates rather than cheerfully
                // adding "call the bank" for the fourth time.
                existingTitles: Array(existingTitles.prefix(60)),
                now: DateParsing.iso8601String(Date()),
                timezone: TimeZone.current.identifier
            )
        )
    }

    func plan(tasks: [TaskItem]) async throws -> DayPlan {
        let relevant = tasks.filter { $0.status == .open }
        return try await call(
            action: "plan",
            body: PlanRequest(
                tasks: Array(relevant.prefix(120)),
                now: DateParsing.iso8601String(Date()),
                timezone: TimeZone.current.identifier
            )
        )
    }

    func chat(history: [ChatTurn], tasks: [TaskItem]) async throws -> ChatReply {
        // Tasks aren't sent: the function reads them from Postgres under the
        // caller's own RLS context, which keeps the prompt small and the data fresh.
        try await call(
            action: "chat",
            body: ChatRequest(
                history: Array(history.suffix(20)),
                now: DateParsing.iso8601String(Date()),
                timezone: TimeZone.current.identifier
            )
        )
    }

    func breakdown(task: TaskItem) async throws -> [String] {
        let response: BreakdownResponse = try await call(
            action: "breakdown",
            body: BreakdownRequest(
                title: task.title,
                notes: task.notes,
                now: DateParsing.iso8601String(Date())
            )
        )
        return response.steps
    }

    // MARK: - Transport

    private func call<Body: Encodable, Response: Decodable>(action: String, body: Body) async throws -> Response {
        guard let base = AppConfig.functionsBaseURL else { throw AIError.notConfigured }

        let token: String
        do {
            token = try await auth.validAccessToken()
        } catch {
            throw AIError.notSignedIn
        }

        var request = URLRequest(url: base.appendingPathComponent("ai"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var payload = try JSONCoding.encoder.encode(body)
        // Splice the action in alongside the body so the function has one entry point.
        if var json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] {
            json["action"] = action
            payload = try JSONSerialization.data(withJSONObject: json)
        }
        request.httpBody = payload

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIError.badResponse("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = SupabaseAuth.errorMessage(from: data)
            if http.statusCode == 429 {
                throw AIError.rateLimited(message)
            }
            throw AIError.server(status: http.statusCode, message: message)
        }

        do {
            return try JSONCoding.decoder.decode(Response.self, from: data)
        } catch {
            throw AIError.badResponse(String(describing: error))
        }
    }
}
