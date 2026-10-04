import Darwin
import Foundation
import os

/// A write of Bubo in the Secondo cervello, kept in the ``BrainJournal`` with the note as it was before, for Annulla.
nonisolated struct BrainChange: Codable, Equatable, Sendable, Identifiable {
    /// Why Annulla did not put the note back.
    enum UndoFailure: Error, Equatable {
        /// The note changed after the write: putting it back would lose what came later.
        case changedOnDisk
    }

    var id = UUID()
    /// When Bubo wrote.
    var date = Date.now
    /// The note written.
    let file: URL
    /// The note before the write; `nil` when the write created it.
    let previous: Data?
    /// The SHA-256 of the note as Bubo wrote it, in hexadecimal.
    let hash: String
    /// Whether Annulla already put the note back.
    var isUndone = false

    /// The note's name as Obsidian links it, without `.md`.
    var noteName: String { file.deletingPathExtension().lastPathComponent }

    /// The note as an Obsidian link, such as `[[Profilo]]`.
    var link: String { "[[\(noteName)]]" }

    /// Puts the note back as it was before the write: the previous text, or no note when the write created it.
    ///
    /// - Throws: ``UndoFailure/changedOnDisk`` when the note is no longer the one Bubo wrote, or became a link; a file
    ///   system error.
    func undo() throws {
        // Restored through a link, the note would land wherever the link points.
        guard !NoteWriter.isLink(file), (try? Data(contentsOf: file)).map(NoteWriter.hash(of:)) == hash else { throw UndoFailure.changedOnDisk }
        if let previous {
            let temporary = file.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).tmp")
            try previous.write(to: temporary)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard rename(temporary.path, file.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } else {
            try FileManager.default.removeItem(at: file)
        }
        Logger.index.notice("Write in the Secondo cervello undone by the user")
    }
}
