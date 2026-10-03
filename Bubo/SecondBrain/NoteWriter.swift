import CryptoKit
import Darwin
import Foundation

/// The only writer of the Secondo cervello: it creates notes only under `Bubo/` at the folder's root; outside it, it
/// only adds to a note of the user's, or rewrites one the user confirmed, for `ricorda`.
///
/// Notes are Markdown with properties Obsidian reads (dates `AAAA-MM-GG`), written atomically, and new ones never
/// replace a file: a name already taken gets a number.
nonisolated struct NoteWriter: Sendable {
    /// Why a note was not written.
    enum Failure: Error, Equatable {
        /// The Secondo cervello cannot be reached: a disk unplugged, a folder deleted, iCloud not available.
        case unreachable
        /// `Bubo/` leads out of the Secondo cervello, through a link.
        case outsideBubo
        /// The note asked for is not a Markdown note inside the Secondo cervello, or is hidden.
        case outsideSecondBrain
        /// The note to add to, outside `Bubo/`, does not exist.
        case notFound
        /// Changing a note of the user's, or the Profilo, needs their confirmation first.
        case needsConfirmation
        /// The Regole and the Intervista are written only by the user: never by `ricorda`.
        case protectedNote
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

    /// Adds `text` at the end of the note at `relativePath`, after a blank line; a note under `Bubo/` that is not
    /// there yet is created. The Profilo changes only when `isConfirmed`.
    ///
    /// - Returns: The write, with the note as it was before.
    /// - Throws: `Failure` when the Secondo cervello cannot be reached, the note is outside it or protected, the
    ///   Profilo is not confirmed, or a note outside `Bubo/` is not there; a file system error.
    func append(_ text: String, to relativePath: String, isConfirmed: Bool = false) throws -> BrainChange {
        let (file, isBubo) = try note(at: relativePath)
        guard !Self.isProfile(relativePath) || isConfirmed else { throw Failure.needsConfirmation }
        let previous = try? Data(contentsOf: file)
        guard previous != nil || isBubo else { throw Failure.notFound }
        let current = previous ?? Data()
        let separator = current.isEmpty ? "" : current.last == UInt8(ascii: "\n") ? "\n" : "\n\n"
        return try replace(file, previous: previous,
                           with: current + Data((separator + text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n").utf8))
    }

    /// Replaces the whole note at `relativePath` with `text`, creating it under `Bubo/` when it is not there.
    ///
    /// A note outside `Bubo/` is the user's, and the Profilo comes into every turn: they are rewritten only when
    /// `isConfirmed`.
    ///
    /// - Returns: The write, with the note as it was before.
    /// - Throws: `Failure.needsConfirmation` for a note of the user's or the Profilo not confirmed; another `Failure`
    ///   when the Secondo cervello cannot be reached, the note is outside it, protected, or not there; a file system
    ///   error.
    func rewrite(_ relativePath: String, with text: String, isConfirmed: Bool) throws -> BrainChange {
        let (file, isBubo) = try note(at: relativePath)
        guard isBubo && !Self.isProfile(relativePath) || isConfirmed else { throw Failure.needsConfirmation }
        let previous = try? Data(contentsOf: file)
        guard previous != nil || isBubo else { throw Failure.notFound }
        return try replace(file, previous: previous,
                           with: Data((text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n").utf8))
    }

    /// The Markdown note at `relativePath` inside the Secondo cervello, and whether it is under `Bubo/`.
    private func note(at relativePath: String) throws -> (file: URL, isBubo: Bool) {
        let components = relativePath.split(separator: "/").map(String.init)
        guard let name = components.last, name.lowercased().hasSuffix(".md"), name.count > 3,
              !components.contains(where: { $0.hasPrefix(".") })
        else { throw Failure.outsideSecondBrain }
        if components.count > 1, components[0].lowercased() == "bubo" {
            let path = components.joined(separator: "/").lowercased()
            guard path != Self.rulesPath.lowercased(), path != Self.interviewPath.lowercased() else {
                throw Failure.protectedNote
            }
            // The one note at the root of `Bubo/` `ricorda` writes, only once the user confirms, through the same checks
            // as the setup's; every other note goes in a folder under `Bubo/`.
            if path == Self.profilePath.lowercased() {
                guard FileManager.default.fileExists(atPath: root.path),
                      let file = Self.setupFile(Self.profilePath, in: root) else { throw Failure.outsideBubo }
                try FileManager.default.createDirectory(at: root.appending(path: "Bubo"), withIntermediateDirectories: true)
                return (file, true)
            }
            let file = try folder(components.dropLast().joined(separator: "/")).appending(path: name)
            // Written through a link, the note would land wherever the link points.
            guard !Self.isLink(file) else { throw Failure.outsideSecondBrain }
            return (file, true)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Failure.unreachable
        }
        let file = root.appending(path: components.joined(separator: "/"))
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory) else { throw Failure.notFound }
        guard !isDirectory.boolValue, !Self.isLink(file) else { throw Failure.outsideSecondBrain }
        // A link among the folders could take the note out of the Secondo cervello, or into `Bubo/` under another name.
        let realRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let realFile = file.resolvingSymlinksInPath().standardizedFileURL.path
        guard realFile.hasPrefix(realRoot + "/"), !realFile.lowercased().hasPrefix((realRoot + "/Bubo/").lowercased()) else {
            throw Failure.outsideSecondBrain
        }
        return (file, false)
    }

    /// Whether `relativePath` names the Profilo.
    private static func isProfile(_ relativePath: String) -> Bool {
        relativePath.split(separator: "/").joined(separator: "/").lowercased() == profilePath.lowercased()
    }

    /// Whether `file` is a symbolic link, without following it.
    static func isLink(_ file: URL) -> Bool {
        var status = stat()
        return lstat(file.path, &status) == 0 && status.st_mode & S_IFMT == S_IFLNK
    }

    /// Replaces `file`, which held `previous`, with `data` atomically.
    private func replace(_ file: URL, previous: Data?, with data: Data) throws -> BrainChange {
        let temporary = try temporaryFile(holding: data, in: file.deletingLastPathComponent())
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard rename(temporary.path, file.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return BrainChange(file: file, previous: previous, hash: Self.hash(of: data))
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

    /// Who the user is, agreed in the interview of the Secondo cervello: every chat reads it.
    static let profilePath = "Bubo/Profilo.md"
    /// How Bubo keeps the Secondo cervello, agreed in the interview: what goes where, what it saves on its own.
    static let rulesPath = "Bubo/Regole.md"
    /// The user's own prompt for the interview, in place of Bubo's method when it is there.
    static let interviewPath = "Bubo/Intervista.md"

    /// Writes `profile` in `Bubo/Profilo.md` and `rules` in `Bubo/Regole.md`, each atomically and replacing the file;
    /// an empty text leaves its file as it is.
    ///
    /// - Throws: `Failure` when the Secondo cervello cannot be reached or `Bubo/` leads out of it; a file system
    ///   error when a file cannot be written.
    func writeSetup(profile: String, rules: String) throws {
        // Only here, after the user's yes, are the Profilo and the Regole written: every other write goes in a folder
        // under `Bubo/`, and `Bubo/Intervista.md` is the user's alone.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Failure.unreachable
        }
        guard Self.setupFile(Self.profilePath, in: root) != nil else { throw Failure.outsideBubo }
        try FileManager.default.createDirectory(at: root.appending(path: "Bubo"), withIntermediateDirectories: true)
        for (text, path) in [(profile, Self.profilePath), (rules, Self.rulesPath)] {
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            guard let file = Self.setupFile(path, in: root) else { throw Failure.outsideBubo }
            try Data((text + "\n").utf8).write(to: file, options: .atomic)
        }
    }

    /// The most a file of the setup is read: a vault could hold anything under its name.
    static let setupReadLimit = 64 * 1024

    /// The text of the setup file at `path` under `Bubo/` in `root`: `nil` when it is missing, not a regular file, a
    /// link, larger than ``setupReadLimit``, or `Bubo/` leads out of `root`.
    static func setupText(_ path: String, in root: URL) -> String? {
        guard let file = setupFile(path, in: root) else { return nil }
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, Int(info.st_size) <= setupReadLimit,
              let data = try? handle.read(upToCount: setupReadLimit)
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// The setup file at `path` under `Bubo/` in `root`, the only place it is read or written from: `nil` when `Bubo/`
    /// is a link or leads out of `root`, or the file is there as anything but a regular file, such as a link.
    private static func setupFile(_ path: String, in root: URL) -> URL? {
        let bubo = root.appending(path: "Bubo", directoryHint: .isDirectory)
        let realBubo = root.resolvingSymlinksInPath().standardizedFileURL.path + "/Bubo"
        var info = stat()
        guard bubo.resolvingSymlinksInPath().standardizedFileURL.path == realBubo,
              lstat(bubo.path, &info) == 0 ? info.st_mode & S_IFMT == S_IFDIR : errno == ENOENT
        else { return nil }
        let file = bubo.appending(path: (path as NSString).lastPathComponent)
        guard lstat(file.path, &info) == 0 else { return errno == ENOENT ? file : nil }
        return info.st_mode & S_IFMT == S_IFREG ? file : nil
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
