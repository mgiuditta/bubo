import Foundation
import Testing
@testable import Bubo

struct SessionProposalTests {
    let bubo = URL(filePath: "/Users/io/dev/bubo", directoryHint: .isDirectory)
    let sito = URL(filePath: "/Users/io/dev/sito", directoryHint: .isDirectory)

    func file(_ path: String) -> Allegato {
        Allegato(fileAt: URL(filePath: path))
    }

    @Test func filesAllInOneProgettoProposeASessioneOnIt() {
        let proposal = SessionProposal(for: [file("/Users/io/dev/bubo/README.md"), file("/Users/io/dev/bubo/Bubo/App.swift")],
                                       projects: [sito, bubo]) { _ in false }
        #expect(proposal == .session(on: bubo))
    }

    @Test func theInnermostOfNestedProgettiWins() {
        let inner = bubo.appending(path: "Packages/RemoteKit", directoryHint: .isDirectory)
        let proposal = SessionProposal(for: [file("/Users/io/dev/bubo/Packages/RemoteKit/Package.swift")],
                                       projects: [bubo, inner]) { _ in false }
        #expect(proposal == .session(on: inner))
    }

    @Test func aFolderNamedLikeAProgettoIsNotInsideIt() {
        let proposal = SessionProposal(for: [file("/Users/io/dev/bubo-vecchio/note.txt")], projects: [bubo]) { _ in false }
        #expect(proposal == nil)
    }

    @Test func aGitRepoThatIsNotAProgettoProposesToOpenIt() throws {
        let repo = FileManager.default.temporaryDirectory.appending(path: "repo-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repo.appending(path: ".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let proposal = SessionProposal(for: [Allegato(fileAt: repo)], projects: [bubo])
        #expect(proposal == .newProject(repo))
    }

    @Test func aFolderOutsideGitProposesNothing() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cartella-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(SessionProposal(for: [Allegato(fileAt: folder)], projects: [bubo]) == nil)
    }

    @Test func filesFromMoreProgettiStayADomanda() {
        let proposal = SessionProposal(for: [file("/Users/io/dev/bubo/README.md"), file("/Users/io/dev/sito/index.html")],
                                       projects: [bubo, sito]) { _ in true }
        #expect(proposal == nil)
    }

    @Test func filesOutsideEveryProgettoStayADomanda() {
        let proposal = SessionProposal(for: [file("/Users/io/Downloads/fattura.pdf")], projects: [bubo, sito]) { _ in true }
        #expect(proposal == nil)
    }

    @Test func aFileOutsideNextToOneInsideStaysADomanda() {
        let proposal = SessionProposal(for: [file("/Users/io/dev/bubo/README.md"), file("/Users/io/Downloads/fattura.pdf")],
                                       projects: [bubo]) { _ in true }
        #expect(proposal == nil)
    }

    @Test func textAloneProposesNothing() {
        let proposal = SessionProposal(for: [Allegato(draggedText: "/Users/io/dev/bubo")], projects: [bubo]) { _ in true }
        #expect(proposal == nil)
    }

    @Test func theDraftPointsToTheFilesInsideTheProgetto() {
        var draft = SessionDraft(prompt: "Sistema il README")
        draft.project = bubo
        draft.files = [URL(filePath: "/Users/io/dev/bubo/README.md"), URL(filePath: "/Users/io/dev/bubo/Bubo/App.swift")]

        // The heading of the list follows the language of the Mac.
        let prompt = draft.firstPrompt("Sistema il README")
        #expect(prompt.hasPrefix("Sistema il README\n\n"))
        #expect(prompt.hasSuffix(":\n- README.md\n- Bubo/App.swift"))
    }
}

struct HUDDropDestinationTests {
    let project = URL(filePath: "/tmp")

    @Test func anOpenSessioneInFrontTakesTheDrop() {
        let session = Session(id: UUID(), title: "Prova", project: project)
        #expect(HUDDropDestination(sessionInFront: session) == .session(session.id))
    }

    @Test func aSessioneInRevisioneTakesTheDrop() {
        var session = Session(id: UUID(), title: "Prova", project: project)
        session.phase = .inRevisione
        #expect(HUDDropDestination(sessionInFront: session) == .session(session.id))
    }

    @Test func noSessioneInFrontMakesADomanda() {
        #expect(HUDDropDestination(sessionInFront: nil) == .question)
    }

    @Test(arguments: [Session.Phase.archiviata, .fusa])
    func aClosedSessioneInFrontMakesADomanda(phase: Session.Phase) {
        var session = Session(id: UUID(), title: "Prova", project: project)
        session.phase = phase
        #expect(HUDDropDestination(sessionInFront: session) == .question)
    }

    @Test func filesGoByPathAndAddressesAsText() {
        let attachments = HUDDropDestination.attachments(from: [URL(filePath: "/tmp/nota.txt"),
                                                                URL(string: "https://example.com/pagina")!])
        #expect(attachments.map(\.path) == [URL(filePath: "/tmp/nota.txt"), nil])
        #expect(attachments.last?.text == "https://example.com/pagina")
    }

    @MainActor
    @Test func theAllegatiOfASessioneWaitForItsNextTurnAndSurviveARelaunch() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let open = Session(id: UUID(), title: "Aperta", project: project, activity: .ferma)
        var archived = Session(id: UUID(), title: "Archiviata", project: project, activity: .ferma)
        archived.phase = .archiviata
        try JSONEncoder().encode([open, archived]).write(to: file)
        let makeStore = {
            SessionStore(file: file, worktrees: WorktreeManager(root: FileManager.default.temporaryDirectory)) {
                throw CancellationError()
            }
        }
        let store = makeStore()
        let nota = Allegato(name: "nota", text: "Ricorda il test")

        store.attach([nota, nota], to: open.id)
        store.attach([nota], to: archived.id)

        let reloaded = makeStore()
        #expect(reloaded.sessions.first { $0.id == open.id }?.attachments == [nota])
        #expect(reloaded.sessions.first { $0.id == archived.id }?.attachments == [])
        reloaded.detach(nota, from: open.id)
        #expect(reloaded.sessions.first { $0.id == open.id }?.attachments == [])
    }
}
