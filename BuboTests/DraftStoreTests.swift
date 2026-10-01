import Foundation
import Testing
@testable import Bubo

/// The Bozze outlive a restart, and Avvia turns one into a Sessione in Aperta · Lavora.
@MainActor
struct DraftStoreTests {
    @Test func theBozzeAreThereAfterARestart() {
        let file = FileManager.default.temporaryDirectory.appending(path: "Bozze-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let draft = Draft(title: "Esporta in CSV", text: "Dal menu File", project: URL(filePath: "/tmp"))
        let gone = Draft(title: "Tolta", text: "", project: URL(filePath: "/tmp"))
        let store = DraftStore(file: file)
        store.add(draft)
        store.add(gone)
        store.remove(gone.id)

        #expect(DraftStore(file: file).drafts == [draft])
    }

    @Test func titleAndTextAreThePrompt() {
        let project = URL(filePath: "/tmp")
        #expect(Draft(title: "Esporta in CSV", text: "Dal menu File", project: project).prompt
                == "Esporta in CSV\n\nDal menu File")
        #expect(Draft(title: "Esporta in CSV", text: "", project: project).prompt == "Esporta in CSV")
    }

    @Test func avviaStartsASessioneInLavoraAndRemovesTheBozza() throws {
        let project = FileManager.default.temporaryDirectory.appending(path: "bubo-bozza-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }
        let store = makeStore()
        let draft = Draft(title: "Esporta in CSV", text: "Dal menu File", project: project)
        store.drafts.add(draft)

        store.start(draft)

        let session = try #require(store.sessions.first)
        #expect(session.title == "Esporta in CSV")
        #expect(session.prompt == "Esporta in CSV\n\nDal menu File")
        #expect(session.phase == .aperta)
        #expect(session.activity == .lavora)
        #expect(BoardColumn(session, at: .now) == .lavora)
        #expect(store.drafts.drafts.isEmpty)
    }

    @Test func aBozzaOfAProgettoNotReachableDoesNotStart() {
        let gone = URL(filePath: "/tmp/bubo-sparito-\(UUID().uuidString)")
        let store = makeStore()
        let draft = Draft(title: "Esporta in CSV", text: "", project: gone)
        store.drafts.add(draft)

        store.start(draft)

        #expect(draft.unreachableReason?.contains(gone.path) == true)
        #expect(store.sessions.isEmpty)
        #expect(store.drafts.drafts == [draft])
    }

    /// A store kept in a new temporary file, with its Bozze only in memory.
    private func makeStore() -> SessionStore {
        let file = FileManager.default.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
        return SessionStore(file: file, worktrees: WorktreeManager(root: FileManager.default.temporaryDirectory)) {
            throw CancellationError()
        }
    }
}
