import Foundation
import Testing
@testable import Bubo

/// Fondi on fake repos made with the real git in a temporary folder: the checkout is the user's, so every test
/// checks what is left of their work.
extension WorktreeManagerTests {
    /// A repo with one commit of `files` and a committer of its own, with a Sessione's worktree on `bubo/prova`.
    func makeSession(files: [String: String]) async throws -> (repo: URL, workspace: Workspace) {
        let repo = try makeRepo("repo", files: files)
        try git("config", "user.name", "Bubo", in: repo)
        try git("config", "user.email", "bubo@example.com", in: repo)
        return (repo, try await manager.prepare(repo, branch: "bubo/prova"))
    }

    func read(_ path: String, in folder: URL) throws -> String {
        try String(contentsOf: folder.appending(path: path), encoding: .utf8)
    }

    func head(of repo: URL) throws -> String {
        try git("rev-parse", "HEAD", in: repo).trimmingCharacters(in: .newlines)
    }

    @Test func aCleanSquashBringsCommittedAndUncommittedWorkAndKeepsTheUsersOtherChanges() async throws {
        let (repo, workspace) = try await makeSession(files: ["a.txt": "a\n", "b.txt": "b\n", "c.txt": "c\n"])
        try write(["a.txt": "a2\n"], in: workspace.folder)
        try git("commit", "-q", "-am", "Agente", in: workspace.folder)
        try write(["nuovo.txt": "n\n", "b.txt": "b2\n"], in: workspace.folder)
        try write(["c.txt": "c-mio\n", "appunti.txt": "mio\n"], in: repo)
        let previous = try head(of: repo)

        let preview = try await manager.mergePreview(of: workspace, into: repo)
        #expect(preview == MergePreview(branch: "main", conflicts: [], dirtyFiles: [], isEmpty: false))
        let merge = try await manager.merge(workspace, into: repo, message: "Prova\n\n- Perché", strategy: .squash)

        #expect(try head(of: repo) == merge.commit)
        #expect(try git("rev-list", "--parents", "-n", "1", "HEAD", in: repo) == "\(merge.commit) \(previous)\n")
        #expect(try git("log", "-1", "--format=%B", in: repo) == "Prova\n\n- Perché\n\n")
        #expect(try read("a.txt", in: repo) == "a2\n")
        #expect(try read("b.txt", in: repo) == "b2\n")
        #expect(try read("nuovo.txt", in: repo) == "n\n")
        #expect(try read("c.txt", in: repo) == "c-mio\n")
        #expect(try read("appunti.txt", in: repo) == "mio\n")
        #expect(try git("status", "--porcelain", in: repo) == " M c.txt\n?? appunti.txt\n")
    }

    @Test func aMergeCommitHasTheSessionsWorkAsSecondParent() async throws {
        let (repo, workspace) = try await makeSession(files: ["a.txt": "a\n"])
        try write(["a.txt": "a2\n"], in: workspace.folder)
        let previous = try head(of: repo)

        let merge = try await manager.merge(workspace, into: repo, message: "Prova", strategy: .mergeCommit)

        let parents = try git("rev-list", "--parents", "-n", "1", "HEAD", in: repo).split(separator: " ")
        #expect(parents.count == 3)
        #expect(parents.first.map(String.init) == merge.commit)
        #expect(parents.dropFirst().first.map(String.init) == previous)
        #expect(try read("a.txt", in: repo) == "a2\n")
    }

    @Test func aConflictIsPredictedWithoutTouchingTheCheckoutAndBlocksTheMerge() async throws {
        let (repo, workspace) = try await makeSession(files: ["a.txt": "a\n", "b.txt": "b\n"])
        try write(["a.txt": "agente\n", "b.txt": "b2\n"], in: workspace.folder)
        try write(["a.txt": "utente\n"], in: repo)
        try git("commit", "-q", "-am", "Utente", in: repo)
        let previous = try head(of: repo)
        let index = try Data(contentsOf: repo.appending(path: ".git/index"))

        let start = ContinuousClock.now
        let preview = try await manager.mergePreview(of: workspace, into: repo)
        let elapsed = ContinuousClock.now - start

        #expect(preview.conflicts == ["a.txt"])
        #expect(preview.obstacle == .conflicts(["a.txt"]))
        #expect(elapsed < .milliseconds(500))
        await #expect(throws: MergeError.conflicts(["a.txt"])) {
            try await manager.merge(workspace, into: repo, message: "Prova", strategy: .squash)
        }
        #expect(try head(of: repo) == previous)
        #expect(try Data(contentsOf: repo.appending(path: ".git/index")) == index)
        #expect(try read("a.txt", in: repo) == "utente\n")
        #expect(try read("b.txt", in: repo) == "b\n")
        #expect(try git("status", "--porcelain", in: repo).isEmpty)
    }

    @Test func unsavedChangesInTheSameFilesBlockTheMergeWithTheirNames() async throws {
        let (repo, workspace) = try await makeSession(files: ["a.txt": "a\n", "b.txt": "b\n"])
        try write(["a.txt": "a2\n", "nuovo.txt": "agente\n"], in: workspace.folder)
        try write(["a.txt": "mio\n", "nuovo.txt": "mio\n"], in: repo)
        let previous = try head(of: repo)

        let preview = try await manager.mergePreview(of: workspace, into: repo)

        #expect(preview.dirtyFiles == ["a.txt", "nuovo.txt"])
        await #expect(throws: MergeError.dirtyCheckout(["a.txt", "nuovo.txt"])) {
            try await manager.merge(workspace, into: repo, message: "Prova", strategy: .squash)
        }
        #expect(try head(of: repo) == previous)
        #expect(try read("a.txt", in: repo) == "mio\n")
        #expect(try read("nuovo.txt", in: repo) == "mio\n")
    }

    @Test func undoPutsTheCheckoutBackExactlyAsItWas() async throws {
        let (repo, workspace) = try await makeSession(files: ["a.txt": "a\n", "b.txt": "b\n", "c.txt": "c\n"])
        try write(["a.txt": "a2\n", "nuovo.txt": "n\n"], in: workspace.folder)
        try write(["b.txt": "b-in-stage\n"], in: repo)
        try git("add", "b.txt", in: repo)
        try write(["c.txt": "c-mio\n", "appunti.txt": "mio\n"], in: repo)
        let previous = try head(of: repo)
        let status = try git("status", "--porcelain", in: repo)
        let staged = try git("diff", "--cached", in: repo)

        let merge = try await manager.merge(workspace, into: repo, message: "Prova", strategy: .squash)
        try await manager.undo(merge)

        #expect(try head(of: repo) == previous)
        #expect(try git("status", "--porcelain", in: repo) == status)
        #expect(try git("diff", "--cached", in: repo) == staged)
        #expect(try read("a.txt", in: repo) == "a\n")
        #expect(!exists("nuovo.txt", in: repo))
        #expect(try read("c.txt", in: repo) == "c-mio\n")
        #expect(try read("appunti.txt", in: repo) == "mio\n")
        #expect(try read("a.txt", in: workspace.folder) == "a2\n")
    }

    @Test func undoIsRefusedOnceTheBranchHasMovedOn() async throws {
        let (repo, workspace) = try await makeSession(files: ["a.txt": "a\n"])
        try write(["a.txt": "a2\n"], in: workspace.folder)
        let merge = try await manager.merge(workspace, into: repo, message: "Prova", strategy: .squash)
        try write(["dopo.txt": "x\n"], in: repo)
        try git("add", "dopo.txt", in: repo)
        try git("commit", "-q", "-m", "Dopo", in: repo)
        let after = try head(of: repo)

        await #expect(throws: MergeError.moved) { try await manager.undo(merge) }
        #expect(try head(of: repo) == after)
        #expect(try read("a.txt", in: repo) == "a2\n")
    }

    @Test func aDetachedCheckoutCannotBeMergedInto() async throws {
        let (repo, workspace) = try await makeSession(files: ["a.txt": "a\n"])
        try git("checkout", "-q", "--detach", in: repo)

        await #expect(throws: MergeError.detachedHead) {
            try await manager.mergePreview(of: workspace, into: repo)
        }
    }

    @MainActor
    @Test func fondiMakesTheSessionFusaAndAnnullaOpensItAgain() async throws {
        let (repo, workspace) = try await makeSession(files: ["a.txt": "a\n"])
        try write(["a.txt": "a2\n"], in: workspace.folder)
        let previous = try head(of: repo)
        var saved = Session(id: UUID(), title: "Prova", project: repo, workspace: workspace, activity: .ferma)
        for hunk in try await manager.changes(in: workspace).flatMap(\.hunks) { saved.decisions[hunk.id] = .accepted }
        let file = base.appending(path: "Sessioni.json")
        try JSONEncoder().encode([saved]).write(to: file)
        let store = SessionStore(file: file, worktrees: manager) { throw CancellationError() }

        try await store.merge(saved.id, message: "Prova", strategy: .squash)

        #expect(store.sessions.first?.phase == .fusa)
        #expect(store.undoDeadlines[saved.id] != nil)
        #expect(try read("a.txt", in: repo) == "a2\n")

        try await store.undoMerge(saved.id)

        #expect(store.sessions.first?.phase == .aperta)
        #expect(store.undoDeadlines.isEmpty)
        #expect(try head(of: repo) == previous)
        #expect(try read("a.txt", in: repo) == "a\n")
    }

    /// Fondi is local git only: on a Progetto with a GitHub remote it works where no `gh` can be found (spec 16).
    @MainActor
    @Test func fondiWorksWithoutGitHubCLI() async throws {
        let (repo, workspace) = try await makeSession(files: ["a.txt": "a\n"])
        try git("remote", "add", "origin", "git@github.com:o/r.git", in: repo)
        try write(["a.txt": "a2\n"], in: workspace.folder)
        let path = ["/usr/bin", "/bin"].map { URL(filePath: $0, directoryHint: .isDirectory) }
        #expect(GitHubCLI(searchPath: path).executable == nil)
        var offline = manager
        offline.shell = LocalShell(environment: ["PATH": "/usr/bin:/bin", "HOME": base.path])
        var saved = Session(id: UUID(), title: "Prova", project: repo, workspace: workspace, activity: .ferma)
        for hunk in try await offline.changes(in: workspace).flatMap(\.hunks) { saved.decisions[hunk.id] = .accepted }
        let file = base.appending(path: "Sessioni.json")
        try JSONEncoder().encode([saved]).write(to: file)
        let store = SessionStore(file: file, worktrees: offline) { throw CancellationError() }

        try await store.merge(saved.id, message: "Prova", strategy: .squash)

        #expect(store.sessions.first?.phase == .fusa)
        #expect(try read("a.txt", in: repo) == "a2\n")
    }

    @MainActor
    @Test func aSessionFusaWhenBuboQuitIsArchived() throws {
        var saved = Session(id: UUID(), title: "Prova", project: base, activity: .ferma, ports: 40_000..<40_010)
        saved.phase = .fusa
        let file = base.appending(path: "Sessioni.json")
        try JSONEncoder().encode([saved]).write(to: file)

        let store = SessionStore(file: file, worktrees: manager) { throw CancellationError() }

        #expect(store.sessions.map(\.phase) == [.archiviata])
        #expect(store.sessions.first?.ports == nil)
    }

    @MainActor
    @Test func fondiRefusesBlocchiNotAccepted() async throws {
        let (repo, workspace) = try await makeSession(files: ["a.txt": "a\n"])
        try write(["a.txt": "a2\n"], in: workspace.folder)
        let saved = Session(id: UUID(), title: "Prova", project: repo, workspace: workspace, activity: .ferma)
        let file = base.appending(path: "Sessioni.json")
        try JSONEncoder().encode([saved]).write(to: file)
        let store = SessionStore(file: file, worktrees: manager) { throw CancellationError() }

        await #expect(throws: MergeError.notAllAccepted) {
            try await store.merge(saved.id, message: "Prova", strategy: .squash)
        }
        #expect(try read("a.txt", in: repo) == "a\n")
    }

    @MainActor
    @Test func fondiOnTheBoardOpensTheRevisioneUntilEveryBloccoIsAccepted() async throws {
        let (repo, workspace) = try await makeSession(files: ["a.txt": "a\n"])
        try write(["a.txt": "a2\n"], in: workspace.folder)
        let saved = Session(id: UUID(), title: "Prova", project: repo, workspace: workspace, activity: .ferma)
        let file = base.appending(path: "Sessioni.json")
        try JSONEncoder().encode([saved]).write(to: file)
        let store = SessionStore(file: file, worktrees: manager) { throw CancellationError() }

        #expect(try await store.boardMerge(of: saved.id) == nil)

        let hunks = try await store.changes(of: saved.id).flatMap(\.hunks).map(\.id)
        store.decide(.accepted, on: hunks, in: saved.id)
        let merge = try #require(try await store.boardMerge(of: saved.id))

        #expect(merge.preview == MergePreview(branch: "main", conflicts: [], dirtyFiles: [], isEmpty: false))
        #expect(merge.message == "Prova")
        #expect(try read("a.txt", in: repo) == "a\n")
    }

    @MainActor
    @Test func fondiOnTheBoardShowsWhyTheDirtyCheckoutRefusesIt() async throws {
        let (repo, workspace) = try await makeSession(files: ["a.txt": "a\n"])
        try write(["a.txt": "a2\n"], in: workspace.folder)
        try write(["a.txt": "mio\n"], in: repo)
        var saved = Session(id: UUID(), title: "Prova", project: repo, workspace: workspace, activity: .ferma)
        for hunk in try await manager.changes(in: workspace).flatMap(\.hunks) { saved.decisions[hunk.id] = .accepted }
        let file = base.appending(path: "Sessioni.json")
        try JSONEncoder().encode([saved]).write(to: file)
        let store = SessionStore(file: file, worktrees: manager) { throw CancellationError() }

        let merge = try #require(try await store.boardMerge(of: saved.id))

        #expect(merge.preview.obstacle == .dirtyCheckout(["a.txt"]))
        #expect(try read("a.txt", in: repo) == "mio\n")
    }
}
