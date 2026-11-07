import AuthenticationServices
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    /// The custom URL scheme the hosted callback page (docs/callback.html) sends you back to.
    static let callbackScheme = "quietpost"

    @Published var config: TikTokConfig?
    @Published private(set) var tokens: TikTokTokens?
    @Published private(set) var creator: CreatorInfo?

    private let webAuth = WebAuth()

    init() {
        config = Keychain.load(TikTokConfig.self, for: "config")
        tokens = Keychain.load(TikTokTokens.self, for: "tokens")
    }

    var isConnected: Bool { tokens != nil && config != nil }

    func saveConfig(_ newConfig: TikTokConfig) {
        config = newConfig
        Keychain.save(newConfig, for: "config")
    }

    func connect() async throws {
        guard let config else { throw QuietError.message("Add your TikTok app keys first.") }
        let state = UUID().uuidString
        let url = TikTokAPI.authorizeURL(config: config, state: state)
        let callback = try await webAuth.start(url: url, callbackScheme: Self.callbackScheme)

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") {
            throw QuietError.message(value("error_description") ?? error)
        }
        guard value("state") == state, let code = value("code") else {
            throw QuietError.message("Sign-in didn't complete. Try again.")
        }
        let newTokens = try await TikTokAPI.exchange(code: code, config: config)
        setTokens(newTokens)
    }

    func disconnect() async {
        if let tokens, let config { await TikTokAPI.revoke(tokens, config: config) }
        setTokens(nil)
        creator = nil
    }

    /// Returns a usable access token, refreshing it if it has expired.
    func accessToken() async throws -> String {
        guard let tokens, let config else { throw QuietError.notConnected }
        if tokens.expiresAt > Date().addingTimeInterval(120) { return tokens.accessToken }
        guard tokens.refreshExpiresAt > Date() else {
            setTokens(nil)
            throw QuietError.notConnected
        }
        do {
            let fresh = try await TikTokAPI.refresh(tokens, config: config)
            setTokens(fresh)
            return fresh.accessToken
        } catch {
            setTokens(nil)
            throw QuietError.notConnected
        }
    }

    func loadCreator() async throws {
        creator = try await TikTokAPI.creatorInfo(token: try await accessToken())
    }

    private func setTokens(_ newTokens: TikTokTokens?) {
        tokens = newTokens
        Keychain.save(newTokens, for: "tokens")
    }
}

/// Wraps ASWebAuthenticationSession in async/await.
final class WebAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    @MainActor
    func start(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: error ?? QuietError.message("Sign-in failed."))
                }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                continuation.resume(throwing: QuietError.message("Couldn't open TikTok sign-in."))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
