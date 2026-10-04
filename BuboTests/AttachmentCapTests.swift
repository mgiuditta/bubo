import Foundation
import Testing
@testable import Bubo

/// The Allegati towards providers other than Claude (#99): the cap of each destination, the confirmation of each
/// Allegato, and what leaves the Mac. Apple FM's cap is measured in `OnDeviceFitTests`.
@Suite(.timeLimit(.minutes(1)))
struct AttachmentCapTests {
    let reader = EndpointContextReader(session: FakeChatServer.session)

    /// An Allegato of text estimated at exactly `tokens`.
    static func allegato(tokens: Int, name: String = "nota.md") -> Allegato {
        Allegato(name: name, text: String(repeating: "a", count: tokens * AttachmentPolicy.charactersPerToken))
    }

    /// The endpoint of `kind` answering at `baseURL` with `model`.
    static func endpoint(_ kind: OpenAICompatibleEndpoint.Kind, at baseURL: URL, model: String = "modello")
        -> OpenAICompatibleEndpoint {
        var endpoint = OpenAICompatibleEndpoint.known.first { $0.kind == kind }
            ?? .custom(named: "Prova", at: baseURL)
        endpoint.baseURL = baseURL
        endpoint.model = model
        return endpoint
    }

    /// The verdict on an Allegato of `tokens` towards `endpoint`, its context read through the stand-in server, with
    /// the Allegato already confirmed.
    func verdict(tokens: Int, to endpoint: OpenAICompatibleEndpoint) async -> AttachmentPolicy.Verdict {
        let allegato = Self.allegato(tokens: tokens)
        return AttachmentPolicy.verdict(for: [allegato], to: endpoint,
                                        contextLength: await reader.contextLength(of: endpoint), confirmed: [allegato])
    }

    @Test func theEstimateCountsThreeCharactersAToken() {
        #expect(AttachmentPolicy.estimatedTokens(of: "") == 0)
        #expect(AttachmentPolicy.estimatedTokens(of: "abc") == 1)
        #expect(AttachmentPolicy.estimatedTokens(of: "abcd") == 2)
    }

    // Ollama: half the context of the loaded model, from `/api/ps`.
    @Test func ollamaTakesHalfTheLoadedContext() async {
        let url = FakeChatServer.serve(.init(body: """
            {"models":[{"name":"altro:latest","model":"altro:latest","context_length":131072},
                       {"name":"qwen3:8b","model":"qwen3:8b","context_length":8192}]}
            """), onMac: true)
        let ollama = Self.endpoint(.ollama, at: url, model: "qwen3:8b")
        #expect(await reader.contextLength(of: ollama) == 8_192)
        #expect(await verdict(tokens: 4_096, to: ollama) == .allowed)
        #expect(await verdict(tokens: 4_097, to: ollama) == .overCap(tokens: 4_097, cap: 4_096))
        #expect(FakeChatServer.requests(at: url).first?.url.path() == "/api/ps")
    }

    @Test func ollamaWithoutTheModelLoadedTakesItsDefault() async {
        let url = FakeChatServer.serve(.init(body: #"{"models":[]}"#), onMac: true)
        let ollama = Self.endpoint(.ollama, at: url)
        #expect(await reader.contextLength(of: ollama) == EndpointContextReader.localDefault)
        #expect(await verdict(tokens: 2_048, to: ollama) == .allowed)
        #expect(await verdict(tokens: 2_049, to: ollama) == .overCap(tokens: 2_049, cap: 2_048))
    }

    @Test func aLocalServerThatIsOffTakesItsDefault() async {
        let url = FakeChatServer.serve(.init(body: "", isOffline: true), onMac: true)
        #expect(await reader.contextLength(of: Self.endpoint(.lmStudio, at: url)) == EndpointContextReader.localDefault)
    }

    // LM Studio: half the context of the loaded instance, from `/api/v1/models`.
    @Test func lmStudioTakesHalfTheLoadedInstancesContext() async {
        let url = FakeChatServer.serve(.init(body: """
            {"models":[{"type":"llm","key":"qwen/qwen3-4b","max_context_length":262144,
              "loaded_instances":[{"id":"qwen/qwen3-4b","config":{"context_length":16384}}]}]}
            """), onMac: true)
        let lmStudio = Self.endpoint(.lmStudio, at: url, model: "qwen/qwen3-4b")
        #expect(await reader.contextLength(of: lmStudio) == 16_384)
        #expect(await verdict(tokens: 8_192, to: lmStudio) == .allowed)
        #expect(await verdict(tokens: 8_193, to: lmStudio) == .overCap(tokens: 8_193, cap: 8_192))
        #expect(FakeChatServer.requests(at: url).first?.url.path() == "/api/v1/models")
    }

    // OpenRouter: half the context it lists for the model.
    @Test func openRouterTakesHalfTheListedContext() async {
        let url = FakeChatServer.serve(.init(body: """
            {"data":[{"id":"openai/gpt-5-mini","context_length":400000},{"id":"altro","context_length":8000}]}
            """))
        let openRouter = Self.endpoint(.openRouter, at: url.appending(path: "api/v1"), model: "openai/gpt-5-mini")
        #expect(await reader.contextLength(of: openRouter) == 400_000)
        #expect(await verdict(tokens: 200_000, to: openRouter) == .allowed)
        #expect(await verdict(tokens: 200_001, to: openRouter) == .overCap(tokens: 200_001, cap: 200_000))
    }

    @Test func openRouterWithoutTheModelTakesTheFixedCap() async {
        let url = FakeChatServer.serve(.init(body: #"{"data":[]}"#))
        let openRouter = Self.endpoint(.openRouter, at: url, model: "sconosciuto")
        #expect(await reader.contextLength(of: openRouter) == nil)
        #expect(await verdict(tokens: 32_001, to: openRouter) == .overCap(tokens: 32_001, cap: 32_000))
    }

    // OpenAI, Gemini and custom endpoints tell no context: 32.000 tokens, and nothing is asked of them.
    @Test(arguments: [OpenAICompatibleEndpoint.Kind.openAI, .gemini, .custom])
    func clientsWithoutMetadataTakeThirtyTwoThousandTokens(kind: OpenAICompatibleEndpoint.Kind) async {
        let url = FakeChatServer.serve(.init(body: "{}"))
        let endpoint = Self.endpoint(kind, at: url)
        #expect(await verdict(tokens: 32_000, to: endpoint) == .allowed)
        #expect(await verdict(tokens: 32_001, to: endpoint) == .overCap(tokens: 32_001, cap: 32_000))
        #expect(FakeChatServer.requests(at: url).isEmpty)
    }

    @Test func aCloudAsksToConfirmEachAllegatoOnce() {
        let cloud = Self.endpoint(.openAI, at: URL(string: "https://api.openai.com/v1")!)
        let first = Allegato(name: "uno.md", text: "uno"), second = Allegato(name: "due.md", text: "due")
        #expect(AttachmentPolicy.verdict(for: [first, second], to: cloud, contextLength: nil, confirmed: [])
            == .needsConfirmation([first, second]))
        #expect(AttachmentPolicy.verdict(for: [first, second], to: cloud, contextLength: nil, confirmed: [first])
            == .needsConfirmation([second]))
        #expect(AttachmentPolicy.verdict(for: [first, second], to: cloud, contextLength: nil, confirmed: [first, second])
            == .allowed)
    }

    @Test func aModelOnTheMacNeedsNoConfirmation() {
        let ollama = Self.endpoint(.ollama, at: URL(string: "http://localhost:11434/v1")!)
        #expect(AttachmentPolicy.verdict(for: [Allegato(name: "uno.md", text: "uno")], to: ollama, contextLength: 4_096,
                                         confirmed: []) == .allowed)
    }

    @Test func aFolderOrAnImageGoesOnlyToClaude() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "AttachmentCapTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = folder.appending(path: "Schermata.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)
        let ollama = Self.endpoint(.ollama, at: URL(string: "http://localhost:11434/v1")!)
        for allegato in [Allegato(fileAt: folder), Allegato(fileAt: image)] {
            #expect(AttachmentPolicy.verdict(for: [allegato], to: ollama, contextLength: 4_096, confirmed: [allegato])
                == .onlyClaude(allegato))
        }
    }

    @Test func theEndpointReadsTheAllegatiAfterTheQuestion() {
        #expect(AttachmentPolicy.prompt("Riassumi", attachments: [Allegato(name: "nota.md", text: "Testo")]) == """
            Riassumi

            --- nota.md ---
            Testo
            """)
        #expect(AttachmentPolicy.prompt("Ciao", attachments: []) == "Ciao")
    }
}
