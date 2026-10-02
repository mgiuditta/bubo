import Foundation

/// The one client of the Domande that are not Claude's (spec 10): OpenAI Chat Completions in streaming, straight from the
/// Mac to the endpoint, with no proxy in between.
///
/// It sends the Domanda's text and nothing else: no file, diff or memory of a Progetto, no tool. Towards a cloud that is
/// not Claude it sends nothing at all without the user's consent for that endpoint.
nonisolated struct OpenAICompatibleClient: Sendable {
    /// What arrives of an answer.
    enum Event: Equatable, Sendable {
        /// The next piece of the answer's text.
        case text(String)
        /// The tokens the turn used, as the endpoint counted them; it comes last, when it comes.
        case usage(input: Int, output: Int)
    }

    /// Creates a client that talks through `session`; tests pass one served by a stand-in server.
    init(session: URLSession = .shared) {
        self.session = session
    }

    private let session: URLSession

    /// Streams `endpoint`'s answer to `prompt`.
    ///
    /// - Parameters:
    ///   - consents: The endpoints the user allowed to receive Domande; one on the Mac needs none.
    ///   - key: The endpoint's key from the keychain, if saved.
    /// - Throws: An `OpenAICompatibleError`, before any byte leaves the Mac when the endpoint may not be asked.
    func answer(_ prompt: String, from endpoint: OpenAICompatibleEndpoint, consents: Set<String>,
                key: String?) -> AsyncThrowingStream<Event, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try Self.request(prompt, to: endpoint, consents: consents, key: key)
                    let (bytes, response) = try await session.bytes(for: request)
                    if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                        var body = ""
                        for try await line in bytes.lines where body.utf8.count < 2_000 { body += line }
                        throw OpenAICompatibleError(status: status, body: body)
                    }
                    for try await line in bytes.lines {
                        guard let events = try Self.events(in: line) else { break }
                        for event in events { continuation.yield(event) }
                    }
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

    /// The request that asks `endpoint` about `prompt`, once it is allowed to.
    ///
    /// - Throws: An `OpenAICompatibleError` when the endpoint may not be asked: no consent, Gemini without billing, no
    ///   key where one is needed, no model chosen.
    static func request(_ prompt: String, to endpoint: OpenAICompatibleEndpoint, consents: Set<String>,
                        key: String?) throws(OpenAICompatibleError) -> URLRequest {
        if !endpoint.isOnMac, !consents.contains(endpoint.id) { throw .consentMissing }
        if endpoint.kind == .gemini, !endpoint.confirmsBilling { throw .billingUnconfirmed }
        let model = endpoint.model.trimmingCharacters(in: .whitespaces)
        guard !model.isEmpty else { throw .modelMissing }
        let key = key.flatMap { $0.isEmpty ? nil : $0 }
        if endpoint.requiresKey, key == nil { throw .keyMissing }

        var request = URLRequest(url: endpoint.chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        // Only the Domanda's text: the body is built here and nowhere else.
        let body = Body(model: model, messages: [.init(role: "user", content: prompt)], stream: true,
                        streamOptions: .init(includeUsage: true))
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw .unexpectedResponse
        }
        return request
    }

    /// The events of one line of the server-sent stream; `nil` at `[DONE]`, the end of the answer.
    static func events(in line: String) throws(OpenAICompatibleError) -> [Event]? {
        guard line.hasPrefix("data:") else { return [] }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return nil }
        let chunk: Chunk
        do {
            chunk = try JSONDecoder().decode(Chunk.self, from: Data(payload.utf8))
        } catch {
            throw .unexpectedResponse
        }
        if let message = chunk.error?.message { throw .failed(message) }
        var events = (chunk.choices ?? []).compactMap { $0.delta?.content }.filter { !$0.isEmpty }.map(Event.text)
        if let usage = chunk.usage { events.append(.usage(input: usage.promptTokens, output: usage.completionTokens)) }
        return events
    }

    private struct Body: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        struct StreamOptions: Encodable {
            let includeUsage: Bool

            enum CodingKeys: String, CodingKey {
                case includeUsage = "include_usage"
            }
        }

        let model: String
        let messages: [Message]
        let stream: Bool
        let streamOptions: StreamOptions

        enum CodingKeys: String, CodingKey {
            case model, messages, stream
            case streamOptions = "stream_options"
        }
    }

    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }

            let delta: Delta?
        }

        struct Usage: Decodable {
            let promptTokens: Int
            let completionTokens: Int

            enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
            }
        }

        struct Failure: Decodable {
            let message: String?
        }

        let choices: [Choice]?
        let usage: Usage?
        let error: Failure?
    }
}
