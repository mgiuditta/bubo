import Foundation
import Observation
import os

/// The search by meaning of the Indice: the embedding model the user agreed to download, and its state.
///
/// Until a model is installed the Indice searches only by words, and the settings say so.
@Observable
final class SemanticSearch {
    /// Where the search by meaning stands.
    enum Phase: Equatable {
        /// No model: only words.
        case wordsOnly
        /// The model is downloading; `received` bytes so far.
        case downloading(TextEmbeddingModel, received: Int64)
        /// The model is installed and in use.
        case ready(TextEmbeddingModel)
        /// The download of the model failed, with what went wrong.
        case failed(TextEmbeddingModel, reason: String)
    }

    /// Creates the search by meaning of `index`, with the models of `store` and the choice saved in `defaults`.
    init(index: SearchIndex?, store: TextEmbeddingModelStore?, defaults: UserDefaults = .standard) {
        self.index = index
        self.store = store
        self.defaults = defaults
    }

    private(set) var phase = Phase.wordsOnly

    @ObservationIgnored private let index: SearchIndex?
    @ObservationIgnored private let store: TextEmbeddingModelStore?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var downloading: Task<Void, Never>?
    /// The phase to go back to when a download is cancelled.
    @ObservationIgnored private var beforeDownload = Phase.wordsOnly

    /// The defaults key of the model in use.
    static let modelKey = "index.embeddingModel"

    /// The model in use, if any.
    var model: TextEmbeddingModel? {
        if case let .ready(model) = phase { model } else { nil }
    }

    /// Uses the model chosen at a previous launch, if it is still installed.
    func start() {
        guard let store, let id = defaults.string(forKey: Self.modelKey),
              let model = TextEmbeddingModel.all.first(where: { $0.id == id }), store.isInstalled(model) else { return }
        use(model, from: store)
    }

    /// Downloads `model`, with the user's consent, and searches with it once it is checked.
    ///
    /// The model in use, if any, stays until the new one is ready; then it is deleted.
    func download(_ model: TextEmbeddingModel) {
        guard let store, downloading == nil else { return }
        beforeDownload = phase
        phase = .downloading(model, received: 0)
        downloading = Task {
            defer { downloading = nil }
            let (received, report) = AsyncStream.makeStream(of: Int64.self, bufferingPolicy: .bufferingNewest(1))
            let showing = Task {
                // At most ten redraws a second: the stream keeps only the newest count.
                for await bytes in received {
                    phase = .downloading(model, received: bytes)
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            defer { showing.cancel() }
            do {
                try await store.install(model) { report.yield($0) }
                report.finish()
                await showing.value
                use(model, from: store)
                store.removeAll(except: model)
            } catch where Task.isCancelled || (error as? URLError)?.code == .cancelled {
                phase = beforeDownload
            } catch {
                Logger.index.error("Embedding model download failed: \(error)")
                phase = .failed(model, reason: Self.reason(for: error))
            }
        }
    }

    /// Stops the download under way; the files already checked are kept for the next attempt.
    func cancelDownload() {
        downloading?.cancel()
    }

    /// Stops searching by meaning and deletes the model: the Indice goes back to words only.
    func removeModel() {
        guard let store, downloading == nil else { return }
        defaults.removeObject(forKey: Self.modelKey)
        phase = .wordsOnly
        Task { [index] in await index?.use(nil) }
        try? FileManager.default.removeItem(at: store.folder)
    }

    private func use(_ model: TextEmbeddingModel, from store: TextEmbeddingModelStore) {
        defaults.set(model.id, forKey: Self.modelKey)
        phase = .ready(model)
        let embedder = Embedder(model: model, directory: store.directory(of: model))
        Task(priority: .utility) { [index] in await index?.use(embedder) }
    }

    private static func reason(for error: any Error) -> String {
        switch error {
        case TextEmbeddingModelError.corrupted:
            String(localized: "Un file del modello non è quello atteso.")
        case TextEmbeddingModelError.unavailable:
            String(localized: "Hugging Face non ha consegnato un file del modello.")
        default:
            error.localizedDescription
        }
    }
}
