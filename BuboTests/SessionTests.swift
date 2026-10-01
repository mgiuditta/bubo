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

    @Test func aSessionSavedBeforeItsPhaseWasKeptIsOpen() throws {
        let json = #"[{"id":"\#(UUID().uuidString)","title":"Prova","project":"file:///tmp/","activity":"ferma"}]"#
        let sessions = try JSONDecoder().decode([Session].self, from: Data(json.utf8))
        #expect(sessions.map(\.phase) == [.aperta])
        #expect(sessions.map(\.isInterrupted) == [false])
    }
}
