import Foundation

/// Account lifecycle operations that need server-side privileges.
///
/// Deliberately tiny and separate from `SupabaseTaskStore`: deletion is
/// irreversible, and it should be obvious from the call site that it is not an
/// ordinary write.
struct AccountService: Sendable {
    let auth: SupabaseAuth

    /// Permanently deletes the signed-in user and everything they own.
    ///
    /// The account is identified server-side from the caller's JWT, so there is
    /// nothing here that could be pointed at somebody else's account.
    func deleteAccount() async throws {
        guard let base = AppConfig.functionsBaseURL else { throw StoreError.backendNotConfigured }
        let token = try await auth.validAccessToken()

        var request = URLRequest(url: base.appendingPathComponent("account"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["action": "delete"])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StoreError.server(status: -1, message: "No response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw StoreError.server(status: http.statusCode, message: SupabaseAuth.errorMessage(from: data))
        }
    }
}
