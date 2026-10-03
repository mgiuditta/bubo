import CryptoKit
import Darwin
import Foundation

/// The only writer of the Secondo cervello: it writes only under `Bubo/` at the folder's root, never anywhere else.
///
/// Notes are Markdown with properties Obsidian reads (dates `AAAA-MM-GG`), written atomically, and never replace a
/// file: a name already taken gets a number.
nonisolated struct NoteWriter: Sendable {
    /// Why a note was not written.
    enum Failure: Error, Equatable {
        /// The Secondo cervello cannot be reached: a disk unplugged, a folder deleted, iCloud not available.
        case unreachable
        /// `Bubo/` leads out of the Secondo cervello, through a link.
        case outsideBubo
    }

    /// A note Bubo wrote.
    struct WrittenNote: Equatable, Sendable {
        /// The note's file.
        var file: URL
        /// The SHA-256 of the bytes Bubo wrote, in hexadecimal.
        var hash: String

        /// Whether the file on disk is still the one Bubo wrote: `false` once edited by hand, moved or deleted.
        var isUnchanged: Bool {
            (try? Data(contentsOf: file)).map(NoteWriter.hash(of:)) == hash
        }
    }

    /// Creates a writer for the Secondo cervello at `root`, dating notes with `now` in `timeZone`.
    init(root: URL, timeZone: TimeZone = .current, now: @escaping @Sendable () -> Date = { .now }) {
        self.root = root
        self.timeZone = timeZone
        self.now = now
    }

    private let root: URL
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date

    /// Saves `text` as a new note titled `title` in `Bubo/Note/AAAA-MM-GG Titolo.md`, creating the folders it needs.
    ///
    /// - Throws: `Failure` when the Secondo cervello cannot be reached or `Bubo/` leads out of it; a file system
    ///   error when the note cannot be written.
    func remember(_ text: String, titled title: String) throws -> WrittenNote {
        let date = now()
        let name = Self.fileName(for: title)
        let day = date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
        let data = Data(Self.note(text, titled: name, createdOn: day).utf8)
        return try write(data, named: "\(day) \(name)", in: "Bubo/Note")
    }

    /// Writes the Riassunto di Sessione `body` in `Bubo/Sessioni/AAAA-MM-GG Titolo.md`, with `properties`.
    ///
    /// Without `previous` the note is a new file. With `previous` as Bubo wrote it, the note is replaced in place,
    /// keeping its name and its creation day. With `previous` changed by hand, once or ever, its bytes stay as they
    /// are and `## Aggiornamento AAAA-MM-GG` with `body` goes at its end. With `previous` deleted, nothing is written.
    ///
    /// - Returns: The note as written; `nil` when `previous` was deleted.
    /// - Throws: `Failure` when the Secondo cervello cannot be reached or `Bubo/Sessioni` leads out of it; a file
    ///   system error when the note cannot be written.
    func writeSessionSummary(_ body: String, properties: SummaryProperties,
                             replacing previous: SummaryNote?) throws -> SummaryNote? {
        let day = now().formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let previous else {
            let note = Data((properties.frontmatter(createdOn: day, updatedOn: day) + "\n" + body + "\n").utf8)
            let stem = "\(day) \(Self.fileName(for: properties.title))"
            let written = try write(note, named: stem, in: Self.summaryFolder)
            return SummaryNote(relativePath: "\(Self.summaryFolder)/\(written.file.lastPathComponent)",
                               hash: written.hash, createdOn: day)
        }
        let directory = try folder(Self.summaryFolder)
        let name = (previous.relativePath as NSString).lastPathComponent
        let file = directory.appending(path: name)
        guard let current = try? Data(contentsOf: file) else { return nil }
        let isEditedByHand = previous.isEditedByHand || Self.hash(of: current) != previous.hash
        let note = if isEditedByHand {
            current + Data(((current.last == UInt8(ascii: "\n") ? "" : "\n") + "\n## Aggiornamento \(day)\n\n" + body
                            + "\n").utf8)
        } else {
            Data((properties.frontmatter(createdOn: previous.createdOn, updatedOn: day) + "\n" + body + "\n").utf8)
        }
        let temporary = try temporaryFile(holding: note, in: directory)
        defer { try? FileManager.default.removeItem(at: temporary) }
        // Atomic: the note is either the old one or the new one, never half written.
        guard rename(temporary.path, file.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return SummaryNote(relativePath: "\(Self.summaryFolder)/\(name)", hash: Self.hash(of: note),
                           createdOn: previous.createdOn, isEditedByHand: isEditedByHand)
    }

    /// Writes the Riunione `note` as a new file in `Bubo/Riunioni/AAAA-MM-GG Titolo.md`, dated by its start.
    ///
    /// - Throws: `Failure` when the Secondo cervello cannot be reached or `Bubo/Riunioni` leads out of it; a file
    ///   system error when the note cannot be written.
    func writeMeeting(_ note: MeetingNote) throws -> WrittenNote {
        let day = note.start.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
        return try write(Data(note.markdown(in: timeZone).utf8), named: "\(day) \(Self.fileName(for: note.title))",
                         in: Self.meetingFolder)
    }

    /// Where the Riunioni go: in the Indice, unlike the Riassunti, since they are sources and not Bubo's summaries.
    static let meetingFolder = "Bubo/Riunioni"

    /// Where the Riassunti di Sessione go: excluded from the Indice, since the conversations already are in it.
    static let summaryFolder = "Bubo/Sessioni"

    /// The folder at `path` under `Bubo/`, created if needed.
    ///
    /// - Throws: `Failure.unreachable` when the Secondo cervello is not there; `Failure.outsideBubo` when a link takes
    ///   the folder out of it.
    private func folder(_ path: String) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Failure.unreachable
        }
        let realRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let directory = root.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A link in place of `Bubo/` or of one of its folders would take the note out of the Secondo cervello.
        guard directory.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(realRoot + "/Bubo/") else {
            throw Failure.outsideBubo
        }
        return directory
    }

    /// A hidden file in `directory` holding `data`, so the Indice never reads a note half written.
    private func temporaryFile(holding data: Data, in directory: URL) throws -> URL {
        let temporary = directory.appending(path: ".\(UUID().uuidString).tmp")
        try data.write(to: temporary)
        return temporary
    }

    /// Writes `data` as a new `.md` file named after `stem` in `folder`, a path under `Bubo/`.
    private func write(_ data: Data, named stem: String, in folder: String) throws -> WrittenNote {
        let directory = try self.folder(folder)
        let temporary = try temporaryFile(holding: data, in: directory)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for number in 1...999 {
            let file = directory.appending(path: number == 1 ? "\(stem).md" : "\(stem) \(number).md")
            // Atomic, and refused when the name is taken: a note is never replaced.
            if renamex_np(temporary.path, file.path, UInt32(RENAME_EXCL)) == 0 {
                return WrittenNote(file: file, hash: Self.hash(of: data))
            }
            guard errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        throw POSIXError(.EEXIST)
    }

    /// The characters a file name of the Secondo cervello leaves out: those macOS, Windows or Obsidian links refuse.
    private static let refused = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]").union(.controlCharacters)
        .union(.newlines)

    /// The name `title` gets as a file: without refused characters, without leading dots, at most 80 characters.
    static func fileName(for title: String) -> String {
        let words = title.unicodeScalars.map { refused.contains($0) ? " " : String($0) }.joined()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let name = String(words.drop { $0 == "." || $0 == " " }.prefix(80)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Nota" : name
    }

    /// The note: properties for Obsidian, then `text`.
    static func note(_ text: String, titled title: String, createdOn day: String) -> String {
        """
        ---
        titolo: \(quoted(title))
        creata: \(day)
        fonte: Domanda
        ---

        \(text.trimmingCharacters(in: .whitespacesAndNewlines))

        """
    }

    /// `text` as a YAML string in double quotes.
    private static func quoted(_ text: String) -> String {
        "\"" + text.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"") + "\""
    }

    /// The SHA-256 of `data`, in hexadecimal.
    static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { ($0 < 0x10 ? "0" : "") + String($0, radix: 16) }.joined()
    }

    /// Where the imported documents go: in the Indice, since they are sources and not Bubo's summaries.
    static let documentFolder = "Bubo/Documenti"

    /// Writes the document `note` as a new file in `Bubo/Documenti/Titolo.md`, dated today in its properties.
    ///
    /// - Throws: `Failure` when the Secondo cervello cannot be reached or `Bubo/Documenti` leads out of it; a file
    ///   system error when the note cannot be written.
    func writeDocument(_ note: DocumentNote) throws -> WrittenNote {
        let day = now().formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
        return try write(Data(note.markdown(importedOn: day).utf8), named: Self.fileName(for: note.title),
                         in: Self.documentFolder)
    }

    /// The note of `Bubo/Documenti/` made from the file whose SHA-256 is `fingerprint`; `nil` when there is none.
    func documentNote(withFingerprint fingerprint: String) -> URL? {
        let directory = root.appending(path: Self.documentFolder, directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.first { file in
            file.pathExtension == "md"
                && (try? String(contentsOf: file, encoding: .utf8)).map {
                    DocumentNote.note($0, isOfFileWithFingerprint: fingerprint)
                } == true
        }
    }
}
