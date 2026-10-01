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

    /// Writes `data` as a new `.md` file named after `stem` in `folder`, a path under `Bubo/`.
    private func write(_ data: Data, named stem: String, in folder: String) throws -> WrittenNote {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Failure.unreachable
        }
        let realRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let directory = root.appending(path: folder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A link in place of `Bubo/` or of one of its folders would take the note out of the Secondo cervello.
        guard directory.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(realRoot + "/Bubo/") else {
            throw Failure.outsideBubo
        }
        // Hidden, so the Indice never reads it half written.
        let temporary = directory.appending(path: ".\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary)
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
}
