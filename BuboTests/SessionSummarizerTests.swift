import Foundation
import Testing
@testable import Bubo

/// A model that answers with `answer`, counting its calls.
@MainActor
final class FakeSummaryEngine: SummaryEngine {
    let needsNetwork: Bool
    var answer: (SummaryInput) throws -> SessionSummary
    private(set) var calls = 0

    init(needsNetwork: Bool, answer: @escaping (SummaryInput) throws -> SessionSummary) {
        self.needsNetwork = needsNetwork
        self.answer = answer
    }

    func summary(of input: SummaryInput) async throws -> SessionSummary {
        calls += 1
        return try answer(input)
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SessionSummarizerTests {
    let folder: NotesFolder
    let defaults: UserDefaults
    let project: URL

    init() throws {
        folder = try NotesFolder()
        defaults = try #require(UserDefaults(suiteName: "SessionSummarizerTests-\(UUID().uuidString)"))
        project = folder.claude.folder.appending(path: "bubo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    }

    static let fixed = SessionSummary(done: ["Aggiunto il riassunto."], decisions: ["Parte a Fondi."], open: ["Provarlo."])

    /// Today in this Mac's time zone, as the note's name starts.
    static var today: String { Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()) }

    func makeStore(_ sessions: [Session]) throws -> SessionStore {
        let file = folder.claude.folder.appending(path: "Sessioni-\(UUID().uuidString).json")
        try JSONEncoder().encode(sessions).write(to: file)
        return SessionStore(file: file, worktrees: WorktreeManager(root: folder.claude.folder)) { throw CancellationError() }
    }

    func session(titled title: String = "Riassunto di Sessione", conversations: [String] = ["c1", "c2"]) -> Session {
        var session = Session(id: UUID(), title: title, project: project, activity: .ferma)
        session.conversations = conversations
        return session
    }

    func makeSummarizer(_ store: SessionStore, engines: [any SummaryEngine], choosing: Bool = true,
                        messages: [String: [CLIConversation.Message]] = [:],
                        isOnline: @escaping () async -> Bool = { true }) -> SessionSummarizer {
        let secondBrain = SecondBrain(index: nil, defaults: defaults)
        if choosing { secondBrain.choose(folder.notes) }
        return SessionSummarizer(sessions: store, secondBrain: secondBrain, index: nil, engines: engines,
                                 transcript: { messages[$0] ?? [CLIConversation.Message(isFromUser: true, text: $0)] },
                                 defaults: defaults, isOnline: isOnline)
    }

    func notes() throws -> [String] {
        let sessions = folder.notes.appending(path: "Bubo/Sessioni")
        return (try? FileManager.default.contentsOfDirectory(atPath: sessions.path))?.filter { $0.hasSuffix(".md") } ?? []
    }

    func note(named name: String) throws -> String {
        try String(contentsOf: folder.notes.appending(path: "Bubo/Sessioni/\(name)"), encoding: .utf8)
    }

    @Test func anArchivedSessionHasItsNoteInBuboSessioniWithinTenSeconds() async throws {
        let session = session()
        let store = try makeStore([session])
        let engine = FakeSummaryEngine(needsNetwork: true) { _ in Self.fixed }
        let summarizer = makeSummarizer(store, engines: [engine])
        let name = "\(Self.today) Riassunto di Sessione.md"
        let clock = ContinuousClock()
        let start = clock.now

        store.archive(session.id)
        while try notes().isEmpty, clock.now - start < .seconds(10) {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(clock.now - start < .seconds(10))
        #expect(try notes() == [name])
        let text = try note(named: name)
        #expect(text.contains("fase: archiviata"))
        #expect(text.contains("## Fatto\n\n- Aggiunto il riassunto."))
        try await SessionTests.wait { store.sessions.first?.summaryNote != nil }
        #expect(store.sessions.first?.summaryNote?.relativePath == "Bubo/Sessioni/\(name)")
        #expect(summarizer.notices[session.id] == .saved)
    }

    @Test func theModelReadsTheMessagesOfEveryTurn() async throws {
        let session = session()
        let store = try makeStore([session])
        var read: [String] = []
        let engine = FakeSummaryEngine(needsNetwork: true) { input in
            read = input.messages.map(\.text)
            return Self.fixed
        }
        let summarizer = makeSummarizer(store, engines: [engine], messages: [
            "c1": [CLIConversation.Message(isFromUser: true, text: "primo turno")],
            "c2": [CLIConversation.Message(isFromUser: false, text: "secondo turno")],
        ])

        _ = try await summarizer.summary(of: session.id)

        #expect(read == ["primo turno", "secondo turno"])
    }

    @Test(arguments: PlantedSecrets.all)
    func aNoteHasNoSecretEvenWhenTheModelRepeatsThem(_ transcript: PlantedSecrets.Transcript) async throws {
        let session = session(titled: transcript.titolo, conversations: ["c1"])
        let store = try makeStore([session])
        // A model that copies what it read, and also repeats the transcript as it was before the filter.
        let engine = FakeSummaryEngine(needsNetwork: true) { input in
            SessionSummary(done: input.messages.map(\.text), open: transcript.messages.map(\.text))
        }
        let summarizer = makeSummarizer(store, engines: [engine], messages: ["c1": transcript.messages])

        await summarizer.summarize(session.id)

        let name = try #require(try notes().first)
        let text = try note(named: name)
        for secret in transcript.secrets {
            #expect(!text.contains(secret))
        }
    }

    @Test func withoutNetworkAppleFMWritesTheSummary() async throws {
        let session = session()
        let store = try makeStore([session])
        let claude = FakeSummaryEngine(needsNetwork: true) { _ in Self.fixed }
        let onDevice = FakeSummaryEngine(needsNetwork: false) { _ in SessionSummary(done: ["Sul Mac."]) }
        let summarizer = makeSummarizer(store, engines: [claude, onDevice], isOnline: { false })

        await summarizer.summarize(session.id)

        #expect(claude.calls == 0)
        #expect(onDevice.calls == 1)
        #expect(try note(named: try #require(try notes().first)).contains("- Sul Mac."))
        #expect(store.sessions.first?.isSummaryPending == false)
    }

    @Test func aFailingClaudeFallsBackToAppleFM() async throws {
        let session = session()
        let store = try makeStore([session])
        let claude = FakeSummaryEngine(needsNetwork: true) { _ in throw AgentBridgeError.failed(message: "rete") }
        let onDevice = FakeSummaryEngine(needsNetwork: false) { _ in SessionSummary(done: ["Sul Mac."]) }
        let summarizer = makeSummarizer(store, engines: [claude, onDevice])

        await summarizer.summarize(session.id)

        #expect(claude.calls == 1)
        #expect(try notes().count == 1)
    }

    @Test func withoutNetworkAndAppleFMTheSummaryWaitsAndIsWrittenWhenTheNetworkReturns() async throws {
        let session = session()
        let store = try makeStore([session])
        let claude = FakeSummaryEngine(needsNetwork: true) { _ in Self.fixed }
        let onDevice = FakeSummaryEngine(needsNetwork: false) { _ in throw SummaryEngineError.unavailable }
        let network = NetworkSwitch()
        let summarizer = makeSummarizer(store, engines: [claude, onDevice], isOnline: { network.isOnline })

        await summarizer.summarize(session.id)

        #expect(try notes().isEmpty)
        #expect(store.sessions.first?.isSummaryPending == true)
        #expect(summarizer.notices[session.id] == .waitingForNetwork)

        network.isOnline = true
        await summarizer.retryPending()

        #expect(try notes().count == 1)
        #expect(store.sessions.first?.isSummaryPending == false)
        #expect(summarizer.notices[session.id] == .saved)
    }

    @Test func anUnreachableSecondBrainKeepsTheSummaryQueued() async throws {
        let session = session()
        let store = try makeStore([session])
        let summarizer = makeSummarizer(store, engines: [FakeSummaryEngine(needsNetwork: true) { _ in Self.fixed }])
        try FileManager.default.removeItem(at: folder.notes)

        await summarizer.summarize(session.id)

        #expect(store.sessions.first?.isSummaryPending == true)
        #expect(summarizer.notices[session.id] == .secondBrainUnreachable)
        #expect(!FileManager.default.fileExists(atPath: folder.notes.path))
    }

    @Test func withoutSecondBrainTheUserIsAskedAndARefusalWritesNothing() async throws {
        let session = session()
        let store = try makeStore([session])
        let engine = FakeSummaryEngine(needsNetwork: true) { _ in Self.fixed }
        let summarizer = makeSummarizer(store, engines: [engine], choosing: false)

        store.archive(session.id)
        try await SessionTests.wait { summarizer.notices[session.id] != nil }

        #expect(summarizer.notices[session.id] == .needsFolder)
        #expect(engine.calls == 0)

        summarizer.declineSummaries()

        #expect(summarizer.notices[session.id] == nil)
        #expect(!summarizer.isOn)
        #expect(try notes().isEmpty)
        #expect(store.sessions.first?.isSummaryPending == false)
    }

    @Test func choosingTheFolderWritesTheSummaryThatAsked() async throws {
        let session = session()
        let store = try makeStore([session])
        let summarizer = makeSummarizer(store, engines: [FakeSummaryEngine(needsNetwork: true) { _ in Self.fixed }],
                                        choosing: false)
        await summarizer.summarize(session.id)

        await summarizer.choose(folder.notes)

        #expect(try notes().count == 1)
        #expect(summarizer.notices[session.id] == .saved)
    }

    @Test func summarizingAgainKeepsOneNote() async throws {
        let session = session()
        let store = try makeStore([session])
        var answer = "primo"
        let engine = FakeSummaryEngine(needsNetwork: true) { _ in SessionSummary(done: [answer]) }
        let summarizer = makeSummarizer(store, engines: [engine])

        await summarizer.summarize(session.id)
        answer = "secondo"
        await summarizer.summarize(session.id)

        let names = try notes()
        #expect(names.count == 1)
        let text = try note(named: try #require(names.first))
        #expect(text.contains("- secondo"))
        #expect(!text.contains("- primo"))
    }

    @Test func withSummariesOffArchivingWritesNothing() async throws {
        let session = session()
        let store = try makeStore([session])
        defaults.set(false, forKey: SessionSummarizer.defaultsKey)
        let engine = FakeSummaryEngine(needsNetwork: true) { _ in Self.fixed }
        _ = makeSummarizer(store, engines: [engine])

        store.archive(session.id)
        try await Task.sleep(for: .milliseconds(100))

        #expect(engine.calls == 0)
        #expect(try notes().isEmpty)
    }
}

/// Whether the network is reachable, as a test switches it.
@MainActor
final class NetworkSwitch {
    var isOnline = false
}
