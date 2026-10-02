import Foundation
import Testing
@testable import Bubo

@Suite(.timeLimit(.minutes(1)))
struct OpenAICompatibleClientTests {
    let client = OpenAICompatibleClient(session: FakeChatServer.session)

    /// A cloud endpoint served by the fake server with `reply`, with a model written.
    static func cloud(_ reply: FakeChatServer.Reply, kind: OpenAICompatibleEndpoint.Kind = .custom)
        -> OpenAICompatibleEndpoint {
        var endpoint = OpenAICompatibleEndpoint.custom(named: "Prova", at: FakeChatServer.serve(reply))
        endpoint = OpenAICompatibleEndpoint(id: endpoint.id, kind: kind, name: endpoint.name, baseURL: endpoint.baseURL,
                                            model: "modello-prova")
        return endpoint
    }

    static func collect(_ stream: AsyncThrowingStream<OpenAICompatibleClient.Event, any Error>) async throws
        -> [OpenAICompatibleClient.Event] {
        var events: [OpenAICompatibleClient.Event] = []
        for try await event in stream { events.append(event) }
        return events
    }

    @Test func theAnswerStreamsWithItsTokens() async throws {
        let endpoint = Self.cloud(.init(body: FakeChatServer.stream(["Ciao", ", ", "mondo"])))

        let events = try await Self.collect(client.answer("Saluta", from: endpoint, consents: [endpoint.id], key: "k"))

        #expect(events == [.text("Ciao"), .text(", "), .text("mondo"), .usage(.init(input: 7, output: 3))])
    }

    // Acceptance of #92: the body carries the Domanda's text and nothing else.
    @Test func theBodyCarriesOnlyTheDomandasText() async throws {
        let endpoint = Self.cloud(.init(body: FakeChatServer.stream(["ok"])))

        _ = try await Self.collect(client.answer("Quanto fa 2+2?", from: endpoint, consents: [endpoint.id], key: "k"))

        let request = try #require(FakeChatServer.requests(at: endpoint.baseURL).first)
        #expect(request.url == endpoint.chatCompletionsURL)
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(Set(body.keys) == ["model", "messages", "stream", "stream_options"])
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [["role": "user", "content": "Quanto fa 2+2?"]])
        #expect(request.headers["Authorization"] == "Bearer k")
    }

    // Acceptance of #92: 0 bytes to a cloud that is not Claude without consent.
    @Test func aCloudWithoutConsentReceivesNothing() async {
        let endpoint = Self.cloud(.init(body: FakeChatServer.stream(["no"])))

        await #expect(throws: OpenAICompatibleError.consentMissing) {
            try await Self.collect(client.answer("Segreto", from: endpoint, consents: [], key: "k"))
        }
        #expect(FakeChatServer.requests(at: endpoint.baseURL).isEmpty)
    }

    // Acceptance of #92: Gemini without billing gets a warning and nothing.
    @Test func geminiWithoutBillingReceivesNothing() async {
        let endpoint = Self.cloud(.init(body: FakeChatServer.stream(["no"])), kind: .gemini)

        await #expect(throws: OpenAICompatibleError.billingUnconfirmed) {
            try await Self.collect(client.answer("Ciao", from: endpoint, consents: [endpoint.id], key: "k"))
        }
        #expect(FakeChatServer.requests(at: endpoint.baseURL).isEmpty)
    }

    @Test func geminiWithBillingIsAsked() async throws {
        var endpoint = Self.cloud(.init(body: FakeChatServer.stream(["sì"])), kind: .gemini)
        endpoint.confirmsBilling = true

        let events = try await Self.collect(client.answer("Ciao", from: endpoint, consents: [endpoint.id], key: "k"))

        #expect(events.first == .text("sì"))
    }

    @Test func aServerOnTheMacNeedsNoConsentNorKey() async throws {
        var endpoint = try #require(OpenAICompatibleEndpoint.known.first { $0.kind == .ollama })
        endpoint.baseURL = FakeChatServer.serve(.init(body: FakeChatServer.stream(["locale"])), onMac: true)
        endpoint.model = "qwen"

        let events = try await Self.collect(client.answer("Ciao", from: endpoint, consents: [], key: nil))

        #expect(events.first == .text("locale"))
        #expect(FakeChatServer.requests(at: endpoint.baseURL).first?.headers["Authorization"] == nil)
    }

    @Test func aKnownCloudWithoutKeyReceivesNothing() async {
        let endpoint = Self.cloud(.init(body: ""), kind: .openAI)

        await #expect(throws: OpenAICompatibleError.keyMissing) {
            try await Self.collect(client.answer("Ciao", from: endpoint, consents: [endpoint.id], key: nil))
        }
        #expect(FakeChatServer.requests(at: endpoint.baseURL).isEmpty)
    }

    @Test(arguments: [
        (401, "{}", OpenAICompatibleError.keyRefused),
        (429, #"{"error":{"message":"Troppe richieste"}}"#, .failed("Troppe richieste")),
        // #164: OpenRouter's own limit is said as such, not as a Budget of Bubo.
        (402, #"{"error":{"code":402,"message":"Key limit exceeded","metadata":{"limit_source":"openrouter_key_limit"}}}"#,
         .providerLimit(.keyLimit)),
        (402, #"{"error":{"code":402,"metadata":{"limit_source":"openrouter_in_flight_budget"}}}"#,
         .providerLimit(.inFlightBudget)),
        (402, #"{"error":{"message":"Insufficient credits"}}"#, .failed("Insufficient credits")),
    ])
    func anErrorOfTheServerIsSaid(status: Int, body: String, expected: OpenAICompatibleError) async {
        let endpoint = Self.cloud(.init(status: status, body: body))

        await #expect(throws: expected) {
            try await Self.collect(client.answer("Ciao", from: endpoint, consents: [endpoint.id], key: "k"))
        }
    }

    @Test func linesOtherThanDataAreSkipped() throws {
        #expect(try OpenAICompatibleClient.events(in: ": keep-alive") == [])
        #expect(try OpenAICompatibleClient.events(in: "") == [])
        #expect(try OpenAICompatibleClient.events(in: "data: [DONE]") == nil)
    }
}
