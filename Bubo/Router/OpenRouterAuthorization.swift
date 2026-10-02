import CryptoKit
import Foundation

/// Connecting OpenRouter with OAuth PKCE (spec 10, Fornitori delle Domande): the user authorizes Bubo in the browser,
/// and OpenRouter hands back a key of theirs, without anything to paste.
///
/// The key pays with the user's OpenRouter credits. "Never use shared capacity" is an option of each BYOK key in
/// OpenRouter's dashboard, not of the request, so Bubo cannot set it (preflight of #95).
nonisolated struct OpenRouterAuthorization: Sendable {
    /// Why no key came back.
    enum Failure: Error, Equatable {
        /// OpenRouter refused the code: expired after 10 minutes, already used, or the verifier did not match.
        case refused(status: Int)
        /// OpenRouter answered without a key.
        case noKey
    }

    /// The secret the code is exchanged with: it never leaves the Mac before the exchange.
    let verifier: String
    /// Where the authorization and the exchange go; tests pass a stand-in.
    let site: URL

    /// Creates an authorization with a fresh random verifier.
    init(site: URL = URL(string: "https://openrouter.ai")!) {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        self.init(verifier: Self.base64URL(Data(bytes)), site: site)
    }

    init(verifier: String, site: URL) {
        self.verifier = verifier
        self.site = site
    }

    /// The S256 challenge: the verifier's SHA-256, in base64url without padding.
    var challenge: String {
        Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// The page where the user authorizes Bubo, which then sends the browser to `callback` with a `code`.
    func authorizationURL(callback: URL) -> URL {
        site.appending(path: "auth").appending(queryItems: [
            URLQueryItem(name: "callback_url", value: callback.absoluteString),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // So the user recognizes the key in OpenRouter's dashboard.
            URLQueryItem(name: "key_label", value: "Bubo"),
        ])
    }

    /// Exchanges `code` for the user's key.
    func key(for code: String, session: URLSession = .shared) async throws -> String {
        var request = URLRequest(url: site.appending(path: "api/v1/auth/keys"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "code": code, "code_verifier": verifier, "code_challenge_method": "S256",
        ])
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.refused(status: status) }
        struct Reply: Decodable { let key: String? }
        guard let key = try? JSONDecoder().decode(Reply.self, from: data).key, !key.isEmpty else { throw Failure.noKey }
        return key
    }

    /// Runs the whole connection: a callback on a free port of this Mac, the page opened with `open`, then the
    /// exchange; the key goes only to `save`.
    ///
    /// Cancelling the task closes the callback.
    static func connect(site: URL = URL(string: "https://openrouter.ai")!, session: URLSession = .shared,
                        open: @MainActor (URL) -> Void, save: (String) async throws -> Void) async throws {
        let authorization = Self(site: site)
        let callback = try await OAuthCallbackServer.start()
        defer { callback.stop() }
        await open(authorization.authorizationURL(callback: callback.url))
        let code = try await callback.code()
        try await save(try await authorization.key(for: code, session: session))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacing("+", with: "-").replacing("/", with: "_").replacing("=", with: "")
    }
}
