import CryptoKit
import Foundation
import os

/// An open embedding model the Indice can download once and then run only on the Mac.
///
/// Its files are fixed in the app, revision and checksum included: a different file on the server is refused.
nonisolated struct TextEmbeddingModel: Hashable, Sendable, Identifiable {
    /// One file of the model as published on Hugging Face.
    struct File: Hashable, Sendable {
        /// The path inside the repository.
        var path: String
        /// The size in bytes.
        var size: Int64
        /// The SHA-256 of the contents, in lowercase hex.
        var sha256: String
    }

    /// The name of the model, also the name of its folder.
    var id: String
    /// The name shown in the settings, as its authors write it.
    var name: String
    /// The Hugging Face repository.
    var repository: String
    /// The commit of the repository the files come from.
    var revision: String
    /// The files the Indice needs, and nothing else.
    var files: [File]
    /// What goes before a search, as the model was trained.
    var queryPrefix: String
    /// What goes before a fragment of a note.
    var passagePrefix: String
    /// The longest input in tokens, special tokens included; longer fragments are cut.
    var maximumTokens: Int

    /// The bytes to download.
    var size: Int64 { files.reduce(0) { $0 + $1.size } }

    /// The name stored with each vector: vectors of another model or revision cannot be compared.
    var signature: String { "\(id)@\(revision)" }

    /// multilingual-e5-small: the default, 384 dimensions, Recall@1 0,83 on the Italian set of the spec.
    static let standard = TextEmbeddingModel(
        id: "multilingual-e5-small", name: "multilingual-e5-small", repository: "intfloat/multilingual-e5-small",
        revision: "614241f622f53c4eeff9890bdc4f31cfecc418b3",
        files: [
            File(path: "config.json", size: 655,
                 sha256: "69137736cab8b8903a07fe8afaafdda25aac55415a12a55d1bffa9f581abf959"),
            File(path: "1_Pooling/config.json", size: 200,
                 sha256: "987f7a67a38fa564c849bb5d277c52ab9088a84368fc0be31a354125aebb12a0"),
            File(path: "tokenizer_config.json", size: 443,
                 sha256: "a1d6bc8734a6f635dc158508bef000f8e2e5a759c7d92f984b2c86e5ff53425b"),
            File(path: "tokenizer.json", size: 17_082_730,
                 sha256: "0b44a9d7b51c3c62626640cda0e2c2f70fdacdc25bbbd68038369d14ebdf4c39"),
            File(path: "model.safetensors", size: 470_641_600,
                 sha256: "1a55775f53449dac10a2bcbc312469fac40b96d53198c407081a831f81c98477"),
        ],
        queryPrefix: "query: ", passagePrefix: "passage: ", maximumTokens: 512)

    /// Qwen3-Embedding-0.6B in 4 bit: the high quality, 1024 dimensions, Recall@1 0,93 on the same set.
    static let highQuality = TextEmbeddingModel(
        id: "qwen3-embedding-0.6b-4bit", name: "Qwen3-Embedding-0.6B", repository: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ",
        revision: "6c3ae70858513f1a78e9cdca3cae330d9075cd2a",
        files: [
            File(path: "config.json", size: 937,
                 sha256: "e7dfa5b73fb2a03cbc8fb40c394e95b99f03348e237f7f28e7a1daf56a2169bb"),
            File(path: "tokenizer_config.json", size: 5404,
                 sha256: "443bfa629eb16387a12edbf92a76f6a6f10b2af3b53d87ba1550adfcf45f7fa0"),
            File(path: "tokenizer.json", size: 11_423_705,
                 sha256: "def76fb086971c7867b829c23a26261e38d9d74e02139253b38aeb9df8b4b50a"),
            File(path: "model.safetensors", size: 335_296_756,
                 sha256: "3d773d5ee582eda445daeee23f7a2b76124011796df244ddb45e22638fdb7cde"),
        ],
        // The default instruction of the model card; the notes go in as they are.
        queryPrefix: "Instruct: Given a web search query, retrieve relevant passages that answer the query\nQuery:", passagePrefix: "",
        maximumTokens: 1024)

    /// Every model the settings offer.
    static let all = [standard, highQuality]

    /// The address of `file` at the fixed revision.
    func url(of file: File) -> URL {
        // Paths and revisions are constants of the app, never user input.
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(file.path)")!
    }
}

/// The embedding models on this Mac, in `Application Support/Bubo/Modelli`.
///
/// A model counts as installed only after every file was checked against its size and checksum.
nonisolated struct TextEmbeddingModelStore: Sendable {
    /// The folder holding one subfolder per model and revision.
    var folder: URL

    /// The store in Application Support.
    static func makeDefault() throws -> TextEmbeddingModelStore {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return TextEmbeddingModelStore(folder: support.appending(path: "Bubo/Modelli"))
    }

    /// The folder of `model`, whether installed or not.
    func directory(of model: TextEmbeddingModel) -> URL {
        folder.appending(path: model.id).appending(path: model.revision)
    }

    /// Whether `model` was downloaded and checked.
    func isInstalled(_ model: TextEmbeddingModel) -> Bool {
        FileManager.default.fileExists(atPath: marker(of: model).path)
    }

    /// Downloads the files of `model` still missing, checks each one, and marks the model installed.
    ///
    /// Only the files of the model leave the network for the Mac; nothing of the user's goes the other way.
    /// - Parameter configuration: The session's configuration; by default no cookies, no cache, no credentials,
    ///   as the files are public.
    /// - Parameter progress: Called with the bytes received so far, out of ``TextEmbeddingModel/size``.
    /// - Throws: ``TextEmbeddingModelError`` when a file is not the expected one, or the network error.
    @concurrent
    func install(_ model: TextEmbeddingModel, configuration: URLSessionConfiguration = .ephemeral,
                 progress: @escaping @Sendable (Int64) -> Void) async throws {
        let directory = directory(of: model)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var done: Int64 = 0
        for file in model.files {
            let destination = directory.appending(path: file.path)
            if !Self.matches(destination, file) {
                let base = done
                let tracker = DownloadProgress { progress(base + $0) }
                let (temporary, response) = try await session.download(from: model.url(of: file), delegate: tracker)
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw TextEmbeddingModelError.unavailable(file: file.path)
                }
                guard Self.matches(temporary, file) else { throw TextEmbeddingModelError.corrupted(file: file.path) }
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            done += file.size
            progress(done)
        }
        try Data().write(to: marker(of: model))
        Logger.index.notice("Embedding model \(model.id, privacy: .public) installed")
    }

    /// Deletes every model but `kept`.
    func removeAll(except kept: TextEmbeddingModel) {
        let others = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in others where name != kept.id {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
    }

    private func marker(of model: TextEmbeddingModel) -> URL {
        directory(of: model).appending(path: ".verificato")
    }

    /// Whether the file at `url` has the size and checksum of `file`.
    private static func matches(_ url: URL, _ file: TextEmbeddingModel.File) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attributes[.size] as? NSNumber)?.int64Value == file.size,
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined() == file.sha256
    }
}

/// Errors while installing an embedding model.
nonisolated enum TextEmbeddingModelError: Error, Equatable {
    /// The server did not hand out the file.
    case unavailable(file: String)
    /// The file arrived with another size or checksum than the one fixed in the app.
    case corrupted(file: String)
}

/// Reports the bytes written by one download.
private nonisolated final class DownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    init(_ report: @escaping @Sendable (Int64) -> Void) {
        self.report = report
    }

    private let report: @Sendable (Int64) -> Void

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        report(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The async `download(from:delegate:)` hands the file back itself.
    }
}
