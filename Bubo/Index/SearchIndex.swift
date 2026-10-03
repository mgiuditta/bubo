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
    /// The past conversations: the Sessioni's turns and the Cronologia CLI.
    case conversations = "conversazioni"
}

/// Who wrote a message of a past conversation in the Indice, and when.
nonisolated struct ConversationMessage: Equatable, Sendable {
    /// The message's id in its conversation.
    var id: String
    /// Whether the user wrote it; otherwise Claude did.
    var isFromUser: Bool
    /// When it was written, or when its conversation last changed if the SDK did not say.
    var date: Date
}

/// Which rankings of the Indice's fusion found a fragment: its words, its meaning, or both.
nonisolated struct SearchMatch: OptionSet, Hashable, Sendable {
    let rawValue: Int

    /// Found by the words searched, with FTS5.
    static let words = SearchMatch(rawValue: 1 << 0)
    /// Found by meaning, with the vectors of the embedding model.
    static let meaning = SearchMatch(rawValue: 1 << 1)
}

/// A fragment of a file in the Indice that matches a search.
nonisolated struct SearchHit: Equatable, Sendable {
    /// The file the fragment comes from, or the id of its conversation.
    var path: String
    /// The Progetto whose memory holds the file, or where the conversation ran, as `~/.claude/projects` names it;
    /// `nil` for the user's CLAUDE.md and for the Secondo cervello.
    var project: String?
    /// Where the file comes from.
    var source: SearchSource = .memory
    /// The fragment: one Markdown section of the file, or one message of the conversation.
    var text: String
    /// Who wrote the message and when, for a conversation; `nil` for a file.
    var message: ConversationMessage?
    /// Which rankings found the fragment; only `.meaning` when no searched word is in it.
    var match: SearchMatch = .words

    /// Whether only its meaning found the fragment, none of the words searched.
    var isFoundByMeaningOnly: Bool { !match.contains(.words) }
}

/// The Indice: a rebuildable SQLite copy of the Memoria di Progetto of every Progetto, of the
/// user's CLAUDE.md, of the Secondo cervello and of the past conversations, searched by words with FTS5 and,
/// once an embedding model is installed, also by meaning, the two rankings fused with Reciprocal Rank Fusion.
///
/// It never holds the code of a Progetto. Deleting its file loses nothing: the next start rebuilds it.
/// The Secondo cervello is the user's own, untrusted text: it is only read, never run, and leaves the Mac
/// only as the answer to a `cerca` call.
actor SearchIndex {
    /// Opens the Indice at `database`, copying the memory found under `root`, the `~/.claude` folder.
    ///
    /// - Parameters:
    ///   - energy: What pauses the vectors: Low Power Mode or a low battery.
    ///   - fragmentLimit: The fragments beyond which ``fragmentLoad(largest:)`` warns.
    init(database: URL, root: URL, energy: any EnergyGauge = SystemEnergyGauge(),
         fragmentLimit: Int = SearchIndex.fragmentLimit) throws {
        self.energy = energy
        self.fragmentLimit = fragmentLimit
        let (pauses, reportPause) = AsyncStream.makeStream(of: IndexPause?.self, bufferingPolicy: .bufferingNewest(1))
        self.pauses = pauses
        self.reportPause = reportPause
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
                DROP TABLE IF EXISTS vectors;
                CREATE TABLE documents(path TEXT PRIMARY KEY, source TEXT NOT NULL, size INTEGER NOT NULL,
                                       modified REAL NOT NULL);
                CREATE VIRTUAL TABLE fragments USING fts5(text, path UNINDEXED, project UNINDEXED, source UNINDEXED,
                                                          message UNINDEXED, author UNINDEXED, date UNINDEXED,
                                                          tokenize = 'unicode61 remove_diacritics 2');
                CREATE TABLE state(key TEXT PRIMARY KEY, value) WITHOUT ROWID;
                CREATE TABLE vectors(fragment INTEGER PRIMARY KEY, vector BLOB NOT NULL);
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
        reportPause.finish()
        sqlite3_close(connection)
    }

    private static let layoutVersion = 4
    /// Fragments beyond which the Indice warns and suggests excluding folders: 100.000 (spec).
    static let fragmentLimit = 100_000
    /// How often a paused computation reads the battery again.
    private static let energyRecheck: Duration = .seconds(60)
    private let energy: any EnergyGauge
    private let fragmentLimit: Int
    /// Every change of the pause, `nil` when the vectors go on; for one reader, ``SemanticSearch``.
    nonisolated let pauses: AsyncStream<IndexPause?>
    private let reportPause: AsyncStream<IndexPause?>.Continuation
    /// Why the vectors wait now; `nil` while they go on.
    private var pause: IndexPause?
    /// Whether the count of fragments was last found beyond the limit, so the log says it once.
    private var wasBeyondLimit = false
    /// Folders of the Secondo cervello left out of the Indice, relative to it.
    private var excludedFolders: Set<String> = []
    /// Folders of the Secondo cervello whose notes a search puts first, relative to it.
    private var priorityFolders: Set<String> = []
    /// The people and projects of the profile, as folded words: `cerca` puts first the notes naming them.
    private var profileNames: [[String]] = []
    /// The real path of the `~/.claude` folder.
    private let root: String
    private let connection: OpaquePointer
    /// The folder of the Secondo cervello being followed, as the user chose it; `nil` without one.
    private var secondBrain: String?
    /// The model the vectors come from; `nil` while none is installed, and the Indice searches only by words.
    private var embedder: (any TextEmbedder)?
    /// The vectors of the fragments in memory; `nil` before the first one.
    private var matrix: VectorMatrix?
    /// The work computing the vectors still missing.
    private var vectorizing: Task<Void, Never>?
    /// How many fragments each ranking hands to the fusion.
    private static let candidates = 50
    /// Italian and English words too common to tell fragments apart.
    private static let stopWords: Set<String> = [
        "che", "chi", "cui", "non", "come", "dove", "quando", "perché", "perche", "cosa", "con", "per", "tra", "fra",
        "del", "dello", "della", "dei", "degli", "delle", "nel", "nello", "nella", "nei", "negli", "nelle", "sul", "sullo",
        "sulla", "sui", "sugli", "sulle", "dal", "dallo", "dalla", "dai", "dagli", "dalle", "all", "allo", "alla", "agli",
        "alle", "gli", "una", "uno", "sono", "sei", "era", "essere", "avere", "hai", "hanno", "anche", "più", "piu", "molto",
        "questo", "questa", "quello", "quella", "suo", "sua", "loro", "mio", "mia", "tuo", "tua", "fare", "fatto", "ogni",
        "sta", "stai", "stanno", "fa", "the", "and", "for", "with", "how", "what", "why", "when", "where", "are", "was", "this", "that", "from", "not",
    ]

    // MARK: Searching

    /// Returns up to `limit` fragments matching `text`, best first: by its words and, with an embedding model,
    /// by its meaning.
    ///
    /// - Parameter project: A Progetto's folder; when given, only its memory is searched.
    /// - Parameter source: When given, only the files from there are searched.
    /// - Parameter limit: At most this many fragments. The notes in the folders put first come before the others,
    ///   then the notes naming a person or project of the profile, each group keeping its order.
    func hits(for text: String, project: String? = nil, source: SearchSource? = nil, limit: Int = 8) async throws -> [SearchHit] {
        guard !priorityFolders.isEmpty || !profileNames.isEmpty, let secondBrain else {
            return try await rankedHits(for: text, project: project, source: source, limit: limit)
        }
        let folder = Self.realPath(secondBrain)
        let ranked = try await rankedHits(for: text, project: project, source: source, limit: Self.candidates)
        func weight(_ hit: SearchHit) -> Int {
            guard hit.source == .secondBrain, hit.path.hasPrefix(folder + "/") else { return 0 }
            return (Self.isNote(hit, inside: priorityFolders, of: folder) ? 2 : 0)
                + (Self.names(profileNames, in: hit) ? 1 : 0)
        }
        // Grouped by weight, highest first; `sorted` is stable, so each group keeps its order.
        return Array(ranked.map { ($0, weight($0)) }.sorted { $0.1 > $1.1 }.map(\.0).prefix(limit))
    }

    /// Makes ``hits(for:project:source:limit:)`` put first the notes of `folders`, relative to the Secondo cervello,
    /// then the notes naming one of `names`: the people and projects of the profile.
    func prioritize(_ folders: Set<String>, names: [String] = []) {
        priorityFolders = folders
        profileNames = names.map(Self.words(of:)).filter { !$0.isEmpty }
    }

    /// Whether `folders` holds the note of `hit`, relative to the Secondo cervello at `folder`.
    ///
    /// Folders compare by whole names: `Lavoro` does not hold `Lavoro2/a.md`.
    private static func isNote(_ hit: SearchHit, inside folders: Set<String>, of folder: String) -> Bool {
        let parts = hit.path.dropFirst(folder.count + 1).split(separator: "/").dropLast()
        return folders.contains { parts.starts(with: $0.split(separator: "/")) }
    }

    /// Whether the fragment of `hit` or its note's name holds one of `names` as whole words, whatever the case and
    /// accents: `Ada` names neither `adattare` nor `Adamo`.
    private static func names(_ names: [[String]], in hit: SearchHit) -> Bool {
        guard !names.isEmpty else { return false }
        let words = Self.words(of: hit.text + " " + (hit.path as NSString).lastPathComponent)
        return names.contains { name in
            words.indices.contains { words[$0...].starts(with: name) }
        }
    }

    /// The words of `text`, folded so that case and accents do not count.
    private static func words(of text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// Returns up to `limit` fragments matching `text`, best first, as ``hits(for:project:source:limit:)`` does
    /// without the folders put first.
    private func rankedHits(for text: String, project: String?, source: SearchSource?, limit: Int) async throws -> [SearchHit] {
        let words = text.split { !$0.isLetter && !$0.isNumber }
        guard !words.isEmpty else { return [] }
        let filter = (project == nil ? "" : "AND project = ?3 ") + (source == nil ? "" : "AND source = ?4")
        // Every word quoted, so nothing the user types is FTS5 syntax; a prefix match, so "notar" finds "notarizzazione".
        func match(_ words: [String]) -> String { words.map { "\"\($0)\"*" }.joined(separator: " OR ") }
        let byWords = "SELECT rowid FROM fragments WHERE fragments MATCH ?1 \(filter) ORDER BY rank LIMIT ?2"
        guard let embedder, matrix?.count ?? 0 > 0 else {
            return try fragments(try rowIDs(byWords, match: match(words.map(String.init)), project: project, source: source)
                .prefix(limit))
        }
        // With the meaning at hand, a word match counts only when strong: the fragment holds at least half of the
        // words that carry meaning. One word in common, as "casa" in a question about a loan, would outrank the
        // fragment the meaning found.
        let searched = Set(words.map { $0.lowercased() }).subtracting(Self.stopWords).filter { $0.count > 2 }.sorted()
        var found: [Int64: Int] = [:]
        for word in searched {
            for rowID in try rowIDs("SELECT rowid FROM fragments WHERE fragments MATCH ?1", match: match([word]),
                                    project: nil, source: nil) {
                found[rowID, default: 0] += 1
            }
        }
        let needed = (searched.count + 1) / 2
        let byStrongWords = try searched.isEmpty ? [] : rowIDs(byWords, match: match(searched), project: project,
                                                               source: source).filter { found[$0, default: 0] >= needed }
        var rankings = [byStrongWords]
        do {
            let query = try await embedder.vectors(for: [text], as: .query)[0]
            // Read after the wait: the fragments may have changed meanwhile.
            let allowed = filter.isEmpty ? nil : Set(try rowIDs("SELECT rowid FROM fragments WHERE 1 \(filter)",
                                                               project: project, source: source))
            rankings.append(matrix?.nearest(to: query, limit: Self.candidates, allowed: allowed) ?? [])
        } catch {
            Logger.index.error("Search by meaning failed, by strong word matches only: \(error)")
        }
        let wordMatches = Set(byStrongWords), meaningMatches = Set(rankings.dropFirst().joined())
        return try fragments(ReciprocalRankFusion.fuse(rankings).prefix(limit)) { rowID in
            SearchMatch().union(wordMatches.contains(rowID) ? .words : []).union(meaningMatches.contains(rowID) ? .meaning : [])
        }
    }

    /// Whether a search also goes by meaning: a model is in use and some fragments have their vectors.
    var searchesByMeaning: Bool { embedder != nil && matrix?.count ?? 0 > 0 }

    /// The fragments `rowIDs`, in order, skipping the ones gone, each with what found it.
    private func fragments(_ rowIDs: some Sequence<Int64>,
                           foundBy match: (Int64) -> SearchMatch = { _ in .words }) throws -> [SearchHit] {
        let statement = try prepare("SELECT path, project, source, text, message, author, date FROM fragments WHERE rowid = ?1")
        defer { sqlite3_finalize(statement) }
        var hits: [SearchHit] = []
        for rowID in rowIDs {
            sqlite3_reset(statement)
            sqlite3_bind_int64(statement, 1, rowID)
            guard sqlite3_step(statement) == SQLITE_ROW else { continue }
            var hit = hit(at: statement)
            hit.match = match(rowID)
            hits.append(hit)
        }
        return hits
    }

    /// Runs `sql`, which selects fragment rows, binding `match` to `?1`, the limit of candidates to `?2`,
    /// the memory of `project` to `?3` and `source` to `?4`.
    private func rowIDs(_ sql: String, match: String? = nil, project: String?, source: SearchSource?) throws -> [Int64] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        if let match { bind(match, at: 1, in: statement) }
        sqlite3_bind_int(statement, 2, Int32(Self.candidates))
        if let project { bind(Self.projectName(ofFolder: project), at: 3, in: statement) }
        if let source { bind(source.rawValue, at: 4, in: statement) }
        var rowIDs: [Int64] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rowIDs.append(sqlite3_column_int64(statement, 0))
        }
        return rowIDs
    }

    /// The fragment of the current row of `statement`, which selects `path, project, source, text, message, author, date`.
    private func hit(at statement: OpaquePointer) -> SearchHit {
        let message = column(4, of: statement).map { id in
            ConversationMessage(id: id, isFromUser: column(5, of: statement) == "utente",
                                date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)))
        }
        return SearchHit(path: column(0, of: statement) ?? "", project: column(1, of: statement),
                         source: column(2, of: statement).flatMap(SearchSource.init(rawValue:)) ?? .memory,
                         text: column(3, of: statement) ?? "", message: message)
    }

    /// Returns the answer to the `cerca` tool: the matching fragments, each under its file.
    ///
    /// When the Secondo cervello is searched but its folder cannot be reached, the answer says the notes are its last copy.
    func toolResult(for text: String, project: String?, source: SearchSource? = nil) async -> String {
        let notice = (source == nil || source == .secondBrain) && project == nil && !isSecondBrainReachable
            ? "La cartella del Secondo cervello non è raggiungibile: le note sono quelle dell'ultima lettura.\n\n" : ""
        do {
            let hits = try await hits(for: text, project: project, source: source)
            guard !hits.isEmpty else { return notice + Self.noResults }
            let folder = secondBrain.map { Self.realPath($0) }
            let found = hits.map { "### \(Self.heading(of: $0, inSecondBrain: folder))\n\n\($0.text)" }
                .joined(separator: "\n\n---\n\n")
            let notes = hits.filter { $0.source == .secondBrain }.compactMap { hit in
                folder.flatMap { NoteCitation(path: hit.path, inFolder: $0) }
            }
            let clarification = SimilarNotes.clarification(among: notes.map(\.note)).map { "\n\n---\n\n" + $0 } ?? ""
            let citesNotes = hits.contains { $0.source == .secondBrain }
            return notice + found + clarification + (citesNotes ? "\n\n---\n\n" + Self.citationRule : "")
        } catch {
            Logger.index.error("Search failed: \(error)")
            return "L'Indice non ha potuto cercare."
        }
    }

    /// The answer to `cerca` when nothing is found: the model says so instead of making an answer up.
    static let noResults = "Nessun risultato nell'Indice. Se la domanda riguarda le note dell'utente, rispondi che "
        + "nel Secondo cervello non c'è niente su questo, senza inventare."

    /// How the model cites the notes of the Secondo cervello, after the fragments that come from them.
    static let citationRule = "Ogni affermazione presa da una nota del Secondo cervello va seguita dalla sua "
        + "citazione, scritta esattamente come dopo \"Cita come\". Per una Riunione aggiungi il minuto del passaggio "
        + "dopo #, come [[Bubo/Riunioni/2026-10-03 Standup#12:40]]. Se nessun frammento risponde alla domanda, dillo, "
        + "senza inventare."

    /// The heading of `hit` in the answer to `cerca`: its file, with its citation for a note of the Secondo cervello
    /// at `secondBrain`, or its conversation with who wrote it and when.
    private static func heading(of hit: SearchHit, inSecondBrain secondBrain: String?) -> String {
        if hit.source == .secondBrain, let secondBrain,
           let citation = NoteCitation(path: hit.path, inFolder: secondBrain) {
            return "\(hit.path) (Cita come \(citation.wikilink))"
        }
        guard let message = hit.message else { return hit.path }
        let author = message.isFromUser ? "l'utente" : "Claude"
        return "Conversazione \(hit.path), messaggio di \(author) del \(message.date.formatted(.iso8601))"
    }

    /// Whether the folder of the Secondo cervello can be read now; `true` without one.
    private var isSecondBrainReachable: Bool {
        secondBrain.map(Self.isFolder) ?? true
    }

    /// The name `~/.claude/projects` gives the memory of the Progetto at `folder`.
    nonisolated static func projectName(ofFolder folder: String) -> String {
        String(folder.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    // MARK: Searching by meaning

    /// The fragments with a vector in memory.
    var vectorCount: Int { matrix?.count ?? 0 }

    /// Waits until the vectors missing when called are computed.
    func vectorsComputed() async {
        await vectorizing?.value
    }

    /// Searches by meaning with `embedder` from now on; `nil` goes back to words only.
    ///
    /// The vectors of another model, or of another revision, cannot be compared: they are forgotten and computed again,
    /// in the background, while the search by words goes on.
    func use(_ embedder: (any TextEmbedder)?) {
        self.embedder = embedder
        guard let embedder else {
            matrix = nil
            return
        }
        if state("vectors.model") != embedder.model.signature {
            do {
                try transaction {
                    try Self.execute("DELETE FROM vectors", in: connection)
                    try setState("vectors.model", to: embedder.model.signature)
                }
            } catch {
                Logger.index.error("Could not forget the vectors of the previous model: \(error)")
            }
        }
        loadMatrix()
        computeMissingVectors()
    }

    /// Starts computing the vectors still missing, unless that is already going on.
    private func computeMissingVectors() {
        guard embedder != nil, vectorizing == nil else { return }
        vectorizing = Task(priority: .utility) { await self.vectorizeMissing() }
    }

    /// Computes the vectors of the fragments without one, a few at a time, until none is left.
    private func vectorizeMissing() async {
        defer {
            vectorizing = nil
            report(nil)
        }
        var after: Int64 = 0
        while let embedder, !Task.isCancelled {
            let batch = fragmentsWithoutVectors(after: after)
            guard let last = batch.last else { return }
            // A long first indexing waits while the Mac saves energy, then resumes on its own: the model and
            // the fragments may have changed meanwhile, so they are read again.
            if energy.current.pause != nil {
                guard await energyAllowsVectors() else { return }
                continue
            }
            after = last.rowID
            do {
                let vectors = try await embedder.vectors(for: batch.map(\.text), as: .passage)
                // The model may have changed during the wait: its vectors would mix with the new ones.
                guard embedder === self.embedder else {
                    after = 0
                    continue
                }
                try transaction {
                    for (fragment, vector) in zip(batch, vectors) {
                        try store(VectorMatrix.half(vector), for: fragment.rowID)
                    }
                }
            } catch {
                Logger.index.error("Could not compute vectors: \(error)")
                return
            }
        }
    }

    /// Waits until the energy allows the vectors, reporting the pause meanwhile; `false` when cancelled first.
    private func energyAllowsVectors() async -> Bool {
        while let pause = energy.current.pause {
            report(pause)
            await energy.change(within: Self.energyRecheck)
            if Task.isCancelled { return false }
        }
        report(nil)
        return true
    }

    /// Tells ``pauses`` and the log when the pause changes.
    private func report(_ pause: IndexPause?) {
        guard pause != self.pause else { return }
        self.pause = pause
        reportPause.yield(pause)
        if let pause {
            Logger.index.notice("Vectors paused: \(String(describing: pause), privacy: .public)")
        } else {
            Logger.index.notice("Vectors resumed")
        }
    }

    /// Up to 16 fragments after `rowID` without a vector, in order.
    private func fragmentsWithoutVectors(after rowID: Int64) -> [(rowID: Int64, text: String)] {
        guard let statement = try? prepare("""
            SELECT rowid, text FROM fragments WHERE rowid > ?1 AND rowid NOT IN (SELECT fragment FROM vectors)
            ORDER BY rowid LIMIT 16
            """) else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, rowID)
        var fragments: [(rowID: Int64, text: String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            fragments.append((sqlite3_column_int64(statement, 0), column(1, of: statement) ?? ""))
        }
        return fragments
    }

    /// Saves the half-precision `vector` for the fragment `rowID`, if the fragment still exists.
    private func store(_ vector: [UInt16], for rowID: Int64) throws {
        let statement = try prepare("""
            INSERT OR REPLACE INTO vectors(fragment, vector) SELECT ?1, ?2 WHERE EXISTS (SELECT 1 FROM fragments WHERE rowid = ?1)
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, rowID)
        vector.withUnsafeBytes { bytes in
            _ = sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        guard sqlite3_changes(connection) > 0 else { return }
        if matrix == nil { matrix = VectorMatrix(dimension: vector.count) }
        matrix?.insert(vector, for: rowID)
    }

    /// Forgets the vectors of the fragments matching `condition`, which binds `value` to `?1`.
    private func forgetVectors(of condition: String, binding value: String) throws {
        let select = try prepare("SELECT rowid FROM fragments WHERE \(condition)")
        defer { sqlite3_finalize(select) }
        bind(value, at: 1, in: select)
        let delete = try prepare("DELETE FROM vectors WHERE fragment = ?1")
        defer { sqlite3_finalize(delete) }
        while sqlite3_step(select) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(select, 0)
            sqlite3_reset(delete)
            sqlite3_bind_int64(delete, 1, rowID)
            guard sqlite3_step(delete) == SQLITE_DONE else { throw lastError() }
            matrix?.remove(rowID)
        }
    }

    /// Reads every vector into memory; with no model, holds none.
    private func loadMatrix() {
        matrix = nil
        guard embedder != nil, let statement = try? prepare("SELECT fragment, vector FROM vectors") else { return }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            let count = Int(sqlite3_column_bytes(statement, 1)) / MemoryLayout<UInt16>.stride
            guard count > 0, let bytes = sqlite3_column_blob(statement, 1) else { continue }
            let vector = UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt16.self), count: count)
            if matrix == nil { matrix = VectorMatrix(dimension: count) }
            matrix?.insert(vector, for: sqlite3_column_int64(statement, 0))
        }
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
    ///
    /// - Parameter excludedFolders: Folders left out, relative to `folder`; their notes leave the Indice, and
    ///   come back when no longer excluded.
    func keepSecondBrainFresh(at folder: URL?, excluding excludedFolders: Set<String> = []) async {
        // Replaced before it even started: the newer call has the newer folder.
        guard !Task.isCancelled else { return }
        let chosen = folder?.standardizedFileURL.path
        let excluded = chosen == nil ? nil : excludedFolders.sorted().joined(separator: "\n")
        let isSameFolder = chosen == state("secondBrain")
        if !isSameFolder {
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
        self.excludedFolders = excludedFolders
        if excluded != state("secondBrain.excluded") {
            do {
                try setState("secondBrain.excluded", to: excluded)
            } catch {
                Logger.index.error("Could not save the excluded folders: \(error)")
            }
            // A full pass forgets the notes now excluded and reads the ones included again.
            if isSameFolder { rescanSecondBrain() }
        }
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
            case .conversations: break
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
                    guard !SecondBrainNotes.skips(relative, excluding: excludedFolders) else { continue }
                    let found = SecondBrainNotes.files(at: path, in: folder, excluding: excludedFolders)
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

    /// How many fragments the Indice holds, and the `limit` folders of the Secondo cervello holding the most.
    func fragmentLoad(largest limit: Int = 3) throws -> FragmentLoad {
        let count = try Self.integer("SELECT count(*) FROM fragments", in: connection)
        var folders: [String: Int] = [:]
        if let secondBrain {
            let prefix = Self.realPath(secondBrain) + "/"
            let statement = try prepare("SELECT path, count(*) FROM fragments WHERE source = ?1 GROUP BY path")
            defer { sqlite3_finalize(statement) }
            bind(SearchSource.secondBrain.rawValue, at: 1, in: statement)
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let path = column(0, of: statement), path.hasPrefix(prefix) else { continue }
                let parts = path.dropFirst(prefix.count).split(separator: "/")
                // A note at the top has no folder to exclude.
                guard parts.count > 1 else { continue }
                folders[String(parts[0]), default: 0] += Int(sqlite3_column_int64(statement, 1))
            }
        }
        let load = FragmentLoad(fragmentCount: count, limit: fragmentLimit, largestFolders: Array(folders
            .map { FolderLoad(relativePath: $0.key, fragmentCount: $0.value) }
            .sorted { ($0.fragmentCount, $1.relativePath) > ($1.fragmentCount, $0.relativePath) }
            .prefix(limit)))
        if load.exceedsLimit, !wasBeyondLimit {
            Logger.index.notice("The Indice holds \(count, privacy: .public) fragments, beyond \(self.fragmentLimit, privacy: .public)")
        }
        wasBeyondLimit = load.exceedsLimit
        return load
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
        computeMissingVectors()
    }

    private func forget(_ path: String) throws {
        try forgetVectors(of: "path = ?1", binding: path)
        for sql in ["DELETE FROM fragments WHERE path = ?1", "DELETE FROM documents WHERE path = ?1"] {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            bind(path, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        }
    }

    private func forgetAll(from source: SearchSource) throws {
        try forgetVectors(of: "source = ?1", binding: source.rawValue)
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

    // MARK: Conversations

    /// When the conversation `id` last changed, as the Indice has it; `nil` if it is not in the Indice.
    func modificationDate(ofConversation id: String) -> Date? {
        guard let statement = try? prepare("SELECT modified FROM documents WHERE path = ?1 AND source = ?2") else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        bind(id, at: 1, in: statement)
        bind(SearchSource.conversations.rawValue, at: 2, in: statement)
        return sqlite3_step(statement) == SQLITE_ROW
            ? Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)) : nil
    }

    /// Replaces the conversation `id` in the Indice with `messages`, one fragment each, a long one cut into pieces.
    ///
    /// - Parameters:
    ///   - folder: Where the conversation ran, which makes its Progetto; `nil` if unknown.
    ///   - modified: When the conversation last changed, also the date of the messages that have none.
    func store(_ messages: [CLIConversation.Message], ofConversation id: String, in folder: URL?, modified: Date) throws {
        try transaction {
            try forget(id)
            let insert = try prepare("""
                INSERT INTO fragments(text, path, project, source, message, author, date) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                """)
            defer { sqlite3_finalize(insert) }
            for (position, message) in messages.enumerated() {
                // An embedding model reads only so far: each piece gets its own vector.
                for piece in MarkdownFragments.pieces(of: message.text) {
                    sqlite3_reset(insert)
                    bind(piece, at: 1, in: insert)
                    bind(id, at: 2, in: insert)
                    if let folder { bind(Self.projectName(ofFolder: folder.path), at: 3, in: insert) } else { sqlite3_bind_null(insert, 3) }
                    bind(SearchSource.conversations.rawValue, at: 4, in: insert)
                    bind(message.id ?? String(position), at: 5, in: insert)
                    bind(message.isFromUser ? "utente" : "agente", at: 6, in: insert)
                    sqlite3_bind_double(insert, 7, (message.date ?? modified).timeIntervalSince1970)
                    guard sqlite3_step(insert) == SQLITE_DONE else { throw lastError() }
                }
            }
            let document = try prepare("INSERT INTO documents(path, source, size, modified) VALUES (?1, ?2, ?3, ?4)")
            defer { sqlite3_finalize(document) }
            bind(id, at: 1, in: document)
            bind(SearchSource.conversations.rawValue, at: 2, in: document)
            sqlite3_bind_int64(document, 3, Int64(messages.count))
            sqlite3_bind_double(document, 4, modified.timeIntervalSince1970)
            guard sqlite3_step(document) == SQLITE_DONE else { throw lastError() }
        }
        computeMissingVectors()
    }

    /// Returns the message `messageID` of the conversation `id` with the one before and the one after it, in order;
    /// empty if the Indice does not have it.
    func messages(around messageID: String, inConversation id: String) throws -> [SearchHit] {
        // A conversation's messages are stored one after the other, so its neighbours are the next and previous rows.
        let statement = try prepare("""
            WITH found(row) AS (SELECT rowid FROM fragments WHERE path = ?1 AND message = ?2 LIMIT 1)
            SELECT path, project, source, text, message, author, date FROM fragments, found
            WHERE fragments.rowid BETWEEN found.row - 1 AND found.row + 1 AND path = ?1 ORDER BY fragments.rowid
            """)
        defer { sqlite3_finalize(statement) }
        bind(id, at: 1, in: statement)
        bind(messageID, at: 2, in: statement)
        var hits: [SearchHit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            hits.append(hit(at: statement))
        }
        return hits
    }

    /// Returns every message of the conversation `id` the Indice holds, in order; empty if it has none.
    func messages(ofConversation id: String) throws -> [SearchHit] {
        let statement = try prepare("""
            SELECT path, project, source, text, message, author, date FROM fragments WHERE path = ?1 AND source = ?2
            ORDER BY rowid
            """)
        defer { sqlite3_finalize(statement) }
        bind(id, at: 1, in: statement)
        bind(SearchSource.conversations.rawValue, at: 2, in: statement)
        var hits: [SearchHit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            hits.append(hit(at: statement))
        }
        return hits
    }

    /// Removes the conversations `ids` from the Indice: a Sessione deleted in Bubo.
    func forgetConversations(_ ids: [String]) throws {
        try transaction {
            for id in ids { try forget(id) }
        }
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
            // The vectors forgotten in memory are back in the database.
            loadMatrix()
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
    /// The longest fragment in characters: about 400 tokens, within what an embedding model reads (512 for e5).
    static let maximumLength = 1500

    /// Returns the non-empty sections of `markdown`, each starting at a heading or at the top, the long ones
    /// cut into ``pieces(of:maximumLength:)``.
    static func split(_ markdown: String) -> [String] {
        sections(of: markdown).flatMap { pieces(of: $0) }
    }

    /// Cuts `text` into pieces of at most `maximumLength` characters, at paragraphs, else at lines, else at words.
    ///
    /// When `text` starts with a Markdown heading, every piece starts with it, so each one says what it is about.
    static func pieces(of text: String, maximumLength: Int = maximumLength) -> [String] {
        guard text.count > maximumLength else { return [text] }
        let firstLine = text.prefix { $0 != "\n" }
        let heading = firstLine.hasPrefix("#") && firstLine.count < maximumLength / 4 ? String(firstLine) : nil
        let body = heading == nil ? Substring(text) : text.dropFirst(firstLine.count)
        let room = maximumLength - (heading.map { $0.count + 1 } ?? 0)
        // The smallest units that fit: paragraphs, lines of a long paragraph, runs of words of a long line.
        var units: [String] = []
        for paragraph in body.components(separatedBy: "\n\n") where !paragraph.isEmpty {
            guard paragraph.count > room else { units.append(paragraph); continue }
            for line in paragraph.split(separator: "\n") {
                guard line.count > room else { units.append(String(line)); continue }
                var run = ""
                for word in line.split(separator: " ") {
                    if !run.isEmpty, run.count + 1 + word.count > room {
                        units.append(run)
                        run = ""
                    }
                    run += run.isEmpty ? String(word.prefix(room)) : " " + word
                }
                if !run.isEmpty { units.append(run) }
            }
        }
        var pieces: [String] = []
        var current = ""
        for unit in units.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !unit.isEmpty {
            if !current.isEmpty, current.count + 2 + unit.count > room {
                pieces.append(current)
                current = ""
            }
            current += current.isEmpty ? unit : "\n\n" + unit
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces.map { piece in heading.map { $0 + "\n" + piece } ?? piece }
    }

    /// Returns the non-empty sections of `markdown`, each starting at a heading or at the top.
    private static func sections(of markdown: String) -> [String] {
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
