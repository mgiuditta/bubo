import Foundation
import os

/// Reads the context of an endpoint's model from its server, for the cap of the Allegati (spec 09).
///
/// Ollama tells the context of the model it has loaded (`/api/ps`), LM Studio the one of each loaded instance
/// (`/api/v1/models`), OpenRouter the one of each model it lists (`/api/v1/models`). OpenAI, Gemini and the custom
/// endpoints tell none, and take the fixed cap.
nonisolated struct EndpointContextReader: Sendable {
    /// The context a local server loads a model with when it says nothing: Ollama's default under 24 GiB of VRAM.
    static let localDefault = 4_096

    /// Creates a reader that asks through `session`; tests pass one served by a stand-in server.
    init(session: URLSession = .shared) {
        self.session = session
    }

    private let session: URLSession

    /// The context, in tokens, of `endpoint`'s model; `nil` for an endpoint that tells none.
    ///
    /// A server on the Mac that does not answer, or has not loaded the model, counts as ``localDefault``: the smallest
    /// context it would load the model with.
    func contextLength(of endpoint: OpenAICompatibleEndpoint) async -> Int? {
        guard let url = Self.address(for: endpoint) else { return nil }
        let fallback = endpoint.kind == .openRouter ? nil : Self.localDefault
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else {
                return fallback
            }
            return Self.contextLength(in: data, for: endpoint) ?? fallback
        } catch {
            Logger.agent.notice("Context of \(endpoint.id, privacy: .public) not read: \(String(describing: error), privacy: .public)")
            return fallback
        }
    }

    /// Where `endpoint`'s server tells the context of its models; `nil` for the endpoints that tell none.
    static func address(for endpoint: OpenAICompatibleEndpoint) -> URL? {
        switch endpoint.kind {
        case .openRouter: endpoint.baseURL.appending(path: "models")
        case .ollama: serverRoot(of: endpoint.baseURL)?.appending(path: "api/ps")
        case .lmStudio: serverRoot(of: endpoint.baseURL)?.appending(path: "api/v1/models")
        case .openAI, .gemini, .custom: nil
        }
    }

    /// The context of `endpoint`'s model in `data`, its server's answer; `nil` when the model is not there.
    static func contextLength(in data: Data, for endpoint: OpenAICompatibleEndpoint) -> Int? {
        let model = endpoint.model.trimmingCharacters(in: .whitespaces)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        switch endpoint.kind {
        case .ollama:
            struct Running: Decodable {
                struct Model: Decodable {
                    let name: String?
                    let model: String?
                    let contextLength: Int?
                }
                let models: [Model]
            }
            let running = try? decoder.decode(Running.self, from: data)
            return running?.models.first { $0.name == model || $0.model == model }?.contextLength
        case .lmStudio:
            struct Listed: Decodable {
                struct Model: Decodable {
                    struct Instance: Decodable {
                        struct Config: Decodable { let contextLength: Int? }
                        let id: String?
                        let config: Config?
                    }
                    let key: String?
                    let loadedInstances: [Instance]?
                }
                let models: [Model]
            }
            let instances = (try? decoder.decode(Listed.self, from: data))?.models.flatMap { listed in
                (listed.loadedInstances ?? []).filter { listed.key == model || $0.id == model }
            }
            return instances?.compactMap(\.config?.contextLength).first
        case .openRouter:
            struct Listed: Decodable {
                struct Model: Decodable {
                    let id: String
                    let contextLength: Int?
                }
                let data: [Model]
            }
            return (try? decoder.decode(Listed.self, from: data))?.data.first { $0.id == model }?.contextLength
        case .openAI, .gemini, .custom:
            return nil
        }
    }

    /// The server's address without the `/v1` of Chat Completions, such as `http://localhost:11434`.
    private static func serverRoot(of baseURL: URL) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path = ""
        return components.url
    }
}
