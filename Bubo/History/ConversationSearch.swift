import Foundation

/// Where a past conversation comes from: a Sessione of Bubo or the Cronologia CLI.
nonisolated enum ConversationSource: Hashable, Sendable {
    case session
    case cli
}

/// One row of the Palette: a past conversation, with the message that answers the search best.
nonisolated struct ConversationResult: Identifiable, Equatable, Sendable {
    /// The Sessione's id, or the id of the Cronologia CLI conversation.
    var id: String
    var title: String
    var source: ConversationSource
    /// The folder the conversation ran in; `nil` if unknown.
    var project: URL?
    /// The agent's conversation to open: the one of the best message, or the latest of the Sessione.
    var conversation: String
    /// When the best message was written, or when the conversation last changed.
    var date: Date
    /// The message that answers the search best; `nil` for a recent conversation, with nothing searched.
    var best: SearchHit?
    /// How many other messages of the conversation answer the search.
    var otherMatches = 0
}

nonisolated extension ConversationResult {
    /// The latest conversation of `session`, with nothing searched; `nil` before its first turn.
    init?(latestOf session: Session) {
        guard let last = session.conversations.last else { return nil }
        self.init(id: session.id.uuidString, title: session.title, source: .session, project: session.project,
                  conversation: last, date: session.activitySince ?? .distantPast)
    }
}

/// One row of the Palette's Secondo cervello group: a note, with the section that answers the search best.
nonisolated struct NoteResult: Identifiable, Equatable, Sendable {
    /// The note's file.
    var id: String { best.path }
    /// The section that answers the search best.
    var best: SearchHit
    /// How many other sections of the note answer the search.
    var otherMatches = 0

    /// The note's name: its file name without `.md`.
    var title: String { URL(filePath: best.path).deletingPathExtension().lastPathComponent }
}

/// How old the conversations of a group of the Palette are.
nonisolated enum ConversationAge: CaseIterable, Sendable {
    case lastWeek
    case lastMonth
    case older

    /// The age of what happened at `date`, seen at `now`.
    init(of date: Date, at now: Date) {
        let days = now.timeIntervalSince(date) / 86_400
        self = days <= 7 ? .lastWeek : days <= 30 ? .lastMonth : .older
    }

    var title: LocalizedStringResource {
        switch self {
        case .lastWeek: "Ultimi 7 giorni"
        case .lastMonth: "Ultimi 30 giorni"
        case .older: "Meno recenti"
        }
    }
}

/// The Palette's results of one age, most relevant first.
nonisolated struct ConversationGroup: Identifiable, Equatable, Sendable {
    var age: ConversationAge
    var results: [ConversationResult]

    var id: ConversationAge { age }
}

/// Searches the past conversations in the Indice, the same search as `cerca`, and makes one row per conversation.
///
/// Everything stays on the Mac: the Indice, the Sessioni and the Cronologia CLI are all local.
nonisolated struct ConversationSearch: Sendable {
    /// How many fragments the Indice returns before they are grouped and filtered.
    static let fragmentLimit = 300
    /// How many conversations a search or the recent ones show at most.
    static let resultLimit = 50
    /// How many notes of the Secondo cervello a search shows at most.
    static let noteLimit = 20

    /// The Indice; `nil` when its database cannot be opened, and only the recent conversations are shown.
    let index: SearchIndex?
    /// The Sessioni, for their titles and Progetti.
    let sessions: [Session]
    /// The Cronologia CLI as last read, for its titles and folders.
    let history: [CLIConversation]

    /// The conversations that answer `query` at `now`, grouped by age; the recent ones when no word is written.
    func groups(for query: PaletteQuery, at now: Date = .now) async throws -> [ConversationGroup] {
        let (text, filters) = query.search
        guard !text.isEmpty else { return recentGroups(filters: filters, at: now) }
        guard let index else { return [] }
        let hits = try await index.hits(for: text, source: .conversations, limit: Self.fragmentLimit)
        return groups(of: hits, filters: filters, at: now)
    }

    /// The notes of the Secondo cervello that answer the words of `query`, best first, one row per note; none when no
    /// word is written. The same search as `cerca` with fonte Secondo cervello.
    func notes(for query: PaletteQuery) async throws -> [NoteResult] {
        let text = query.search.text
        guard !text.isEmpty, let index else { return [] }
        let hits = try await index.hits(for: text, source: .secondBrain, limit: Self.fragmentLimit)
        return Self.notes(of: hits)
    }

    /// `hits`, best first, as one result per note, in the order of their best section.
    static func notes(of hits: [SearchHit]) -> [NoteResult] {
        var notes: [NoteResult] = []
        var positions: [String: Int] = [:]
        for hit in hits {
            if let position = positions[hit.path] {
                notes[position].otherMatches += 1
            } else {
                positions[hit.path] = notes.count
                notes.append(NoteResult(best: hit))
            }
        }
        return Array(notes.prefix(Self.noteLimit))
    }

    /// `hits`, best first, as one result per conversation, grouped by age and kept in order within each group.
    ///
    /// The turns of a Sessione are one conversation: each repeats the earlier ones, so a message counts once.
    func groups(of hits: [SearchHit], filters: [PaletteFilter], at now: Date) -> [ConversationGroup] {
        let owners = Dictionary(sessions.flatMap { session in session.conversations.map { ($0, session) } },
                                uniquingKeysWith: { first, _ in first })
        let cli = Dictionary(history.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var results: [ConversationResult] = []
        var positions: [String: Int] = [:]
        var seenTexts: [String: Set<String>] = [:]
        for hit in hits {
            guard let message = hit.message else { continue }
            let result: ConversationResult
            if let session = owners[hit.path] {
                result = ConversationResult(id: session.id.uuidString, title: session.title, source: .session,
                                            project: session.project, conversation: hit.path, date: message.date,
                                            best: hit)
            } else {
                let conversation = cli[hit.path]
                result = ConversationResult(id: hit.path, title: conversation?.title ?? Self.untitled, source: .cli,
                                            project: conversation?.folder, conversation: hit.path, date: message.date,
                                            best: hit)
            }
            guard Self.matches(result, filters: filters, projectName: hit.project, at: now) else { continue }
            guard seenTexts[result.id, default: []].insert(hit.text).inserted else { continue }
            if let position = positions[result.id] {
                results[position].otherMatches += 1
            } else {
                positions[result.id] = results.count
                results.append(result)
            }
        }
        return Self.grouped(Array(results.prefix(Self.resultLimit)), at: now)
    }

    /// The conversations that changed last, newest first, grouped by age.
    func recentGroups(filters: [PaletteFilter], at now: Date) -> [ConversationGroup] {
        let own = sessions.compactMap(ConversationResult.init(latestOf:))
        let theirs = history.map { conversation in
            ConversationResult(id: conversation.id, title: conversation.title, source: .cli, project: conversation.folder,
                               conversation: conversation.id, date: conversation.lastModified)
        }
        let recent = (own + theirs)
            .filter { Self.matches($0, filters: filters, projectName: nil, at: now) }
            .sorted { $0.date > $1.date }
            .prefix(Self.resultLimit)
        return Self.grouped(Array(recent), at: now)
    }

    /// The title of a Cronologia CLI conversation not listed yet.
    private static var untitled: String { String(localized: "Conversazione senza titolo") }

    /// Whether `result` passes every one of `filters`.
    ///
    /// - Parameter projectName: The Progetto as the Indice names it, for a folder Bubo does not know.
    private static func matches(_ result: ConversationResult, filters: [PaletteFilter], projectName: String?,
                                at now: Date) -> Bool {
        filters.allSatisfy { filter in
            switch filter {
            case .source(let source):
                result.source == source
            case .days(let days):
                result.date >= now.addingTimeInterval(-Double(days) * 86_400)
            case .project(let name):
                [result.project?.lastPathComponent, result.project == nil ? projectName : nil]
                    .contains { $0?.localizedStandardContains(name) == true }
            case .kind:
                true
            }
        }
    }

    /// `results` in groups by age, in the order of ``ConversationAge``, without the empty ones.
    private static func grouped(_ results: [ConversationResult], at now: Date) -> [ConversationGroup] {
        let byAge = Dictionary(grouping: results) { ConversationAge(of: $0.date, at: now) }
        return ConversationAge.allCases.compactMap { age in
            byAge[age].map { ConversationGroup(age: age, results: $0) }
        }
    }
}
