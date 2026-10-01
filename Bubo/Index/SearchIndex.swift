import CoreServices
import Foundation
import os
import SQLite3

/// A fragment of a file in the Indice that matches a search.
nonisolated struct SearchHit: Equatable, Sendable {
    /// The file the fragment comes from.
    var path: String
    /// The Progetto whose memory holds the file, as `~/.claude/projects` names it; `nil` for the user's CLAUDE.md.
    var project: String?
    /// The fragment: one Markdown section of the file.
    var text: String
}

/// The Indice: a rebuildable SQLite copy of the Memoria di Progetto of every Progetto and of the
/// user's CLAUDE.md, searched by words with FTS5.
///
/// It never holds the code of a Progetto. Deleting its file loses nothing: the next start rebuilds it.
actor SearchIndex {
    /// Opens the Indice at `database`, copying the memory found under `root`, the `~/.claude` folder.
    init(database: URL, root: URL) throws {
        // FSEvents reports real paths: `~/.claude` may be a link, and `resolvingSymlinksInPath` keeps `/var` for `/private/var`.
        self.root = realpath(root.path, nil).map { defer { free($0) }; return String(cString: $0) } ?? root.path
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
                CREATE TABLE documents(path TEXT PRIMARY KEY, size INTEGER NOT NULL, modified REAL NOT NULL);
                CREATE VIRTUAL TABLE fragments USING fts5(text, path UNINDEXED, project UNINDEXED,
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

    private static let layoutVersion = 1
    private let root: String
    private let connection: OpaquePointer

    // MARK: Searching

    /// Returns up to `limit` fragments matching the words of `text`, best first.
    ///
    /// - Parameter project: A Progetto's folder; when given, only its memory is searched.
    func hits(for text: String, project: String? = nil, limit: Int = 8) throws -> [SearchHit] {
        let words = text.split { !$0.isLetter && !$0.isNumber }
        guard !words.isEmpty else { return [] }
        // Every word quoted, so nothing the user types is FTS5 syntax; a prefix match, so "notar" finds "notarizzazione".
        let match = words.map { "\"\($0)\"*" }.joined(separator: " OR ")
        let filter = project == nil ? "" : "AND project = ?3"
        let statement = try prepare("""
            SELECT path, project, text FROM fragments WHERE fragments MATCH ?1 \(filter) ORDER BY rank LIMIT ?2
            """)
        defer { sqlite3_finalize(statement) }
        bind(match, at: 1, in: statement)
        sqlite3_bind_int(statement, 2, Int32(limit))
        if let project { bind(Self.projectName(ofFolder: project), at: 3, in: statement) }
        var hits: [SearchHit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            hits.append(SearchHit(path: column(0, of: statement) ?? "", project: column(1, of: statement),
                                  text: column(2, of: statement) ?? ""))
        }
        return hits
    }

    /// Returns the answer to the `cerca` tool: the matching fragments, each under its file.
    func toolResult(for text: String, project: String?) -> String {
        do {
            let hits = try hits(for: text, project: project)
            guard !hits.isEmpty else { return "Nessun risultato nell'Indice." }
            return hits.map { "### \($0.path)\n\n\($0.text)" }.joined(separator: "\n\n---\n\n")
        } catch {
            Logger.index.error("Search failed: \(error)")
            return "L'Indice non ha potuto cercare."
        }
    }

    /// The name `~/.claude/projects` gives the memory of the Progetto at `folder`.
    nonisolated static func projectName(ofFolder folder: String) -> String {
        String(folder.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    // MARK: Staying fresh

    /// Keeps the Indice in step with the disk while Bubo runs; never returns until cancelled.
    ///
    /// Resumes from the last file event it handled, so changes made with Bubo closed are not lost;
    /// without that point, or when FSEvents lost events, it rescans everything.
    func keepFresh() async {
        let volume = Self.volumeID(of: root)
        let since: FSEventStreamEventId
        if let saved = resumePoint(), saved.volume == volume {
            since = saved.eventID
        } else {
            since = FSEventsGetCurrentEventId()
            rescan()
            saveResumePoint(eventID: since, volume: volume)
        }
        for await batch in FileEvents.batches(under: root, since: since) {
            if batch.needsRescan || batch.paths.contains(where: isMemory) {
                rescan()
            }
            saveResumePoint(eventID: batch.latestID, volume: volume)
        }
    }

    /// Brings every memory file up to date and forgets the deleted ones.
    // ponytail: a full stat pass per change, fine for memory folders; per-path refresh when the Secondo cervello (#114) brings thousands of notes.
    func rescan() {
        let onDisk = memoryFiles()
        var known: [String: (size: Int, modified: Double)] = [:]
        if let statement = try? prepare("SELECT path, size, modified FROM documents") {
            while sqlite3_step(statement) == SQLITE_ROW, let path = column(0, of: statement) {
                known[path] = (Int(sqlite3_column_int64(statement, 1)), sqlite3_column_double(statement, 2))
            }
            sqlite3_finalize(statement)
        }
        do {
            try Self.execute("BEGIN", in: connection)
            for path in known.keys where onDisk[path] == nil {
                try forget(path)
            }
            for (path, file) in onDisk where known[path].map({ $0 != (file.size, file.modified) }) ?? true {
                try forget(path)
                try store(path, size: file.size, modified: file.modified)
            }
            try Self.execute("COMMIT", in: connection)
        } catch {
            try? Self.execute("ROLLBACK", in: connection)
            Logger.index.error("Rescan failed: \(error)")
        }
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
    private func memoryFiles() -> [String: (size: Int, modified: Double)] {
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
        var found: [String: (size: Int, modified: Double)] = [:]
        for path in paths {
            guard let attributes = try? manager.attributesOfItem(atPath: path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? Int,
                  let modified = attributes[.modificationDate] as? Date else { continue }
            found[path] = (size, modified.timeIntervalSinceReferenceDate)
        }
        return found
    }

    private func store(_ path: String, size: Int, modified: Double) throws {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let project = path.hasPrefix(root + "/projects/")
            ? String(path.dropFirst(root.count + "/projects/".count).prefix { $0 != "/" }) : nil
        let insert = try prepare("INSERT INTO fragments(text, path, project) VALUES (?1, ?2, ?3)")
        defer { sqlite3_finalize(insert) }
        for fragment in MarkdownFragments.split(contents) {
            sqlite3_reset(insert)
            bind(fragment, at: 1, in: insert)
            bind(path, at: 2, in: insert)
            if let project { bind(project, at: 3, in: insert) } else { sqlite3_bind_null(insert, 3) }
            guard sqlite3_step(insert) == SQLITE_DONE else { throw lastError() }
        }
        let document = try prepare("INSERT INTO documents(path, size, modified) VALUES (?1, ?2, ?3)")
        defer { sqlite3_finalize(document) }
        bind(path, at: 1, in: document)
        sqlite3_bind_int64(document, 2, Int64(size))
        sqlite3_bind_double(document, 3, modified)
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

    private func resumePoint() -> (eventID: FSEventStreamEventId, volume: String)? {
        guard let statement = try? prepare("SELECT key, value FROM state") else { return nil }
        defer { sqlite3_finalize(statement) }
        var eventID: FSEventStreamEventId?
        var volume: String?
        while sqlite3_step(statement) == SQLITE_ROW {
            switch column(0, of: statement) {
            case "eventID": eventID = FSEventStreamEventId(bitPattern: sqlite3_column_int64(statement, 1))
            case "volume": volume = column(1, of: statement)
            default: break
            }
        }
        guard let eventID, let volume else { return nil }
        return (eventID, volume)
    }

    private func saveResumePoint(eventID: FSEventStreamEventId, volume: String) {
        do {
            let statement = try prepare("INSERT OR REPLACE INTO state(key, value) VALUES ('eventID', ?1), ('volume', ?2)")
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, Int64(bitPattern: eventID))
            bind(volume, at: 2, in: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        } catch {
            Logger.index.error("Could not save the resume point: \(error)")
        }
    }

    /// The FSEvents identity of the volume holding `path`, or of the home folder while `path` does not exist.
    private static func volumeID(of path: String) -> String {
        var info = stat()
        guard stat(path, &info) == 0 || stat(NSHomeDirectory(), &info) == 0,
              let uuid = FSEventsCopyUUIDForDevice(info.st_dev) else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    // MARK: SQLite

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
