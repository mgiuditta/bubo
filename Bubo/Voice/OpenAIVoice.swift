import AVFoundation
import OSLog

/// The voice of OpenAI's `gpt-4o-mini-tts`, which says the Sintesi parlata when the user turns it on in Impostazioni ›
/// Voce (spec 08, opt-in cloud).
///
/// It sends the Sintesi parlata's text and nothing else, with the OpenAI key already in the keychain for the Domande.
/// Turning it on is the user's consent: off, and without a key, nothing leaves the Mac.
nonisolated struct OpenAIVoice: Sendable {
    /// The user defaults key of the switch in Impostazioni › Voce; off unless the user turns it on.
    static let isOnKey = "voice.speaksWithOpenAI"
    /// The keychain account of the OpenAI key, the one the Domande use.
    static let keychainAccount = OpenAICompatibleEndpoint.known[0].keychainAccount
    /// The model that speaks.
    static let model = "gpt-4o-mini-tts"
    /// One of OpenAI's voices, warm in Italian as in English.
    static let voice = "coral"
    /// The `pcm` format OpenAI streams: 24 kHz, 16-bit signed little-endian, mono, no header.
    static let sampleRate = 24_000.0
    /// The bytes of each piece of audio handed on: a tenth of a second.
    static let pieceSize = 4_800

    /// Creates the voice of the server at `baseURL`; tests pass a stand-in server and its session.
    init(baseURL: URL = OpenAICompatibleEndpoint.known[0].baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    private let baseURL: URL
    private let session: URLSession

    /// The audio of `text` as it streams, or `nil` when it failed before its first piece, so the Mac's voice says it.
    ///
    /// - Parameter key: The OpenAI key from the keychain; without one nothing is sent.
    /// - Returns: Pieces of 16-bit PCM, each an even number of bytes; the stream ends early, without throwing, if the
    ///   connection drops halfway.
    func startedAudio(of text: String, key: String?) async -> AsyncStream<Data>? {
        let (relay, input) = AsyncStream.makeStream(of: Data.self)
        let (started, startedInput) = AsyncStream.makeStream(of: Bool.self)
        let task = Task {
            var hasStarted = false
            do {
                for try await piece in audio(of: text, key: key) {
                    if !hasStarted {
                        hasStarted = true
                        startedInput.yield(true)
                    }
                    input.yield(piece)
                }
            } catch {
                Logger.voice.notice("OpenAI voice failed: \(String(describing: error), privacy: .public)")
            }
            input.finish()
            startedInput.yield(hasStarted)
            startedInput.finish()
        }
        input.onTermination = { _ in task.cancel() }
        let hasStarted = await withTaskCancellationHandler {
            var iterator = started.makeAsyncIterator()
            return await iterator.next() ?? false
        } onCancel: {
            task.cancel()
        }
        guard hasStarted else {
            input.finish()
            return nil
        }
        return relay
    }

    /// The audio of `text`, in pieces of `pieceSize` bytes as they arrive.
    ///
    /// - Throws: An `OpenAICompatibleError`, before any byte leaves the Mac when there is no key.
    func audio(of text: String, key: String?) -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try Self.request(text, to: baseURL, key: key)
                    let (bytes, response) = try await session.bytes(for: request)
                    if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                        var body = ""
                        for try await line in bytes.lines where body.utf8.count < 2_000 { body += line }
                        throw OpenAICompatibleError(status: status, body: body)
                    }
                    var piece = Data(capacity: Self.pieceSize)
                    for try await byte in bytes {
                        piece.append(byte)
                        if piece.count == Self.pieceSize {
                            continuation.yield(piece)
                            piece.removeAll(keepingCapacity: true)
                        }
                    }
                    // A last odd byte is half a sample: it is dropped.
                    piece.count -= piece.count % 2
                    if !piece.isEmpty { continuation.yield(piece) }
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish(throwing: CancellationError())
                } catch let error as URLError {
                    continuation.finish(throwing: OpenAICompatibleError.unreachable(error.code))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The request that asks the server at `baseURL` to say `text`.
    ///
    /// - Throws: `OpenAICompatibleError.keyMissing` without a key.
    static func request(_ text: String, to baseURL: URL, key: String?) throws(OpenAICompatibleError) -> URLRequest {
        guard let key, !key.isEmpty else { throw .keyMissing }
        var request = URLRequest(url: baseURL.appending(path: "audio/speech"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        // Only the Sintesi parlata's text: the body is built here and nowhere else.
        let body = Body(model: model, input: text, voice: voice, responseFormat: "pcm")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw .unexpectedResponse
        }
        return request
    }

    /// A buffer in 32-bit float, which the player plays, with the samples of `piece`, 16-bit PCM at `sampleRate`.
    static func buffer(of piece: Data) -> AVAudioPCMBuffer? {
        let frames = piece.count / 2
        guard frames > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        piece.withUnsafeBytes { raw in
            for frame in 0..<frames {
                let sample = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: frame * 2, as: Int16.self))
                channel[frame] = Float(sample) / 32_768
            }
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        return buffer
    }

    private struct Body: Encodable {
        let model: String
        let input: String
        let voice: String
        let responseFormat: String

        enum CodingKeys: String, CodingKey {
            case model, input, voice
            case responseFormat = "response_format"
        }
    }
}
