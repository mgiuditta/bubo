import CryptoKit
import Foundation
import Synchronization
import Testing
@testable import Bubo

/// Serves fixed bytes for each URL, in place of Hugging Face.
nonisolated final class FixedFilesProtocol: URLProtocol {
    static let files = Mutex<[URL: Data]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let data = Self.files.withLock({ $0[url] }) else {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil,
                                                                  headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.timeLimit(.minutes(1)))
struct TextEmbeddingModelTests {
    let folder = URL.temporaryDirectory.appending(path: "TextEmbeddingModelTests-\(UUID().uuidString)")
    var store: TextEmbeddingModelStore { TextEmbeddingModelStore(folder: folder) }
    let configuration: URLSessionConfiguration = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixedFilesProtocol.self]
        return configuration
    }()

    /// A model of two small files, served by ``FixedFilesProtocol`` as `served`.
    func model(served: [String: Data], expected: [String: Data]) -> TextEmbeddingModel {
        let model = TextEmbeddingModel(
            id: "prova", name: "prova", repository: "prova/\(UUID().uuidString)", revision: "abc",
            files: expected.keys.sorted().map { path in
                let data = expected[path]!
                return .init(path: path, size: Int64(data.count),
                             sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            },
            queryPrefix: "", passagePrefix: "", maximumTokens: 512)
        FixedFilesProtocol.files.withLock { files in
            for file in model.files { files[model.url(of: file)] = served[file.path] }
        }
        return model
    }

    @Test func aCheckedModelIsInstalledWithItsFiles() async throws {
        let files = ["config.json": Data("{}".utf8), "1_Pooling/config.json": Data("{\"a\":1}".utf8)]
        let model = model(served: files, expected: files)
        let received = Mutex<[Int64]>([])

        try await store.install(model, configuration: configuration) { bytes in received.withLock { $0.append(bytes) } }

        #expect(store.isInstalled(model))
        #expect(try Data(contentsOf: store.directory(of: model).appending(path: "1_Pooling/config.json")) == Data("{\"a\":1}".utf8))
        #expect(received.withLock { $0.last } == model.size)
    }

    @Test func aFileWithAnotherChecksumIsRefused() async throws {
        let model = model(served: ["model.safetensors": Data("pesi alterati".utf8)],
                          expected: ["model.safetensors": Data("pesi originali".utf8)])

        await #expect(throws: TextEmbeddingModelError.corrupted(file: "model.safetensors")) {
            try await store.install(model, configuration: configuration) { _ in }
        }
        #expect(!store.isInstalled(model))
        #expect(!FileManager.default.fileExists(atPath: store.directory(of: model).appending(path: "model.safetensors").path))
    }

    @Test func aMissingFileIsReported() async throws {
        let model = model(served: [:], expected: ["config.json": Data("{}".utf8)])

        await #expect(throws: TextEmbeddingModelError.unavailable(file: "config.json")) {
            try await store.install(model, configuration: configuration) { _ in }
        }
    }

    @Test func theModelsComeFromAFixedRevision() {
        for model in TextEmbeddingModel.all {
            #expect(model.revision.count == 40)
            for file in model.files {
                #expect(model.url(of: file).absoluteString.hasPrefix("https://huggingface.co/\(model.repository)/resolve/\(model.revision)/"))
                #expect(file.sha256.count == 64)
            }
        }
    }
}

/// The real models, run when `BUBO_EMBEDDING_MODELS` names a folder holding them as the app installs them
/// (`<model>/<revision>`); with `xcodebuild`, pass it as `TEST_RUNNER_BUBO_EMBEDDING_MODELS`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BUBO_EMBEDDING_MODELS"] != nil), .serialized,
       .timeLimit(.minutes(5)))
struct RealModelTests {
    let store = TextEmbeddingModelStore(folder: URL(filePath: ProcessInfo.processInfo.environment["BUBO_EMBEDDING_MODELS"] ?? "/"))

    /// The spec's criteria: Recall@1 ≥ 0,80 on the Italian set, and a query within the 50 ms budget.
    @Test(arguments: TextEmbeddingModel.all)
    func theItalianSetIsRecalled(model: TextEmbeddingModel) async throws {
        let directory = store.directory(of: model)
        try #require(FileManager.default.fileExists(atPath: directory.appending(path: "model.safetensors").path),
                     "\(model.id) is not in the folder")
        let embedder = Embedder(model: model, directory: directory)
        let notes = try await embedder.vectors(for: ItalianRecallSet.notes, as: .passage)
        var matrix = VectorMatrix(dimension: notes[0].count)
        for (index, vector) in notes.enumerated() {
            matrix.insert(VectorMatrix.half(vector), for: Int64(index))
        }
        var found = 0
        var durations: [Duration] = []
        for (index, question) in ItalianRecallSet.questions.enumerated() {
            let started = ContinuousClock.now
            let query = try await embedder.vectors(for: [question], as: .query)[0]
            if matrix.nearest(to: query, limit: 1) == [Int64(index)] { found += 1 }
            durations.append(ContinuousClock.now - started)
        }
        let recall = Double(found) / Double(ItalianRecallSet.questions.count)
        let p95 = durations.sorted()[Int(Double(durations.count) * 0.95) - 1]
        print("\(model.id): Recall@1 \(recall), query p95 \(p95)")
        #expect(recall >= 0.8)
        #expect(p95 < .milliseconds(50))
    }

    /// The same criterion through the whole Indice: words and meaning fused, as the `cerca` tool sees them.
    @Test(arguments: TextEmbeddingModel.all)
    func theItalianSetIsRecalledByTheHybridSearch(model: TextEmbeddingModel) async throws {
        let directory = store.directory(of: model)
        try #require(FileManager.default.fileExists(atPath: directory.appending(path: "model.safetensors").path),
                     "\(model.id) is not in the folder")
        let claude = try ClaudeFolder()
        for (index, note) in ItalianRecallSet.notes.enumerated() {
            try claude.write(note, to: "projects/-p/memory/\(index).md")
        }
        let index = try claude.open()
        await index.use(Embedder(model: model, directory: directory))
        await index.rescan()
        await index.vectorsComputed()
        var found = 0
        var durations: [Duration] = []
        for (number, question) in ItalianRecallSet.questions.enumerated() {
            let started = ContinuousClock.now
            let hits = try await index.hits(for: question, limit: 1)
            durations.append(ContinuousClock.now - started)
            if hits.first?.path.hasSuffix("/\(number).md") == true { found += 1 }
        }
        let recall = Double(found) / Double(ItalianRecallSet.questions.count)
        let p95 = durations.sorted()[Int(Double(durations.count) * 0.95) - 1]
        print("\(model.id) hybrid: Recall@1 \(recall), query p95 \(p95)")
        #expect(recall >= 0.8)
        #expect(p95 < .milliseconds(50))
    }

    /// The same criterion as the Palette sees it: each note a past conversation, one row per conversation.
    @Test(arguments: TextEmbeddingModel.all)
    func theItalianSetIsRecalledByThePalette(model: TextEmbeddingModel) async throws {
        let directory = store.directory(of: model)
        try #require(FileManager.default.fileExists(atPath: directory.appending(path: "model.safetensors").path),
                     "\(model.id) is not in the folder")
        let claude = try ClaudeFolder()
        let index = try claude.open()
        let now = Date.now
        for (number, note) in ItalianRecallSet.notes.enumerated() {
            try await index.store([CLIConversation.Message(id: "m", isFromUser: true, text: note, date: now)],
                                  ofConversation: "c\(number)", in: nil, modified: now)
        }
        await index.use(Embedder(model: model, directory: directory))
        await index.vectorsComputed()
        let search = ConversationSearch(index: index, sessions: [], history: [])
        var found = 0
        for (number, question) in ItalianRecallSet.questions.enumerated() {
            var query = PaletteQuery()
            query.text = question
            let first = try await search.groups(for: query, at: now).first?.results.first
            if first?.id == "c\(number)" { found += 1 }
        }
        let recall = Double(found) / Double(ItalianRecallSet.questions.count)
        print("\(model.id) Palette: Recall@1 \(recall)")
        #expect(recall >= 0.8)
    }

    /// The spec's first indexing: 10.000 notes in 3 minutes at most, on a base M-series Mac with the standard model.
    @Test func tenThousandNotesAreIndexedWithinThreeMinutes() async throws {
        let model = TextEmbeddingModel.standard
        let directory = store.directory(of: model)
        try #require(FileManager.default.fileExists(atPath: directory.appending(path: "model.safetensors").path),
                     "\(model.id) is not in the folder")
        let folder = try NotesFolder()
        let notes = ItalianRecallSet.notes
        for number in 0..<10_000 {
            let sections = (0..<3).map { "## Parte \($0 + 1)\n\n\(notes[(number + $0 * 7) % notes.count])" }
            try folder.write("# Nota \(number)\n\n" + sections.joined(separator: "\n\n"),
                             to: "Cartella \(number % 20)/Nota \(number).md")
        }
        let index = try folder.claude.open()
        await index.use(Embedder(model: model, directory: directory))

        let started = ContinuousClock.now
        let following = folder.follow(folder.notes, with: index)
        defer { following.cancel() }
        while try await index.fragmentLoad().fragmentCount == 0 {
            try await Task.sleep(for: .milliseconds(50))
        }
        await index.vectorsComputed()
        let elapsed = ContinuousClock.now - started

        let load = try await index.fragmentLoad()
        print("10.000 notes, \(load.fragmentCount) fragments: indexed in \(elapsed)")
        #expect(await index.vectorCount == load.fragmentCount)
        #expect(elapsed <= .seconds(180))
    }

    @Test func theModelIsLetGoWhenIdle() async throws {
        let model = TextEmbeddingModel.standard
        let embedder = Embedder(model: model, directory: store.directory(of: model), idleTime: .milliseconds(200))

        _ = try await embedder.vectors(for: ["prova"], as: .query)
        #expect(await embedder.isLoaded)
        try await Task.sleep(for: .seconds(1))

        #expect(await !embedder.isLoaded)
    }
}
