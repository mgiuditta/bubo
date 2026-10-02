import Foundation
import Testing
@testable import Bubo

struct SessionTests {
    @Test func theTitleIsTheFirstSixWordsOfThePrompt() {
        #expect(Session.proposedTitle(for: "  Correggi il   login quando la rete cade e riprova ") == "Correggi il login quando la rete")
        #expect(Session.proposedTitle(for: "").isEmpty)
    }

    @Test(arguments: [
        ("Correggi il login", "bubo/correggi-il-login"),
        ("Perché è già così? Sì!", "bubo/perche-e-gia-cosi-si"),
        ("", "bubo/sessione"),
        ("日本語", "bubo/sessione"),
    ])
    func theBranchIsASlugOfTheTitle(title: String, branch: String) {
        #expect(Session.proposedBranch(for: title) == branch)
    }

    @Test func aLongTitleGivesAShortBranch() {
        let branch = Session.proposedBranch(for: String(repeating: "parola ", count: 20))
        #expect(branch.count <= "bubo/".count + 40)
    }

    @MainActor
    @Test func aSessionThatWasWorkingWhenBuboQuitIsStopped() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let saved = Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp"))
        try JSONEncoder().encode([saved]).write(to: file)

        let store = SessionStore(file: file, worktrees: WorktreeManager(root: FileManager.default.temporaryDirectory)) {
            throw CancellationError()
        }

        #expect(store.sessions.map(\.activity) == [.ferma])
        #expect(store.sessions.map(\.isInterrupted) == [true])
        #expect(store.projects == [URL(filePath: "/tmp")])
    }

    /// A store kept in a new temporary file holding `saved`.
    @MainActor
    func makeStore(saving saved: [Session]) throws -> SessionStore {
        let file = FileManager.default.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
        try JSONEncoder().encode(saved).write(to: file)
        return SessionStore(file: file, worktrees: WorktreeManager(root: FileManager.default.temporaryDirectory)) {
            throw CancellationError()
        }
    }

    @MainActor
    @Test func aSessionWhoseProjectIsGoneIsInErrore() throws {
        let gone = URL(filePath: "/tmp/bubo-sparito-\(UUID().uuidString)")
        let store = try makeStore(saving: [Session(id: UUID(), title: "Prova", project: gone, activity: .ferma)])

        #expect(store.sessions.map(\.activity) == [.errore])
        #expect(store.sessions.first?.failure?.contains(gone.path) == true)
    }

    @MainActor
    @Test func aSessionWhoseWorktreeIsGoneIsInErrore() throws {
        let gone = Workspace(folder: URL(filePath: "/tmp/bubo-sparito-\(UUID().uuidString)"), branch: "bubo/prova")
        let store = try makeStore(saving: [Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp"),
                                                   workspace: gone, activity: .lavora)])

        #expect(store.sessions.map(\.activity) == [.errore])
    }

    @MainActor
    @Test func archivingKeepsTheSessionAndFreesItsPorts() throws {
        let session = Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp"), activity: .ferma,
                              ports: 40_000..<40_010)
        let store = try makeStore(saving: [session])

        store.archive(session.id)

        #expect(store.sessions.map(\.phase) == [.archiviata])
        #expect(store.sessions.first?.ports == nil)
    }

    @MainActor
    @Test func aSessionInLavoraIsNeitherArchivedNorDeleted() throws {
        let store = try makeStore(saving: [])
        try store.start("Prova", title: "Prova", branch: "bubo/prova", in: URL(filePath: "/tmp"))
        let id = try #require(store.sessions.first?.id)

        store.archive(id)
        store.delete(id)

        #expect(store.sessions.map(\.phase) == [.aperta])
    }

    @MainActor
    @Test func aSecondSessionOnTheCheckoutIsRefused() throws {
        let store = try makeStore(saving: [])
        let project = URL(filePath: "/tmp")
        try store.start("Prova", title: "Prima", branch: "", in: project, onCheckout: true)

        #expect(throws: SessionError.checkoutTaken(by: "Prima")) {
            try store.start("Prova", title: "Seconda", branch: "", in: URL(filePath: "/tmp/"), onCheckout: true)
        }
        try store.start("Prova", title: "Isolata", branch: "bubo/isolata", in: project)

        #expect(store.sessions.map(\.title) == ["Prima", "Isolata"])
        #expect(store.sessions.first?.workspace == Workspace(folder: project))
        #expect(store.checkoutSession(of: project)?.title == "Prima")
    }

    @MainActor
    @Test func anArchivedSessionFreesTheCheckout() throws {
        var session = Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp"), activity: .ferma)
        session.isOnCheckout = true
        let store = try makeStore(saving: [session])

        store.archive(session.id)

        #expect(store.checkoutSession(of: URL(filePath: "/tmp")) == nil)
    }

    @MainActor
    @Test func deletingRemovesTheSession() throws {
        let session = Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp"), activity: .ferma)
        let store = try makeStore(saving: [session])

        store.delete(session.id)

        #expect(store.sessions.isEmpty)
    }

    @MainActor
    @Test func aSessionFromTheCLIHistoryKeepsTheConversationItForks() throws {
        let store = try makeStore(saving: [])
        let conversation = CLIConversation(id: "c-1", title: "Correggi il login", folder: URL(filePath: "/tmp"),
                                           branch: nil, lastModified: .now)

        try store.start("Continua", title: "Correggi il login", branch: "", in: URL(filePath: "/tmp"), onCheckout: true,
                        forkingFrom: conversation)

        #expect(store.sessions.map(\.forkedFrom) == ["c-1"])
    }

    /// A bridge played by `/bin/sh` that writes every command to `log`, ends every turn at once, and lists as the
    /// Cronologia CLI the first conversation it was asked to keep, plus `c-1`.
    static func keepingBridge(log: URL) -> AgentBridge {
        let script = #"""
            while read line; do
                echo "$line" >> "$1"
                id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
                case "$line" in
                    *'"type":"ask"'*) echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}" ;;
                    *'"type":"history"'*)
                        kept=$(sed -n 's/.*"keep":"\([^"]*\)".*/\1/p' "$1" | head -1)
                        echo "{\"v\":4,\"type\":\"history\",\"id\":\"$id\",\"conversations\":[{\"id\":\"$kept\",\"title\":\"Bubo\",\"lastModified\":0},{\"id\":\"c-1\",\"title\":\"CLI\",\"lastModified\":0}]}" ;;
                esac
            done
            """#
        return AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script, "sh", log.path],
                           environment: ["PATH": "/usr/bin:/bin"]) { _, _, _ in "" }
    }

    /// Waits up to 5 s for `condition`.
    @MainActor
    static func wait(until condition: () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func eachTurnIsKeptAndDeletingTheSessionForgetsIt() async throws {
        let log = FileManager.default.temporaryDirectory.appending(path: "bridge-\(UUID().uuidString).log")
        let file = FileManager.default.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: file)
        }
        let bridge = Self.keepingBridge(log: log)
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: FileManager.default.temporaryDirectory)) {
            bridge
        }

        try store.start("Ciao", title: "Prova", branch: "", in: URL(filePath: "/tmp"), onCheckout: true)
        try await Self.wait { store.sessions.first?.activity == .ferma }
        let session = try #require(store.sessions.first)
        let kept = try #require(session.conversations.first)
        #expect(session.conversations.count == 1)
        #expect(try String(contentsOf: log, encoding: .utf8).contains(#""keep":"\#(kept)""#))

        #expect(try await store.history().map(\.id) == ["c-1"])

        store.delete(session.id)
        let forget = #"{"conversations":["\#(kept)"],"type":"forget","v":4}"#
        try await Self.wait { (try? String(contentsOf: log, encoding: .utf8).contains(forget)) == true }
        #expect(try String(contentsOf: log, encoding: .utf8).contains(forget))
    }

    /// The `resume` and `keep` of each `ask` in `log`, in order.
    static func asks(in log: URL) throws -> [(resume: String?, keep: String?)] {
        try String(contentsOf: log, encoding: .utf8).split(separator: "\n").compactMap { line in
            let command = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            guard command?["type"] as? String == "ask" else { return nil }
            return (command?["resume"] as? String, command?["keep"] as? String)
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func eachTurnResumesTheConversationOfTheLastTurnThatRan() async throws {
        let log = FileManager.default.temporaryDirectory.appending(path: "bridge-\(UUID().uuidString).log")
        let file = FileManager.default.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: file)
        }
        // Ends every turn at once; the turn asked "Sbaglia" fails before answering.
        let script = #"""
            while read line; do
                echo "$line" >> "$1"
                id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
                case "$line" in
                    *'"prompt":"Sbaglia"'*) echo "{\"v\":4,\"type\":\"error\",\"id\":\"$id\",\"message\":\"no\"}" ;;
                    *'"type":"ask"'*) echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}" ;;
                esac
            done
            """#
        let bridge = AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script, "sh", log.path],
                                 environment: ["PATH": "/usr/bin:/bin"]) { _, _, _ in "" }
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: FileManager.default.temporaryDirectory)) {
            bridge
        }
        let conversation = CLIConversation(id: "c-1", title: "CLI", folder: nil, branch: nil, lastModified: .now)

        let id = try store.start("Ciao", title: "Prova", branch: "", in: URL(filePath: "/tmp"), onCheckout: true,
                                 forkingFrom: conversation)
        try await Self.wait { store.sessions.first?.activity == .ferma }
        for (prompt, ending) in [("Ancora", Session.Activity.ferma), ("Sbaglia", .errore), ("Infine", .ferma)] {
            store.sendBack(prompt, to: id, keepingAcceptedAmong: [])
            try await Self.wait { store.sessions.first?.activity == ending }
        }

        let session = try #require(store.sessions.first)
        #expect(session.conversations.count == 4)
        let asks = try Self.asks(in: log)
        #expect(asks.map(\.keep) == session.conversations)
        // The failed turn never ran: the next one resumes the turn before it.
        #expect(asks.map(\.resume) == ["c-1", session.conversations[0], session.conversations[1],
                                        session.conversations[1]])
        #expect(session.continuedConversation == session.conversations[3])
        #expect(session.forkedFrom == "c-1")
    }

    @Test func aSessionSavedBeforeTheChainResumesWhatItForked() throws {
        let json = #"[{"id":"\#(UUID().uuidString)","title":"Prova","project":"file:///tmp/","activity":"ferma","forkedFrom":"c-1","conversations":["t-1"]}]"#
        let sessions = try JSONDecoder().decode([Session].self, from: Data(json.utf8))
        #expect(sessions.map(\.continuedConversation) == ["c-1"])
    }

    /// The `prompt` and `upTo` of each `ask` in `log`, in order.
    static func prompts(in log: URL) throws -> [(prompt: String?, upTo: String?)] {
        try String(contentsOf: log, encoding: .utf8).split(separator: "\n").compactMap { line in
            let command = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            guard command?["type"] as? String == "ask" else { return nil }
            return (command?["prompt"] as? String, command?["upTo"] as? String)
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func riprendiAfterQuittingAsksThePromptOfTheInterruptedTurn() async throws {
        let log = FileManager.default.temporaryDirectory.appending(path: "bridge-\(UUID().uuidString).log")
        let file = FileManager.default.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: file)
        }
        let bridge = Self.keepingBridge(log: log)
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: FileManager.default.temporaryDirectory)) {
            bridge
        }
        let id = try store.start("Primo", title: "Prova", branch: "", in: URL(filePath: "/tmp"), onCheckout: true)
        try await Self.wait { store.sessions.first?.activity == .ferma }
        store.sendBack("Rimando", to: id, keepingAcceptedAmong: [])
        try await Self.wait { store.sessions.first?.conversations.count == 2 && store.sessions.first?.activity == .ferma }
        #expect(store.sessions.first?.turnPrompt == "Rimando")

        // Bubo quits during the rimando: the saved Sessione was still in Lavora.
        var saved = try #require(store.sessions.first)
        saved.activity = .lavora
        try JSONEncoder().encode([saved]).write(to: file)
        let relaunched = SessionStore(file: file,
                                      worktrees: WorktreeManager(root: FileManager.default.temporaryDirectory)) { bridge }
        relaunched.resume(id)
        try await Self.wait { relaunched.sessions.first?.conversations.count == 3 }
        try await Self.wait { relaunched.sessions.first?.activity == .ferma }

        #expect(try Self.prompts(in: log).map(\.prompt) == ["Primo", "Rimando", "Rimando"])
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func continuaDaQuiCutsOnlyTheConversationItForks() async throws {
        let log = FileManager.default.temporaryDirectory.appending(path: "bridge-\(UUID().uuidString).log")
        let file = FileManager.default.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: file)
        }
        let bridge = Self.keepingBridge(log: log)
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: FileManager.default.temporaryDirectory)) {
            bridge
        }
        let conversation = CLIConversation(id: "c-1", title: "CLI", folder: nil, branch: nil, lastModified: .now)

        let id = try store.start("Ciao", title: "Prova", branch: "", in: URL(filePath: "/tmp"), onCheckout: true,
                                 forkingFrom: conversation, upTo: "m-2")
        try await Self.wait { store.sessions.first?.activity == .ferma }
        store.sendBack("Ancora", to: id, keepingAcceptedAmong: [])
        try await Self.wait { store.sessions.first?.conversations.count == 2 && store.sessions.first?.activity == .ferma }

        let session = try #require(store.sessions.first)
        #expect(try Self.prompts(in: log).map(\.upTo) == ["m-2", nil])
        #expect(try Self.asks(in: log).map(\.resume) == ["c-1", session.conversations[0]])
        #expect(session.forkedUpTo == "m-2")
    }

    @Test func aDraftFromTheCLIHistoryStartsEvenEmpty() {
        let draft = SessionDraft(conversation: CLIConversation(id: "c-1", title: "Prova", folder: nil, branch: nil,
                                                               lastModified: .now))
        #expect(draft.canStartEmpty)
        #expect(draft.firstPrompt("Aggiungi i test") == "Aggiungi i test")
        #expect(draft.firstPrompt("") == String(localized: "Continua da dove ti eri fermato."))
        #expect(!SessionDraft().canStartEmpty)
    }

    @Test func aSessionSavedBeforeItsPhaseWasKeptIsOpen() throws {
        let json = #"[{"id":"\#(UUID().uuidString)","title":"Prova","project":"file:///tmp/","activity":"ferma"}]"#
        let sessions = try JSONDecoder().decode([Session].self, from: Data(json.utf8))
        #expect(sessions.map(\.phase) == [.aperta])
        #expect(sessions.map(\.isInterrupted) == [false])
        #expect(sessions.map(\.forkedFrom) == [nil])
        #expect(sessions.map(\.conversations) == [[]])
    }

    @Test func aSessionSavedBeforeSummariesDecodes() throws {
        let json = #"[{"id":"\#(UUID().uuidString)","title":"Prova","project":"file:///tmp/","activity":"ferma"}]"#
        let sessions = try JSONDecoder().decode([Session].self, from: Data(json.utf8))
        #expect(sessions.map(\.summaryNote) == [nil])
        #expect(sessions.map(\.isSummaryPending) == [false])
    }
}

extension SessionTests {
    @Test func aSessionSavedBeforeAutomationsDecodesWithoutAMark() throws {
        let saved = #"[{"id":"6A1F3C2E-0000-4000-8000-000000000001","title":"Prova","project":"file:///tmp/","activity":"ferma"}]"#
        let session = try #require(try JSONDecoder().decode([Session].self, from: Data(saved.utf8)).first)
        #expect(session.automation == nil)
        #expect(session.denials.isEmpty)
        #expect(session.effectiveMode == nil)
    }
}
