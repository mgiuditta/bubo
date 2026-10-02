import Foundation
import Hub
import MLX
import MLXEmbedders
import MLXLMCommon
import os
import Tokenizers

/// What a text is, for models trained with a different prefix for each.
nonisolated enum EmbeddingRole: Sendable {
    /// A search.
    case query
    /// A fragment of a note.
    case passage
}

/// Turns text into vectors that can be compared with a dot product.
nonisolated protocol TextEmbedder: AnyObject, Sendable {
    /// The model the vectors come from: vectors of different models cannot be compared.
    var model: TextEmbeddingModel { get }

    /// Returns one unit-length vector per text, in order.
    func vectors(for texts: [String], as role: EmbeddingRole) async throws -> [[Float]]
}

/// Turns text into vectors with a downloaded ``TextEmbeddingModel``, on the Mac's GPU.
///
/// The model is loaded at the first request and let go after a minute without requests,
/// so it holds no memory while the Indice is idle. It reads only its own folder: no network.
actor Embedder: TextEmbedder {
    /// Creates an embedder for `model`, installed at `directory`.
    /// - Parameter idleTime: How long the model stays loaded after the last request.
    init(model: TextEmbeddingModel, directory: URL, idleTime: Duration = .seconds(60)) {
        self.model = model
        self.directory = directory
        self.idleTime = idleTime
    }

    /// The model the vectors come from.
    nonisolated let model: TextEmbeddingModel
    private let directory: URL
    private let idleTime: Duration
    private var container: EmbedderModelContainer?
    private var loading: Task<EmbedderModelContainer, any Error>?
    private var unloading: Task<Void, Never>?

    /// Whether the model is in memory now.
    var isLoaded: Bool { container != nil }

    func vectors(for texts: [String], as role: EmbeddingRole) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        unloading?.cancel()
        defer { scheduleUnload() }
        let container = try await loadedContainer()
        let prefix = role == .query ? model.queryPrefix : model.passagePrefix
        let inputs = texts.map { prefix + $0 }
        let maximumTokens = model.maximumTokens
        return try await container.perform { context in
            try Task.checkCancellation()
            let padding = (context.tokenizer as? TokenizerAdapter)?.paddingID ?? context.tokenizer.eosTokenId ?? 0
            let encoded = inputs.map { input in
                let tokens = context.tokenizer.encode(text: input, addSpecialTokens: true)
                // The closing special token stays: the pooling of some models reads it.
                return tokens.count > maximumTokens ? tokens.prefix(maximumTokens - 1) + [tokens[tokens.count - 1]] : tokens
            }
            let length = encoded.map(\.count).max() ?? 0
            let ids = MLXArray(encoded.flatMap { $0 + Array(repeating: padding, count: length - $0.count) }.map(Int32.init),
                               [encoded.count, length])
            let mask = MLXArray(encoded.flatMap { Array(repeating: Float(1), count: $0.count)
                + Array(repeating: Float(0), count: length - $0.count) }, [encoded.count, length])
            let output = context.model(ids, positionIds: nil, tokenTypeIds: MLXArray.zeros(like: ids), attentionMask: mask)
            let pooled = context.pooling(output, mask: mask, normalize: true).asType(.float32)
            pooled.eval()
            let dimension = pooled.dim(1)
            let flat = pooled.asArray(Float.self)
            return (0..<encoded.count).map { Array(flat[($0 * dimension)..<(($0 + 1) * dimension)]) }
        }
    }

    /// Lets the model go now.
    func unload() {
        unloading?.cancel()
        loading?.cancel()
        loading = nil
        container = nil
        Memory.clearCache()
    }

    private func loadedContainer() async throws -> EmbedderModelContainer {
        if let container { return container }
        let task = loading ?? Task { [directory, model] in
            let started = ContinuousClock.now
            let container = try await EmbedderModelFactory.shared.loadContainer(from: directory, using: TokenizerAdapter.Loader())
            Logger.index.notice("Embedding model \(model.id, privacy: .public) loaded in \(ContinuousClock.now - started, privacy: .public)")
            return container
        }
        loading = task
        do {
            let loaded = try await task.value
            // Another request may have unloaded it meanwhile: the newest state wins.
            if loading == task {
                container = loaded
                loading = nil
            }
            return loaded
        } catch {
            if loading == task { loading = nil }
            throw error
        }
    }

    private func scheduleUnload() {
        unloading?.cancel()
        unloading = Task { [idleTime] in
            try? await Task.sleep(for: idleTime)
            guard !Task.isCancelled else { return }
            self.unloadIfIdle()
        }
    }

    private func unloadIfIdle() {
        guard container != nil else { return }
        container = nil
        Memory.clearCache()
        Logger.index.notice("Embedding model \(self.model.id, privacy: .public) unloaded")
    }
}

/// A tokenizer of swift-transformers, read from the model's own folder, as MLX wants it.
private nonisolated struct TokenizerAdapter: MLXLMCommon.Tokenizer {
    /// Loads the tokenizer next to the weights, without the Hugging Face client: no network, no cache folders.
    struct Loader: MLXLMCommon.TokenizerLoader {
        func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
            func configuration(_ name: String) throws -> Config {
                let data = try Data(contentsOf: directory.appending(path: name))
                guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [NSString: Any] else {
                    throw Tokenizers.TokenizerError.missingConfig
                }
                return Config(dictionary)
            }
            return TokenizerAdapter(upstream: try PreTrainedTokenizer(tokenizerConfig: configuration("tokenizer_config.json"),
                                                                      tokenizerData: configuration("tokenizer.json")))
        }
    }

    let upstream: any Tokenizers.Tokenizer

    /// The token that fills shorter inputs of a batch: the model's padding, else its end.
    var paddingID: Int? { upstream.convertTokenToId("<pad>") ?? upstream.eosTokenId }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        // An embedder never chats.
        throw Tokenizers.TokenizerError.missingChatTemplate
    }
}
