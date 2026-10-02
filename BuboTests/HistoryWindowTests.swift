import Foundation
import Testing
@testable import Bubo

/// The Cronologia window over made-up conversations: never the user's own, never the bridge.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct HistoryWindowTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func message(_ id: String, _ text: String, fromUser: Bool = true, daysAgo: Double = 1) -> CLIConversation.Message {
        CLIConversation.Message(id: id, isFromUser: fromUser, text: text, date: now.addingTimeInterval(-daysAgo * 86_400))
    }

    /// A conversation of 300 messages, longer than the 200 the bridge reads without `all`.
    var longConversation: [CLIConversation.Message] {
        (0..<300).map { message("m\($0)", "Messaggio numero \($0) sul login.", fromUser: $0.isMultiple(of: 2)) }
    }

    func result(found messageID: String?, in conversation: String = "c1", source: ConversationSource = .cli,
                project: String = "/Users/a/bubo", daysAgo: Double = 1) -> ConversationResult {
        let best = messageID.map { id in
            SearchHit(path: conversation, source: .conversations, text: "testo",
                      message: ConversationMessage(id: id, isFromUser: true, date: now.addingTimeInterval(-daysAgo * 86_400)))
        }
        return ConversationResult(id: conversation, title: "Login", source: source, project: URL(filePath: project),
                                  conversation: conversation, date: now.addingTimeInterval(-daysAgo * 86_400), best: best)
    }

    func reader(for result: ConversationResult, words: [String] = [], messages: [CLIConversation.Message],
                kept: [CLIConversation.Message] = []) -> ConversationReader {
        ConversationReader(result: result, words: words, resumeID: nil, read: { _ in messages }, indexed: { _ in kept })
    }

    // MARK: Opening on the message found

    @Test(arguments: ["m0", "m150", "m299"])
    func everyOpeningShowsTheMessageFoundHighlighted(id: String) async {
        let reader = reader(for: result(found: id), messages: longConversation)

        await reader.load()

        #expect(reader.content == .available)
        #expect(reader.lines.count == 300)
        #expect(reader.current == id)
        #expect(reader.position == id)
    }

    @Test func withNothingSearchedItOpensAtTheEnd() async {
        let reader = reader(for: result(found: nil), messages: longConversation)

        await reader.load()

        #expect(reader.current == "m299")
    }

    @Test func commandGJumpsToTheNextPointAndBackToTheFirst() async {
        let messages = [message("a", "Il login non va."), message("b", "Guardo il controller.", fromUser: false),
                        message("c", "Ora il login va.", fromUser: false)]
        let reader = reader(for: result(found: "a"), words: ["login"], messages: messages)
        await reader.load()

        reader.showNextMatch()
        #expect(reader.current == "c")
        #expect(reader.position == "c")
        reader.showNextMatch()
        #expect(reader.current == "a")
    }

    // MARK: Gone, old or failed

    @Test func aDeletedTranscriptSaysItIsNoLongerAvailableWithWhatTheIndiceKept() async {
        let kept = [message("a", "Il login non va."), message("b", "Guardo.", fromUser: false)]
        let reader = reader(for: result(found: "b"), messages: [], kept: kept)

        await reader.load()

        #expect(reader.content == .unavailable)
        #expect(reader.lines.map(\.id) == ["a", "b"])
        #expect(reader.current == "b")
        #expect(!reader.isPastCLIRetention(at: now))
    }

    @Test func withNothingInTheIndiceEitherItStillShowsTheMessageFound() async {
        let reader = reader(for: result(found: "b"), messages: [])

        await reader.load()

        #expect(reader.content == .unavailable)
        #expect(reader.lines.map(\.id) == ["b"])
    }

    @Test func aBridgeErrorIsShownNotSwallowed() async {
        let reader = ConversationReader(result: result(found: "a"), words: [], resumeID: nil,
                                        read: { _ in throw CocoaError(.fileReadUnknown) }, indexed: { _ in [] })

        await reader.load()

        #expect(reader.content == .failed)
    }

    @Test func pastThirtyDaysItWarnsThatItResumesFromBubosCopy() async {
        let old = reader(for: result(found: "a", daysAgo: 40), messages: [message("a", "Vecchio.", daysAgo: 40)])
        let recent = reader(for: result(found: "a"), messages: [message("a", "Recente.")])

        await old.load()
        await recent.load()

        #expect(old.isPastCLIRetention(at: now))
        #expect(!recent.isPastCLIRetention(at: now))
    }

    // MARK: The window's model

    @Test func aSessioneShowsTheResumeCommandOfItsLatestConversation() {
        var session = Session(id: UUID(), title: "Login", project: URL(filePath: "/Users/a/bubo"), activity: .ferma,
                              activitySince: now)
        session.conversations = ["t1", "t2", "t3"]
        let model = HistoryModel(search: { ConversationSearch(index: nil, sessions: [session], history: []) },
                                 read: { _ in [] })
        var found = result(found: "a", in: "t1", source: .session)
        found.id = session.id.uuidString

        model.open(found, searching: "login")

        #expect(model.reader?.resumeCommand == "claude --resume t3")
        #expect(model.reader?.words == ["login"])
    }

    @Test func theCronologiaCLIHasNoResumeCommand() {
        let model = HistoryModel(search: { ConversationSearch(index: nil, sessions: [], history: []) }, read: { _ in [] })

        model.open(result(found: "a"), searching: "login")

        #expect(model.reader?.resumeCommand == nil)
    }

    @Test func eachFilterCountsWhatTheOthersLeave() {
        let results = [result(found: "a", in: "1", source: .cli, project: "/a/bubo", daysAgo: 2),
                       result(found: "a", in: "2", source: .session, project: "/a/bubo", daysAgo: 20),
                       result(found: "a", in: "3", source: .cli, project: "/a/sito", daysAgo: 60)]
        let filters = HistoryFilters(project: "bubo")

        #expect(filters.count(in: results, at: now) == 2)
        #expect(filters.changing { $0.days = 7 }.count(in: results, at: now) == 1)
        #expect(filters.changing { $0.source = .cli }.count(in: results, at: now) == 1)
        #expect(filters.changing { $0.project = nil }.count(in: results, at: now) == 3)
        #expect(HistoryFilters(days: 90).count(in: results, at: now) == 3)
    }

    // MARK: The Indice

    @Test func theIndiceGivesEveryMessageOfAConversationInOrder() async throws {
        let claude = try ClaudeFolder()
        let index = try claude.open()
        try await index.store(longConversation, ofConversation: "c1", in: nil, modified: now)
        try await index.store([message("x", "Altro.")], ofConversation: "c2", in: nil, modified: now)

        let kept = try await index.messages(ofConversation: "c1")

        #expect(kept.count == 300)
        #expect(kept.first?.message?.id == "m0")
        #expect(kept.last?.message?.id == "m299")
    }
}
