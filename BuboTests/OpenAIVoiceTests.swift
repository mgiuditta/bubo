import Foundation
import Testing
@testable import Bubo

/// OpenAI's voice for the Sintesi parlata (#109): only the text leaves, only with the key, and any failure before the
/// first audio hands the Sintesi back to the Mac's voice. Served by a stand-in server; no real call, no audio.
@Suite(.timeLimit(.minutes(1)))
struct OpenAIVoiceTests {
    /// The voice of a stand-in server that replies `reply`, and the address it is served at.
    static func voice(_ reply: FakeChatServer.Reply) -> (OpenAIVoice, URL) {
        let url = FakeChatServer.serve(reply)
        return (OpenAIVoice(baseURL: url, session: FakeChatServer.session), url)
    }

    static func collect(_ stream: AsyncStream<Data>) async -> Data {
        var data = Data()
        for await piece in stream { data.append(piece) }
        return data
    }

    @Test func theAudioStreamsWithTheSintesisTextOnly() async throws {
        let audio = String(repeating: "ab", count: 3_000)
        let (voice, url) = Self.voice(.init(body: audio))

        let stream = try #require(await voice.startedAudio(of: "A Lima sono le sette.", key: "sk-prova"))

        #expect(await Self.collect(stream) == Data(audio.utf8))
        let request = try #require(FakeChatServer.requests(at: url).first)
        #expect(request.url == url.appending(path: "audio/speech"))
        #expect(request.headers["Authorization"] == "Bearer sk-prova")
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: String])
        #expect(body == ["model": "gpt-4o-mini-tts", "input": "A Lima sono le sette.", "voice": "coral",
                         "response_format": "pcm"])
    }

    @Test func thePiecesAreWholeSamples() async throws {
        let (voice, _) = Self.voice(.init(body: String(repeating: "x", count: OpenAIVoice.pieceSize + 3)))

        let stream = try #require(await voice.startedAudio(of: "Ciao", key: "k"))
        var sizes: [Int] = []
        for await piece in stream { sizes.append(piece.count) }

        #expect(sizes == [OpenAIVoice.pieceSize, 2])
    }

    // Acceptance of #109: on only with the OpenAI key.
    @Test func withoutAKeyNothingIsSent() async {
        let (voice, url) = Self.voice(.init(body: "ab"))

        #expect(await voice.startedAudio(of: "Segreto", key: nil) == nil)
        #expect(await voice.startedAudio(of: "Segreto", key: "") == nil)
        #expect(FakeChatServer.requests(at: url).isEmpty)
    }

    // Acceptance of #109: back to the Mac's voice on an error.
    @Test(arguments: [
        FakeChatServer.Reply(status: 500, body: #"{"error":{"message":"guasto"}}"#),
        FakeChatServer.Reply(status: 401, body: ""),
        FakeChatServer.Reply(status: 200, body: ""),
    ])
    func anErrorBeforeTheFirstAudioFallsBack(reply: FakeChatServer.Reply) async {
        let (voice, _) = Self.voice(reply)

        #expect(await voice.startedAudio(of: "Ciao", key: "k") == nil)
    }

    // Acceptance of #109: back to the Mac's voice with no network.
    @Test func noNetworkFallsBack() async {
        let (voice, _) = Self.voice(.init(body: "ab", isOffline: true))

        #expect(await voice.startedAudio(of: "Ciao", key: "k") == nil)
    }

    @Test func aPieceBecomesFloatSamples() throws {
        var pcm = Data()
        for sample: Int16 in [0, 16_384, -32_768] {
            withUnsafeBytes(of: sample.littleEndian) { pcm.append(contentsOf: $0) }
        }

        let buffer = try #require(OpenAIVoice.buffer(of: pcm))

        #expect(buffer.format.sampleRate == 24_000)
        #expect(buffer.frameLength == 3)
        let channel = try #require(buffer.floatChannelData?[0])
        #expect([channel[0], channel[1], channel[2]] == [0, 0.5, -1])
    }

    // Acceptance of #109: off by default.
    @Test func theVoiceIsOffByDefault() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        #expect(!defaults.bool(forKey: OpenAIVoice.isOnKey))
    }
}
