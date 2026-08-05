import Foundation

struct Session: Sendable, Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userId: UUID
    var isAnonymous: Bool

    /// Refresh a minute early so a request never races the expiry.
    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}

/// Talks to Supabase GoTrue directly over REST. Hand-rolled instead of pulling
/// in the SDK so the project has zero package dependencies and builds from a
/// clean checkout with nothing but Xcode.
actor SupabaseAuth {
    private static let keychainAccount = "supabase.session"
    private var cached: Session?

    // MARK: - Sign in

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws -> Session {
        var body: [String: Any] = [
            "provider": "apple",
            "id_token": idToken,
            "nonce": nonce
        ]
        if let fullName, !fullName.isEmpty {
            body["gotrue_meta_security"] = ["full_name": fullName]
        }
        let session = try await post(path: "token", query: [URLQueryItem(name: "grant_type", value: "id_token")], body: body)
        persist(session)
        return session
    }

    /// Requires "Allow anonymous sign-ins" to be enabled in the Supabase
    /// dashboard. Gives a real, RLS-scoped user without Apple's paid program.
    func signInAnonymously() async throws -> Session {
        let session = try await post(path: "signup", query: [], body: [:], anonymous: true)
        persist(session)
        return session
    }

    func signOut() async {
        if let token = cached?.accessToken {
            _ = try? await rawRequest(path: "logout", query: [], body: [:], accessToken: token)
        }
        cached = nil
        Keychain.remove(Self.keychainAccount)
    }

    // MARK: - Session handling

    func restoreSession() async -> Session? {
        if let cached, !cached.isExpired { return cached }

        if cached == nil,
           let data = Keychain.get(Self.keychainAccount),
           let stored = try? JSONDecoder().decode(Session.self, from: data) {
            cached = stored
        }

        guard let current = cached else { return nil }
        if current.isExpired {
            do {
                return try await refresh(using: current.refreshToken)
            } catch {
                // Only a definitive rejection from the server means the session
                // is really gone. A network failure must never discard it: for
                // an anonymous account the refresh token *is* the account, so
                // dropping it after one offline launch would orphan every task
                // on the server with no way back in.
                if let storeError = error as? StoreError,
                   case .server(let status, _) = storeError,
                   status == 400 || status == 401 {
                    Keychain.remove(Self.keychainAccount)
                    cached = nil
                }
                return nil
            }
        }
        return current
    }

    /// The single accessor every authenticated request goes through.
    func validAccessToken() async throws -> String {
        guard let session = await restoreSession() else { throw StoreError.notSignedIn }
        return session.accessToken
    }

    func currentUserId() async -> UUID? {
        let session = await restoreSession()
        return session?.userId
    }

    private func refresh(using refreshToken: String) async throws -> Session {
        let session = try await post(
            path: "token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: ["refresh_token": refreshToken]
        )
        persist(session)
        return session
    }

    private func persist(_ session: Session) {
        cached = session
        if let data = try? JSONEncoder().encode(session) {
            Keychain.set(data, for: Self.keychainAccount)
        }
    }

    // MARK: - Transport

    private func post(path: String, query: [URLQueryItem], body: [String: Any], anonymous: Bool = false) async throws -> Session {
        let data = try await rawRequest(path: path, query: query, body: body, accessToken: nil, anonymous: anonymous)
        return try Self.decodeSession(from: data)
    }

    @discardableResult
    private func rawRequest(
        path: String,
        query: [URLQueryItem],
        body: [String: Any],
        accessToken: String?,
        anonymous: Bool = false
    ) async throws -> Data {
        guard let base = AppConfig.authBaseURL else { throw StoreError.backendNotConfigured }
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        // Short, so an offline launch fails fast instead of stalling a refresh.
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StoreError.server(status: -1, message: "No response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw StoreError.server(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        return data
    }

    private static func decodeSession(from data: Data) throws -> Session {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String else {
            throw StoreError.decoding("missing tokens in auth response")
        }
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        let user = json["user"] as? [String: Any]
        let userIdString = (user?["id"] as? String) ?? ""
        guard let userId = UUID(uuidString: userIdString) else {
            throw StoreError.decoding("missing user id in auth response")
        }
        let isAnonymous = (user?["is_anonymous"] as? Bool) ?? false

        return Session(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn),
            userId: userId,
            isAnonymous: isAnonymous
        )
    }

    static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? "unknown"
        }
        return (json["error_description"] as? String)
            ?? (json["msg"] as? String)
            ?? (json["message"] as? String)
            ?? (json["error"] as? String)
            ?? "unknown"
    }
}
