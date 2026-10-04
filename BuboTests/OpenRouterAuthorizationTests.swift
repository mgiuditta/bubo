import Foundation
import Testing
@testable import Bubo

/// Connecting OpenRouter (#95): PKCE, the callback on this Mac and the exchange, against stand-ins only.
struct OpenRouterAuthorizationTests {
    /// The expected challenge was computed apart, with Python's `hashlib` and `base64.urlsafe_b64encode`.
    @Test func challengeIsTheS256OfTheVerifier() {
        let authorization = OpenRouterAuthorization(verifier: "dBjftJeZ4CVP-mA3uicV1HIqHXmUYRdhQ4GbZtbM3NE",
                                                    site: URL(string: "https://openrouter.ai")!)
        #expect(authorization.challenge == "4MVOxUhVhxllkt0aopd7qSxYcKPpAn4B8mfd2lvTKi0")
    }

    @Test func aFreshVerifierIsLongURLSafeAndNew() {
        let first = OpenRouterAuthorization().verifier
        #expect(first.count == 43)
        #expect(first.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(first != OpenRouterAuthorization().verifier)
    }

    @Test func authorizationURLAsksForAnS256KeyLabelledBubo() throws {
        let authorization = OpenRouterAuthorization()
        let callback = URL(string: "http://localhost:51423/callback")!
        let url = authorization.authorizationURL(callback: callback)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(components.host == "openrouter.ai")
        #expect(components.path == "/auth")
        #expect(items["callback_url"] == callback.absoluteString)
        #expect(items["code_challenge"] == authorization.challenge)
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["key_label"] == "Bubo")
    }

    @Test(arguments: [
        ("GET /callback?code=abc123 HTTP/1.1\r\nHost: localhost\r\n\r\n", "abc123"),
        ("GET /callback?state=x&code=a%2Fb HTTP/1.1\r\n\r\n", "a/b"),
        ("GET /favicon.ico HTTP/1.1\r\n\r\n", nil),
        ("GET /callback HTTP/1.1\r\n\r\n", nil),
        ("GET /callback?code= HTTP/1.1\r\n\r\n", nil),
        ("POST /callback?code=abc HTTP/1.1\r\n\r\n", nil),
    ] as [(String, String?)])
    func callbackReadsOnlyTheCode(request: String, code: String?) {
        #expect(OAuthCallbackServer.code(inRequest: request) == code)
    }

    @Test func codeIsExchangedForTheKey() async throws {
        let site = FakeChatServer.serve(.init(body: #"{"key":"sk-or-v1-test"}"#))
        let authorization = OpenRouterAuthorization(verifier: "verifier", site: site)

        let key = try await authorization.key(for: "the-code", session: FakeChatServer.session)

        #expect(key == "sk-or-v1-test")
        let request = try #require(FakeChatServer.requests(at: site).first)
        #expect(request.url.path().hasSuffix("/api/v1/auth/keys"))
        let body = try JSONDecoder().decode([String: String].self, from: request.body)
        #expect(body == ["code": "the-code", "code_verifier": "verifier", "code_challenge_method": "S256"])
    }

    @Test func aRefusedCodeGivesNoKey() async {
        let site = FakeChatServer.serve(.init(status: 403, body: #"{"error":"invalid code"}"#))
        let authorization = OpenRouterAuthorization(verifier: "verifier", site: site)

        await #expect(throws: OpenRouterAuthorization.Failure.refused(status: 403)) {
            try await authorization.key(for: "old-code", session: FakeChatServer.session)
        }
    }

    @Test func aReplyWithoutAKeyGivesNoKey() async {
        let site = FakeChatServer.serve(.init(body: "{}"))
        let authorization = OpenRouterAuthorization(verifier: "verifier", site: site)

        await #expect(throws: OpenRouterAuthorization.Failure.noKey) {
            try await authorization.key(for: "code", session: FakeChatServer.session)
        }
    }

    @Test func callbackOnThisMacReceivesTheCode() async throws {
        let server = try await OAuthCallbackServer.start()
        defer { server.stop() }
        #expect(server.url.host() == "localhost")
        #expect(server.url.path() == "/callback")

        var request = URLComponents(url: server.url, resolvingAgainstBaseURL: false)!
        request.queryItems = [URLQueryItem(name: "code", value: "from-browser")]
        let (_, response) = try await URLSession(configuration: .ephemeral).data(from: request.url!)

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(try await server.code(timeout: .seconds(5)) == "from-browser")
    }

    @Test func callbackGivesUpAfterTheTimeout() async throws {
        let server = try await OAuthCallbackServer.start()
        defer { server.stop() }

        await #expect(throws: OAuthCallbackServer.Failure.timedOut) {
            try await server.code(timeout: .milliseconds(50))
        }
    }

    @Test func openRouterIsKnownAndNeedsAKey() throws {
        let endpoint = try #require(OpenAICompatibleEndpoint.known.first { $0.kind == .openRouter })
        #expect(endpoint.baseURL == URL(string: "https://openrouter.ai/api/v1"))
        #expect(endpoint.requiresKey)
        #expect(!endpoint.isOnMac)
    }
}
