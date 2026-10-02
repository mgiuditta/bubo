import Foundation
import os

/// Finds Ollama and LM Studio on this Mac, and the models they have, for the Modello locale (spec 10).
///
/// Ollama tells the models it has loaded (`/api/ps`) and the ones it has, with when they changed (`/api/tags`);
/// LM Studio tells both in one list (`/api/v1/models`), without a date. Nothing is sent but the request for the list.
nonisolated struct LocalModelDetector: Sendable {
    /// What Bubo proposes once: a server on the Mac and the model to use on it.
    struct Offer: Equatable, Sendable {
        /// The server's endpoint, without a model yet.
        let endpoint: OpenAICompatibleEndpoint
        /// The model id, as the server calls it: the loaded one, or else Ollama's latest.
        let model: String
    }

    /// Whether a server on the Mac can answer with the model it was set with.
    enum Availability: Equatable, Sendable {
        case available
        /// The server does not answer: not running, or not installed.
        case serverOff
        /// The server answers, but no longer has the model.
        case modelMissing
    }

    /// Creates a detector that asks through `session`; tests pass one served by a stand-in server.
    init(session: URLSession = .shared) {
        self.session = session
    }

    private let session: URLSession

    /// The model to propose on the first of `endpoints` that answers, Ollama and LM Studio only; `nil` when none
    /// answers, or none has a model to propose.
    ///
    /// The model loaded now comes first; without one, Ollama's most recently changed. LM Studio gives no date, so
    /// without a loaded model it proposes nothing (preflight of #94).
    func offer(among endpoints: [OpenAICompatibleEndpoint]) async -> Offer? {
        for endpoint in endpoints {
            if let model = await proposedModel(on: endpoint) {
                return Offer(endpoint: endpoint, model: model)
            }
        }
        return nil
    }

    /// Whether `endpoint`, a server on the Mac, can answer with its model now.
    func availability(of endpoint: OpenAICompatibleEndpoint) async -> Availability {
        guard let models = await installedModels(on: endpoint) else { return .serverOff }
        return models.contains { Self.names($0, endpoint.model) } ? .available : .modelMissing
    }

    private func proposedModel(on endpoint: OpenAICompatibleEndpoint) async -> String? {
        switch endpoint.kind {
        case .ollama:
            if let data = await data(at: "api/ps", of: endpoint), let loaded = Self.ollamaModels(in: data).first {
                return loaded.name
            }
            guard let data = await data(at: "api/tags", of: endpoint) else { return nil }
            return Self.ollamaModels(in: data).max { ($0.modifiedAt ?? .distantPast) < ($1.modifiedAt ?? .distantPast) }?
                .name
        case .lmStudio:
            guard let data = await data(at: "api/v1/models", of: endpoint) else { return nil }
            return Self.lmStudioModels(in: data).first { $0.isLoaded }?.key
        case .openAI, .gemini, .openRouter, .custom:
            return nil
        }
    }

    /// The ids of the models `endpoint`'s server has; `nil` when it does not answer.
    private func installedModels(on endpoint: OpenAICompatibleEndpoint) async -> [String]? {
        switch endpoint.kind {
        case .ollama:
            guard let data = await data(at: "api/tags", of: endpoint) else { return nil }
            return Self.ollamaModels(in: data).map(\.name)
        case .lmStudio:
            guard let data = await data(at: "api/v1/models", of: endpoint) else { return nil }
            return Self.lmStudioModels(in: data).map(\.key)
        case .openAI, .gemini, .openRouter, .custom:
            return nil
        }
    }

    /// The body of `path` on `endpoint`'s server; `nil` when it does not answer, or answers with an error.
    private func data(at path: String, of endpoint: OpenAICompatibleEndpoint) async -> Data? {
        guard var components = URLComponents(url: endpoint.baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/" + path
        guard let url = components.url else { return nil }
        // A server on the Mac answers at once, or not at all: the Domanda does not wait for it.
        let request = URLRequest(url: url, timeoutInterval: 2)
        do {
            let (data, response) = try await session.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
                return nil
            }
            return data
        } catch {
            Logger.agent.notice("\(endpoint.id, privacy: .public) not answering: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Whether `listed`, a model id as the server lists it, is `wanted`; Ollama's `:latest` tag may be left out.
    static func names(_ listed: String, _ wanted: String) -> Bool {
        let wanted = wanted.trimmingCharacters(in: .whitespaces)
        return listed == wanted || listed == wanted + ":latest"
    }

    /// A model of Ollama's `/api/ps` or `/api/tags`.
    struct OllamaModel {
        let name: String
        let modifiedAt: Date?
    }

    /// The models in an answer of Ollama, in its order.
    static func ollamaModels(in data: Data) -> [OllamaModel] {
        struct Listed: Decodable {
            struct Model: Decodable {
                let name: String?
                let model: String?
                let modifiedAt: String?
            }
            let models: [Model]
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let listed = try? decoder.decode(Listed.self, from: data) else { return [] }
        return listed.models.compactMap { model in
            guard let name = model.name ?? model.model else { return nil }
            return OllamaModel(name: name, modifiedAt: model.modifiedAt.flatMap(date))
        }
    }

    /// A date as Ollama writes it, such as `2026-09-30T10:12:44.123456789+02:00`: the fraction of a second is
    /// dropped, since its digits go past what ISO 8601 parsing takes.
    static func date(_ text: String) -> Date? {
        let whole = text.replacing(/\.\d+/, with: "")
        return try? Date(whole, strategy: .iso8601)
    }

    /// A model of LM Studio's `/api/v1/models`.
    struct LMStudioModel {
        let key: String
        let isLoaded: Bool
    }

    /// The language models in an answer of LM Studio, in its order: not the embedding ones.
    static func lmStudioModels(in data: Data) -> [LMStudioModel] {
        struct Listed: Decodable {
            struct Model: Decodable {
                struct Instance: Decodable { let id: String? }
                let type: String?
                let key: String?
                let loadedInstances: [Instance]?
            }
            let models: [Model]
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let listed = try? decoder.decode(Listed.self, from: data) else { return [] }
        return listed.models.compactMap { model in
            guard let key = model.key, model.type != "embedding" else { return nil }
            return LMStudioModel(key: key, isLoaded: !(model.loadedInstances ?? []).isEmpty)
        }
    }
}
