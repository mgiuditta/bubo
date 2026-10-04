import Foundation
import os

/// A line Ricordato, Salvato or Richiamato in a Sessione's flow: the agent wrote in the Memoria di Progetto or in the
/// Secondo cervello, or memories came into its turn (spec 13).
nonisolated struct MemoryLine: Codable, Equatable, Sendable, Identifiable {
    /// What happened to the memory.
    enum Event: Codable, Equatable, Sendable {
        /// Ricordato: the agent wrote a file of the memory with `Write` or `Edit`.
        case remembered(MemoryWrite)
        /// Richiamato: `claude` brought memories into the turn (`memory_recall`).
        case recalled(MemoryRecall)
        /// Richiamato: the agent searched the Indice with `cerca` for `query`, and got `result`.
        case searched(query: String, result: String)
        /// Salvato: the agent wrote a note of the Secondo cervello with `ricorda`.
        case saved(BrainChange)
    }

    var id = UUID()
    let event: Event
    /// When the line came.
    var date = Date.now
    /// Whether Annulla put the file back as it was before the write.
    var isUndone = false

    /// Whether the line is Ricordato.
    var isRemembered: Bool {
        if case .remembered = event { true } else { false }
    }

    /// Whether the line is Salvato.
    var isSaved: Bool {
        if case .saved = event { true } else { false }
    }

    /// Whether Annulla can put the file back: a Ricordato whose write Bubo copied, or a Salvato, not undone yet.
    var canUndo: Bool {
        switch event {
        case let .remembered(write): write.written != nil && !isUndone
        case .saved: !isUndone
        case .recalled, .searched: false
        }
    }

    /// What the line names: the memory written, the memories recalled, or the words searched.
    var subject: String {
        switch event {
        case let .remembered(write):
            write.written.flatMap { ProjectMemory.frontmatter(of: $0)["name"] } ?? write.fileName
        case let .recalled(recall):
            if recall.isSynthesis {
                String(localized: "sintesi dei ricordi")
            } else if recall.memories.count == 1, let memory = recall.memories.first {
                memory.name
            } else {
                String(localized: "\(recall.memories.count) ricordi")
            }
        case let .searched(query, _):
            String(localized: "dall'Indice: «\(query)»")
        case let .saved(change):
            change.link
        }
    }

    /// What Apri shows: the file as it is on disk now, the memories recalled, or the fragments `cerca` found.
    @concurrent static func contents(of line: MemoryLine) async -> String {
        switch line.event {
        case let .remembered(write):
            return read(write.file) ?? String(localized: "Il file non c'è più.")
        case let .recalled(recall):
            return recall.memories.map { memory in
                let text = memory.content ?? read(memory.path) ?? String(localized: "Il file non c'è più.")
                return recall.isSynthesis ? text : "\(memory.name)\n\n\(text)"
            }
            .joined(separator: "\n\n———\n\n")
        case let .searched(_, result):
            return result
        case let .saved(change):
            return read(change.file.path) ?? String(localized: "Il file non c'è più.")
        }
    }

    /// The text of the file at `path`, an absolute path, if it is there and not too large to show.
    private static func read(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        let file = URL(filePath: path)
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576 else { return nil }
        return try? String(contentsOf: file, encoding: .utf8)
    }
}

/// A write of the agent in the Memoria di Progetto, with the file before and after it for Annulla.
nonisolated struct MemoryWrite: Codable, Equatable, Sendable {
    /// The file written, an absolute path.
    let file: String
    /// The file before the write; `nil` when the write created it.
    let previous: String?
    /// The file after the write; `nil` when it was too large to copy, so Annulla is not offered.
    let written: String?

    /// The name of the file, such as `MEMORY.md`.
    var fileName: String { URL(filePath: file).lastPathComponent }

    /// Puts the file back as it was before the write: the previous text, or no file when the write created it.
    ///
    /// Only in `directory`, the memory folder of the Sessione's Progetto, and only if the file still holds what the
    /// agent wrote: a later write, by any Sessione or by the CLI, stays.
    ///
    /// - Throws: ``ProjectMemoryError/outsideMemory`` for a file outside `directory`,
    ///   ``ProjectMemoryError/changedOnDisk`` when the file changed after the write, or a file error.
    @MainActor func undo(in directory: URL) throws {
        guard let written else { return }
        let url = URL(filePath: file)
        guard !fileName.hasPrefix("."),
              TrustGate.realPath(url.deletingLastPathComponent().path) == TrustGate.realPath(directory.path)
        else { throw ProjectMemoryError.outsideMemory }
        try ProjectMemory.write(previous, to: fileName, in: directory, expecting: written)
        Logger.memory.notice("Memory write undone by the user")
    }
}

/// The memories `claude` brought into a turn, as `memory_recall` reports them.
nonisolated struct MemoryRecall: Codable, Equatable, Sendable {
    /// A memory brought into the turn.
    struct Memory: Codable, Equatable, Sendable {
        /// The memory file, an absolute path; a URL for an organization's memory; a placeholder in a synthesis.
        let path: String
        /// `personal`, `team` or `organization`, as `claude` reports it.
        let scope: String
        /// The memory's text, when it has no file on disk to read.
        let content: String?

        /// The name of the memory: its file name, or the address of an organization's memory.
        var name: String {
            path.hasPrefix("/") ? URL(filePath: path).lastPathComponent : path
        }
    }

    /// Whether `claude` wrote one paragraph from many memories (`synthesize`) instead of choosing whole files.
    let isSynthesis: Bool
    let memories: [Memory]
}
