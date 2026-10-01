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
        #expect(store.projects == [URL(filePath: "/tmp")])
    }
}
