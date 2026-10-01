import Foundation
import Testing
@testable import Bubo

/// The Palette's search over made-up conversations in a temporary Indice: never the user's own.
@Suite(.timeLimit(.minutes(1)))
struct ConversationSearchTests {
    let claude: ClaudeFolder
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        claude = try ClaudeFolder()
    }

    func message(_ id: String, _ text: String, fromUser: Bool = true, daysAgo: Double = 1) -> CLIConversation.Message {
        CLIConversation.Message(id: id, isFromUser: fromUser, text: text, date: now.addingTimeInterval(-daysAgo * 86_400))
    }

    func session(_ title: String, conversations: [String], project: String = "/Users/a/bubo") -> Session {
        var session = Session(id: UUID(), title: title, project: URL(filePath: project), activity: .ferma,
                              activitySince: now.addingTimeInterval(-3_600))
        session.conversations = conversations
        return session
    }

    @Test func aSessionesTurnsAreOneRowWithItsOtherMatches() async throws {
        let index = try claude.open()
        let first = [message("a1", "Il deploy usa fastlane."), message("a2", "Ok, deploy con fastlane.", fromUser: false)]
        try await index.store(first, ofConversation: "t1", in: URL(filePath: "/Users/a/bubo"), modified: now)
        // The second turn repeats the first and adds a message.
        try await index.store(first + [message("b3", "Rifai il deploy domani.")], ofConversation: "t2",
                              in: URL(filePath: "/Users/a/bubo"), modified: now)
        let sessione = session("Rilascio", conversations: ["t1", "t2"])
        let search = ConversationSearch(index: index, sessions: [sessione], history: [])
        var query = PaletteQuery()
        query.text = "deploy"

        let results = try await search.groups(for: query, at: now).flatMap(\.results)
        #expect(results.count == 1)
        #expect(results.first?.id == sessione.id.uuidString)
        #expect(results.first?.title == "Rilascio")
        #expect(results.first?.source == .session)
        #expect(results.first?.otherMatches == 2)
    }

    @Test func theCronologiaCLIHasItsTitleAndFiltersApply() async throws {
        let index = try claude.open()
        try await index.store([message("c1", "Briciola è il gatto.", daysAgo: 40)], ofConversation: "cli-1",
                              in: URL(filePath: "/Users/a/altro"), modified: now)
        try await index.store([message("d1", "Briciola mangia.", daysAgo: 2)], ofConversation: "t1",
                              in: URL(filePath: "/Users/a/bubo"), modified: now)
        let history = [CLIConversation(id: "cli-1", title: "Il gatto", folder: URL(filePath: "/Users/a/altro"),
                                       branch: nil, lastModified: now)]
        let search = ConversationSearch(index: index, sessions: [session("Gatti", conversations: ["t1"])], history: history)

        func titles(_ text: String) async throws -> [String] {
            var query = PaletteQuery()
            query.text = text
            return try await search.groups(for: query, at: now).flatMap(\.results).map(\.title)
        }
        #expect(try await titles("briciola") == ["Gatti", "Il gatto"])
        #expect(try await titles("briciola cli") == ["Il gatto"])
        #expect(try await titles("briciola sessioni") == ["Gatti"])
        #expect(try await titles("briciola 7g") == ["Gatti"])
        #expect(try await titles("briciola @altro") == ["Il gatto"])
        #expect(try await search.groups(for: { var q = PaletteQuery(); q.text = "briciola"; return q }(), at: now)
            .map(\.age) == [.lastWeek, .older])
    }

    @Test func anEmptyQueryShowsTheRecentConversations() async throws {
        let older = CLIConversation(id: "cli-1", title: "Vecchia", folder: nil, branch: nil,
                                    lastModified: now.addingTimeInterval(-86_400 * 10))
        let search = ConversationSearch(index: nil, sessions: [session("Nuova", conversations: ["t1", "t2"]),
                                                               session("Mai partita", conversations: [])],
                                        history: [older])

        let groups = try await search.groups(for: PaletteQuery(), at: now)
        #expect(groups.map(\.age) == [.lastWeek, .lastMonth])
        #expect(groups.flatMap(\.results).map(\.title) == ["Nuova", "Vecchia"])
        // A Sessione opens on its latest turn.
        #expect(groups.first?.results.first?.conversation == "t2")
    }

    @Test func thePreviewIsTheMessageWithTheOneBeforeAndAfter() async throws {
        let index = try claude.open()
        try await index.store([message("m1", "uno"), message("m2", "due"), message("m3", "tre"), message("m4", "quattro")],
                              ofConversation: "c", in: nil, modified: now)
        try await index.store([message("m1", "altro")], ofConversation: "d", in: nil, modified: now)

        #expect(try await index.messages(around: "m2", inConversation: "c").map(\.text) == ["uno", "due", "tre"])
        #expect(try await index.messages(around: "m1", inConversation: "c").map(\.text) == ["uno", "due"])
        #expect(try await index.messages(around: "m9", inConversation: "c").isEmpty)
    }

    @Test func aSearchOn30000FragmentsTakesAt50MillisecondsP95() async throws {
        let index = try claude.open()
        let words = ["deploy", "login", "gatto", "fattura", "worktree", "branch", "test", "colore", "orb", "quota"]
        for conversation in 0..<1_000 {
            let messages = (0..<30).map { position in
                message("\(position)", "Messaggio \(position) su \(words[(conversation + position) % 10]) e "
                    + "\(words[(conversation * 3 + position) % 10]) della conversazione \(conversation).")
            }
            try await index.store(messages, ofConversation: "c\(conversation)", in: URL(filePath: "/Users/a/p"),
                                  modified: now)
        }
        let search = ConversationSearch(index: index, sessions: [], history: [])
        var durations: [Duration] = []
        for round in 0..<20 {
            var query = PaletteQuery()
            query.text = words[round % 10]
            let clock = ContinuousClock()
            let start = clock.now
            _ = try await search.groups(for: query, at: now)
            durations.append(clock.now - start)
        }
        let p95 = durations.sorted()[18]
        #expect(p95 <= .milliseconds(50), "p95 \(p95)")
    }
}
