import CoreServices
import Foundation
import os
import SQLite3

/// Where a file of the Indice comes from; the raw value is the `fonte` of the `cerca` tool.
nonisolated enum SearchSource: String, Sendable {
    /// The Memoria di Progetto of every Progetto and the user's CLAUDE.md.
    case memory = "memoria"
    /// The Secondo cervello, the user's folder of notes.
    case secondBrain = "secondo-cervello"
}

/// A fragment of a file in the Indice that matches a search.
nonisolated struct SearchHit: Equatable, Sendable {
    /// The file the fragment comes from.
    var path: String
    /// The Progetto whose memory holds the file, as `~/.claude/projects` names it; `nil` for the user's CLAUDE.md
    /// and for the Secondo cervello.
    var project: String?
    /// Where the file comes from.
    var source: SearchSource = .memory
    /// The fragment: one Markdown section of the file.
    var text: String
}

/// The Indice: a rebuildable SQLite copy of the Memoria di Progetto of every Progetto, of the
/// user's CLAUDE.md and of the Secondo cervello, searched by words with FTS5.
///
/// It never holds the code of a Progetto. Deleting its file loses nothing: the next start rebuilds it.
/// The Secondo cervello is the user's own, untrusted text: it is only read, never run, and leaves the Mac
/// only as the answer to a `cerca` call.
actor SearchIndex {
    /// Opens the Indice at `database`, copying the memory found under `root`, the `~/.claude` folder.
    init(database: URL, root: URL) throws {
        // FSEvents reports real paths: `~/.claude` may be a link, and `resolvingSymlinksInPath` keeps `/var` for `/private/var`.
        // A named argument: Xcode 26.6 rejects `$0` inside `defer`.
        self.root = Self.realPath(root.path)
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var connection: OpaquePointer?
        guard sqlite3_open(database.path, &connection) == SQLITE_OK, let connection else {
            sqlite3_close(connection)
            throw SearchIndexError.unopenable(path: database.path)
        }
        self.connection = connection
        // A cache: a different layout is dropped and rebuilt, never migrated.
        if try Self.integer("PRAGMA user_version", in: connection) != Self.layoutVersion {
            try Self.execute("""
                DROP TABLE IF EXISTS documents; DROP TABLE IF EXISTS fragments; DROP TABLE IF EXISTS state;
                CREATE TABLE documents(path TEXT PRIMARY KEY, source TEXT NOT NULL, size INTEGER NOT NULL,
                                       modified REAL NOT NULL);
                CREATE VIRTUAL TABLE fragments USING fts5(text, path UNINDEXED, project UNINDEXED, source UNINDEXED,
                                                          tokenize = 'unicode61 remove_diacritics 2');
                CREATE TABLE state(key TEXT PRIMARY KEY, value) WITHOUT ROWID;
                PRAGMA user_version = \(Self.layoutVersion);
                """, in: connection)
        }
    }

    /// The Indice in Application Support, over the user's `~/.claude`.
    static func makeDefault() throws -> SearchIndex {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return try SearchIndex(database: support.appending(path: "Bubo/Indice/indice.sqlite"),
                               root: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude"))
    }

    isolated deinit {
        sqlite3_close(connection)
    }

    private static let layoutVersion = 2
    /// The real path of the `~/.claude` folder.
    private let root: String
    private let connection: OpaquePointer
    /// The folder of the Secondo cervello being followed, as the user chose it; `nil` without one.
    private var secondBrain: String?

    // MARK: Searching

    /// Returns up to `limit` fragments matching the words of `text`, best first.
    ///
    /// - Parameter project: A Progetto's folder; when given, only its memory is searched.
    /// - Parameter source: When given, only the files from there are searched.
    func hits(for text: String, project: String? = nil, source: SearchSource? = nil, limit: Int = 8) throws -> [SearchHit] {
        let words = text.split { !$0.isLetter && !$0.isNumber }
        guard !words.isEmpty else { return [] }
        // Every word quoted, so nothing the user types is FTS5 syntax; a prefix match, so "notar" finds "notarizzazione".
        let match = words.map { "\"\($0)\"*" }.joined(separator: " OR ")
        let statement = try prepare("""
            SELECT path, project, source, text FROM fragments WHERE fragments MATCH ?1
            \(project == nil ? "" : "AND project = ?3") \(source == nil ? "" : "AND source = ?4") ORDER BY rank LIMIT ?2
            """)
        defer { sqlite3_finalize(statement) }
        bind(match, at: 1, in: statement)
        sqlite3_bind_int(statement, 2, Int32(limit))
        if let project { bind(Self.projectName(ofFolder: project), at: 3, in: statement) }
        if let source { bind(source.rawValue, at: 4, in: statement) }
        var hits: [SearchHit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            hits.append(SearchHit(path: column(0, of: statement) ?? "", project: column(1, of: statement),
                                  source: column(2, of: statement).flatMap(SearchSource.init(rawValue:)) ?? .memory,
                                  text: column(3, of: statement) ?? ""))
        }
        return hits
    }

    /// Returns the answer to the `cerca` tool: the matching fragments, each under its file.
    ///
    /// When the Secondo cervello is searched but its folder cannot be reached, the answer says the notes are its last copy.
    func toolResult(for text: String, project: String?, source: SearchSource? = nil) -> String {
        let notice = source != .memory && project == nil && !isSecondBrainReachable
            ? "La cartella del Secondo cervello non è raggiungibile: le note sono quelle dell'ultima lettura.\n\n" : ""
        do {
            let hits = try hits(for: text, project: project, source: source)
            guard !hits.isEmpty else { return notice + "Nessun risultato nell'Indice." }
            return notice + hits.map { "### \($0.path)\n\n\($0.text)" }.joined(separator: "\n\n---\n\n")
        } catch {
            Logger.index.error("Search failed: \(error)")
            return "L'Indice non ha potuto cercare."
        }
    }

    /// Whether the folder of the Secondo cervello can be read now; `true` without one.
    private var isSecondBrainReachable: Bool {
        secondBrain.map(Self.isFolder) ?? true
    }

    /// The name `~/.claude/projects` gives the memory of the Progetto at `folder`.
    nonisolated static func projectName(ofFolder folder: String) -> String {
        String(folder.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    // MARK: Staying fresh

    /// Keeps the memory in the Indice in step with the disk while Bubo runs; never returns until cancelled.
    ///
    /// Resumes from the last file event it handled, so changes made with Bubo closed are not lost;
    /// without that point, or when FSEvents lost events, it rescans everything.
    func keepFresh() async {
        await follow(root, as: .memory) { batch in
            if batch.needsRescan || batch.paths.contains(where: isMemory) {
                rescan()
            }
            return true
        }
    }

    /// Follows the Secondo cervello at `folder` like ``keepFresh()``, until cancelled; `nil` forgets the one followed.
    ///
    /// Another folder than the last one replaces its notes. While the folder cannot be reached, as a disk
    /// unplugged, the Indice keeps the last copy of its notes and catches up when it comes back.
    func keepSecondBrainFresh(at folder: URL?) async {
        // Replaced before it even started: the newer call has the newer folder.
        guard !Task.isCancelled else { return }
        let chosen = folder?.standardizedFileURL.path
        if chosen != state("secondBrain") {
            do {
                try transaction {
                    try forgetAll(from: .secondBrain)
                    try setState("secondBrain", to: chosen)
                    try setState(SearchSource.secondBrain.rawValue + ".eventID", to: nil)
                }
            } catch {
                Logger.index.error("Could not replace the Secondo cervello: \(error)")
            }
        }
        secondBrain = chosen
        guard let chosen else { return }
        // FSEvents reports real paths, and a missing folder has none yet: worked out again at every batch.
        await follow(Self.realPath(chosen), as: .secondBrain) { batch in
            // A stream left over from a folder since replaced: it must not touch the new one's notes or resume point.
            guard secondBrain == chosen else { return false }
            let folder = Self.realPath(chosen)
            if batch.needsRescan || batch.paths.contains(folder) {
                rescanSecondBrain()
            } else {
                refreshSecondBrain(at: Set(batch.paths).filter { $0.hasPrefix(folder + "/") }, in: folder)
            }
            return true
        }
    }

    /// Runs `handle` on every batch of file events under `folder`, from where the last run for `source` stopped,
    /// until it returns `false`.
    private func follow(_ folder: String, as source: SearchSource, handle: (FileEventBatch) -> Bool) async {
        let volume = Self.volumeID(of: folder)
        let since: FSEventStreamEventId
        if let saved = resumePoint(of: source), saved.volume == volume {
            since = saved.eventID
        } else {
            since = FSEventsGetCurrentEventId()
            switch source {
            case .memory: rescan()
            case .secondBrain: rescanSecondBrain()
            }
            saveResumePoint(of: source, eventID: since, volume: volume)
        }
        for await batch in FileEvents.batches(under: folder, since: since) {
            guard handle(batch) else { return }
            saveResumePoint(of: source, eventID: batch.latestID, volume: volume)
        }
    }

    /// Brings every memory file up to date and forgets the deleted ones.
    // ponytail: a full stat pass per change, fine for memory folders; the Secondo cervello refreshes per path.
    func rescan() {
        do {
            try transaction {
                try update(source: .memory, known: try documents(from: .memory, under: nil), onDisk: memoryFiles())
            }
        } catch {
            Logger.index.error("Rescan failed: \(error)")
        }
    }

    /// Brings every note of the Secondo cervello up to date and forgets the deleted ones; with the folder
    /// out of reach, keeps them all.
    func rescanSecondBrain() {
        guard let secondBrain else { return }
        let folder = Self.realPath(secondBrain)
        refreshSecondBrain(at: [folder], in: folder)
    }

    /// Brings the notes at or under each of `paths`, inside the Secondo cervello at `folder`, up to date.
    private func refreshSecondBrain(at paths: Set<String>, in folder: String) {
        guard Self.isFolder(folder) else {
            Logger.index.notice("Secondo cervello out of reach: keeping the last copy")
            return
        }
        do {
            try transaction {
                for path in paths {
                    let relative = path == folder ? "" : String(path.dropFirst(folder.count + 1))
                    guard !SecondBrainNotes.skips(relative) else { continue }
                    let found = SecondBrainNotes.files(at: path, in: folder)
                    let known = try documents(from: .secondBrain, under: path).filter { !found.kept.contains($0.key) }
                    try update(source: .secondBrain, known: known, onDisk: found.notes)
                }
            }
        } catch {
            Logger.index.error("Secondo cervello refresh failed: \(error)")
        }
    }

    /// Stores the files of `source` that changed from `known` to `onDisk` and forgets the ones gone.
    private func update(source: SearchSource, known: [String: FileStamp], onDisk: [String: FileStamp]) throws {
        for path in known.keys where onDisk[path] == nil {
            try forget(path)
        }
        for (path, file) in onDisk where known[path] != file {
            try forget(path)
            try store(path, from: source, stamp: file)
        }
    }

    /// The files of `source` in the Indice, at or under `path` when given.
    private func documents(from source: SearchSource, under path: String?) throws -> [String: FileStamp] {
        let statement = try prepare("""
            SELECT path, size, modified FROM documents WHERE source = ?1
            \(path == nil ? "" : "AND (path = ?2 OR substr(path, 1, length(?2) + 1) = ?2 || '/')")
            """)
        defer { sqlite3_finalize(statement) }
        bind(source.rawValue, at: 1, in: statement)
        if let path { bind(path, at: 2, in: statement) }
        var known: [String: FileStamp] = [:]
        while sqlite3_step(statement) == SQLITE_ROW, let path = column(0, of: statement) {
            known[path] = FileStamp(size: Int(sqlite3_column_int64(statement, 1)), modified: sqlite3_column_double(statement, 2))
        }
        return known
    }

    /// Whether `path` is, holds, or may hold a memory file: the user's CLAUDE.md, a Progetto's
    /// folder, or anything in its `memory` folder.
    private func isMemory(_ path: String) -> Bool {
        if path == root + "/CLAUDE.md" { return true }
        guard path.hasPrefix(root + "/projects") else { return false }
        let inside = path.dropFirst(root.count + "/projects".count).split(separator: "/")
        return inside.count <= 1 || inside[1] == "memory"
    }

    /// The memory files on disk, with their size and modification time.
    private func memoryFiles() -> [String: FileStamp] {
        let manager = FileManager.default
        var paths = [root + "/CLAUDE.md"]
        let projects = URL(filePath: root).appending(path: "projects")
        for project in (try? manager.contentsOfDirectory(atPath: projects.path)) ?? [] {
            let memory = projects.appending(path: project).appending(path: "memory")
            guard let files = manager.enumerator(atPath: memory.path) else { continue }
            for case let file as String in files where file.hasSuffix(".md") {
                paths.append(memory.appending(path: file).path)
            }
        }
        var found: [String: FileStamp] = [:]
        for path in paths {
            guard let stamp = FileStamp(ofFileAt: path) else { continue }
            found[path] = stamp
        }
        return found
    }

    private func store(_ path: String, from source: SearchSource, stamp: FileStamp) throws {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let project = source == .memory && path.hasPrefix(root + "/projects/")
            ? String(path.dropFirst(root.count + "/projects/".count).prefix { $0 != "/" }) : nil
        let insert = try prepare("INSERT INTO fragments(text, path, project, source) VALUES (?1, ?2, ?3, ?4)")
        defer { sqlite3_finalize(insert) }
        for fragment in MarkdownFragments.split(contents) {
            sqlite3_reset(insert)
            bind(fragment, at: 1, in: insert)
            bind(path, at: 2, in: insert)
            if let project { bind(project, at: 3, in: insert) } else { sqlite3_bind_null(insert, 3) }
            bind(source.rawValue, at: 4, in: insert)
            guard sqlite3_step(insert) == SQLITE_DONE else { throw lastError() }
        }
        let document = try prepare("INSERT INTO documents(path, source, size, modified) VALUES (?1, ?2, ?3, ?4)")
        defer { sqlite3_finalize(document) }
        bind(path, at: 1, in: document)
        bind(source.rawValue, at: 2, in: document)
        sqlite3_bind_int64(document, 3, Int64(stamp.size))
        sqlite3_bind_double(document, 4, stamp.modified)
        guard sqlite3_step(document) == SQLITE_DONE else { throw lastError() }
    }

    private func forget(_ path: String) throws {
        for sql in ["DELETE FROM fragments WHERE path = ?1", "DELETE FROM documents WHERE path = ?1"] {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            bind(path, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        }
    }

    private func forgetAll(from source: SearchSource) throws {
        for sql in ["DELETE FROM fragments WHERE source = ?1", "DELETE FROM documents WHERE source = ?1"] {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            bind(source.rawValue, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        }
    }

    private func resumePoint(of source: SearchSource) -> (eventID: FSEventStreamEventId, volume: String)? {
        guard let eventID = state(source.rawValue + ".eventID").flatMap(UInt64.init),
              let volume = state(source.rawValue + ".volume") else { return nil }
        return (eventID, volume)
    }

    private func saveResumePoint(of source: SearchSource, eventID: FSEventStreamEventId, volume: String) {
        do {
            try setState(source.rawValue + ".eventID", to: String(eventID))
            try setState(source.rawValue + ".volume", to: volume)
        } catch {
            Logger.index.error("Could not save the resume point: \(error)")
        }
    }

    private func state(_ key: String) -> String? {
        guard let statement = try? prepare("SELECT value FROM state WHERE key = ?1") else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(key, at: 1, in: statement)
        return sqlite3_step(statement) == SQLITE_ROW ? column(0, of: statement) : nil
    }

    /// Saves `value` under `key`; `nil` removes it.
    private func setState(_ key: String, to value: String?) throws {
        let statement = try prepare(value == nil ? "DELETE FROM state WHERE key = ?1"
                                                 : "INSERT OR REPLACE INTO state(key, value) VALUES (?1, ?2)")
        defer { sqlite3_finalize(statement) }
        bind(key, at: 1, in: statement)
        if let value { bind(value, at: 2, in: statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    /// The FSEvents identity of the volume holding `path`, or of the home folder while `path` does not exist.
    private static func volumeID(of path: String) -> String {
        var info = stat()
        guard stat(path, &info) == 0 || stat(NSHomeDirectory(), &info) == 0,
              let uuid = FSEventsCopyUUIDForDevice(info.st_dev) else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// The path FSEvents reports for `path`: links resolved, `/private/var` for `/var`; `path` itself while missing.
    private static func realPath(_ path: String) -> String {
        // A named argument: Xcode 26.6 rejects `$0` inside `defer`.
        realpath(path, nil).map { resolved in
            defer { free(resolved) }
            return String(cString: resolved)
        } ?? path
    }

    private static func isFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    // MARK: SQLite

    /// Runs `body` in one transaction, rolled back when it throws.
    private func transaction(_ body: () throws -> Void) throws {
        try Self.execute("BEGIN", in: connection)
        do {
            try body()
            try Self.execute("COMMIT", in: connection)
        } catch {
            try? Self.execute("ROLLBACK", in: connection)
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw lastError() }
        return statement
    }

    private func bind(_ text: String, at index: Int32, in statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func column(_ index: Int32, of statement: OpaquePointer) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }

    private func lastError() -> SearchIndexError {
        .failed(message: String(cString: sqlite3_errmsg(connection)))
    }

    private static func execute(_ sql: String, in connection: OpaquePointer) throws {
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
            throw SearchIndexError.failed(message: String(cString: sqlite3_errmsg(connection)))
        }
    }

    private static func integer(_ sql: String, in connection: OpaquePointer) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SearchIndexError.failed(message: String(cString: sqlite3_errmsg(connection)))
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
    }
}

/// Errors from the Indice's database.
nonisolated enum SearchIndexError: Error, Equatable {
    /// The database file could not be opened or created.
    case unopenable(path: String)
    /// SQLite refused a statement with this message.
    case failed(message: String)
}

/// Splits Markdown into the fragments the Indice stores: one per section, its heading included.
nonisolated enum MarkdownFragments {
    /// Returns the non-empty sections of `markdown`, each starting at a heading or at the top.
    // ponytail: no size cap; vectors (#112) need ≤ 512 tokens and will cut long sections.
    static func split(_ markdown: String) -> [String] {
        var fragments: [String] = []
        var current: [Substring] = []
        var inCode = false
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("```") { inCode.toggle() }
            if !inCode, line.hasPrefix("#"), line.drop(while: { $0 == "#" }).first == " " {
                fragments.append(current.joined(separator: "\n"))
                current = []
            }
            current.append(line)
        }
        fragments.append(current.joined(separator: "\n"))
        return fragments.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

extension Logger {
    nonisolated static let index = Logger(subsystem: "com.mgiuditta.bubo", category: "index")
}
