import Foundation

/// Single place to point the app at your backend.
///
/// Until you fill these in, the app runs in **local mode**: tasks are stored on
/// device, and capture falls back to on-device date parsing instead of the
/// model. Everything is still usable — you just don't get planning, chat, or
/// sync. See SETUP.md.
enum AppConfig {
    /// e.g. "https://abcdefghijkl.supabase.co"
    static let supabaseURL = "https://zflusebzzwjkonxlvmke.supabase.co"

    /// The Supabase **anon/publishable** key. This one is safe to ship — row
    /// level security is what actually protects the data. Never put the
    /// service-role key or your OpenAI key here; those live on the server.
    static let supabaseAnonKey = "sb_publishable_9vmVr2UdoQxvRI7KOaLzEQ_cuni829U"

    static var isBackendConfigured: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty && URL(string: supabaseURL) != nil
    }

    static var functionsBaseURL: URL? {
        guard isBackendConfigured, let base = URL(string: supabaseURL) else { return nil }
        return base.appendingPathComponent("functions/v1")
    }

    static var restBaseURL: URL? {
        guard isBackendConfigured, let base = URL(string: supabaseURL) else { return nil }
        return base.appendingPathComponent("rest/v1")
    }

    static var authBaseURL: URL? {
        guard isBackendConfigured, let base = URL(string: supabaseURL) else { return nil }
        return base.appendingPathComponent("auth/v1")
    }

    /// Deep link that every quick-capture trigger funnels through.
    static let captureURL = URL(string: "ontrack://capture")!
    static let appScheme = "ontrack"
}
