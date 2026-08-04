import AuthenticationServices
import CryptoKit
import SwiftUI

/// Sign in with Apple, wired straight to Supabase's `id_token` grant.
///
/// Apple embeds the SHA-256 of the nonce in the identity token; Supabase needs
/// the raw one to verify the pair, which is why both forms are kept here.
struct AppleSignInButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    @State private var rawNonce = ""

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = Self.randomNonce()
            rawNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard
                    let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                    let tokenData = credential.identityToken,
                    let idToken = String(data: tokenData, encoding: .utf8)
                else {
                    model.show(message: "Apple didn't return a usable token.")
                    return
                }
                // Apple only sends the name on the very first authorisation.
                let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")

                Task {
                    await model.signInWithApple(idToken: idToken, nonce: rawNonce, fullName: name.isEmpty ? nil : name)
                }

            case .failure(let error):
                // Cancelling isn't an error worth shouting about.
                if (error as? ASAuthorizationError)?.code == .canceled { return }
                model.show(error)
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
    }

    // MARK: - Nonce

    static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        guard status == errSecSuccess else {
            // Never silently fall back to something predictable.
            return UUID().uuidString + UUID().uuidString
        }
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
