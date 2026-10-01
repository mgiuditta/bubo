import Foundation
import Testing
@testable import Bubo

/// Conflicts resolved by the agent, and Fondi gli accettati, on fake repos: the agent is played by a script or
/// by the test itself, never by `claude`.
extension WorktreeManagerTests {
    /// A Sessione whose `a.txt` conflicts with a commit of the user on `main`, with work also not committed.
    func makeConflict() async throws -> (repo: URL, workspace: Workspace) {
        let (repo, workspace) = try await makeSession(files: ["a.txt": "a\n", "b.txt": "b\n"])
        try write(["a.txt": "agente\n"], in: workspace.folder)
        try git("commit", "-q", "-am", "Agente", in: workspace.folder)
        try write(["b.txt": "b2\n", "nuovo.txt": "n\n"], in: workspace.folder)
        try write(["a.txt": "utente\n"], in: repo)
        try git("commit", "-q", "-am", "Utente", in: repo)
        return (repo, workspace)
    }

    /// A store holding an open Sessione on `workspace` of `repo`, whose turns `bridge` answers.
    @MainActor
    func makeStore(for workspace: Workspace, of repo: URL,
                   bridge: @escaping () async throws -> AgentBridge = { throw CancellationError() }) throws
        -> (SessionStore, UUID) {
        let saved = Session(id: UUID(), title: "Prova", project: repo, workspace: workspace, activity: .ferma)
        let file = base.appending(path: "Sessioni.json")
        try JSONEncoder().encode([saved]).write(to: file)
        return (SessionStore(file: file, worktrees: manager, bridge: bridge), saved.id)
    }

    /// Waits until the conflicts of the Sessione `id` are resolved or put back.
    @MainActor
    func waitForResolution(of id: UUID, in store: SessionStore) async throws {
        while store.sessions.first(where: { $0.id == id })?.resolution != nil {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func theResolutionIsNewBlocchiOnTheBranchBroughtInAndTheCheckoutStaysAsItWas() async throws {
        let (repo, workspace) = try await makeConflict()
        let previous = try head(of: repo)
        let before = Set(try await manager.changes(in: workspace).flatMap(\.hunks).map(\.id))

        let resolution = try await manager.bringIn(repo, into: workspace)
        #expect(resolution.conflicts == ["a.txt"])
        #expect(resolution.branch == "main")
        #expect(try read("a.txt", in: workspace.folder).contains("<<<<<<<"))
        try write(["a.txt": "utente e agente\n"], in: workspace.folder)
        try await manager.conclude(resolution, in: workspace)

        var resolved = workspace
        resolved.base = resolution.incoming
        let files = try await manager.changes(in: resolved)
        #expect(files.map(\.path) == ["a.txt", "b.txt", "nuovo.txt"])
        let resolutionHunk = try #require(files.first?.hunks.first)
        #expect(!before.contains(resolutionHunk.id))
        #expect(resolutionHunk.lines.contains(Hunk.Line(kind: .added, text: "utente e agente")))
        #expect(try await manager.mergePreview(of: resolved, into: repo).conflicts.isEmpty)
        #expect(try head(of: repo) == previous)
        #expect(try read("a.txt", in: repo) == "utente\n")
        #expect(try git("status", "--porcelain", in: repo).isEmpty)
    }

    @Test func markersLeftByTheAgentAreRefusedAndTheWorktreeGoesBackAsItWas() async throws {
        let (repo, workspace) = try await makeConflict()
        let tip = try head(of: workspace.folder)
        let status = try git("status", "--porcelain", in: workspace.folder)

        let resolution = try await manager.bringIn(repo, into: workspace)
        try write(["c.txt": "dell'agente\n"], in: workspace.folder)
        await #expect(throws: MergeError.unresolved(["a.txt"])) {
            try await manager.conclude(resolution, in: workspace)
        }
        try await manager.restore(resolution, in: workspace)

        #expect(try head(of: workspace.folder) == tip)
        #expect(try git("status", "--porcelain", in: workspace.folder) == status)
        #expect(try read("a.txt", in: workspace.folder) == "agente\n")
        #expect(try read("b.txt", in: workspace.folder) == "b2\n")
        #expect(try read("nuovo.txt", in: workspace.folder) == "n\n")
        #expect(!exists("c.txt", in: workspace.folder))
        #expect(!exists("MERGE_HEAD", in: repo.appending(path: ".git/worktrees/bubo-prova")))
        #expect(exists("HEAD", in: repo.appending(path: ".git/worktrees/bubo-prova")))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func aTurnOfTheSessionResolvesTheConflictsAndTheRevisioneShowsTheResolution() async throws {
        let (repo, workspace) = try await makeConflict()
        let file = workspace.folder.appending(path: "a.txt").path
        let (store, id) = try makeStore(for: workspace, of: repo) {
            AgentBridgeTests.bridge(AgentBridgeTests.answering(#"""
                printf 'utente e agente\n' > '\#(file)'
                echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}"
                read _
                """#))
        }

        try await store.resolveConflicts(id)
        #expect(store.sessions.first?.activity == .lavora)
        try await waitForResolution(of: id, in: store)

        let session = try #require(store.sessions.first)
        #expect(session.activity == .ferma)
        #expect(session.workspace?.base == (try head(of: repo)))
        let files = try await store.changes(of: id)
        #expect(files.first?.hunks.first?.lines.contains(Hunk.Line(kind: .added, text: "utente e agente")) == true)
        #expect(try await store.mergePreview(of: id)?.conflicts.isEmpty == true)
        #expect(try read("a.txt", in: repo) == "utente\n")
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func aFailedTurnPutsTheWorktreeBackAndTheSessionInErrore() async throws {
        let (repo, workspace) = try await makeConflict()
        let tip = try head(of: workspace.folder)
        let (store, id) = try makeStore(for: workspace, of: repo)

        try await store.resolveConflicts(id)
        try await waitForResolution(of: id, in: store)

        let session = try #require(store.sessions.first)
        #expect(session.activity == .errore)
        #expect(session.failure == MergeError.unresolved(["a.txt"]).localizedDescription)
        #expect(session.workspace == workspace)
        #expect(try head(of: workspace.folder) == tip)
        #expect(try read("a.txt", in: workspace.folder) == "agente\n")
        #expect(try read("nuovo.txt", in: workspace.folder) == "n\n")
    }

    @MainActor
    @Test func fondiGliAccettatiLeavesTheOtherBlocchiOutOfTheCheckout() async throws {
        let lines = (1...20).map { "riga \($0)\n" }.joined()
        let (repo, workspace) = try await makeSession(files: ["a.txt": lines, "b.txt": "b\n"])
        try write(["a.txt": lines.replacing("riga 2\n", with: "riga due\n").replacing("riga 19\n", with: "riga diciannove\n"),
                   "b.txt": "b2\n", "nuovo.txt": "n\n"], in: workspace.folder)
        let (store, id) = try makeStore(for: workspace, of: repo)
        let files = try await manager.changes(in: workspace)
        let first = try #require(files.first { $0.path == "a.txt" }?.hunks.first)
        let created = try #require(files.first { $0.path == "nuovo.txt" }?.hunks.first)
        store.decide(.accepted, on: [first.id, created.id], in: id)

        try await store.merge(id, message: "Prova", strategy: .squash, discardingRest: true)

        #expect(store.sessions.first?.phase == .fusa)
        #expect(try read("a.txt", in: repo) == lines.replacing("riga 2\n", with: "riga due\n"))
        #expect(try read("b.txt", in: repo) == "b\n")
        #expect(try read("nuovo.txt", in: repo) == "n\n")
        #expect(try git("status", "--porcelain", in: repo).isEmpty)
        #expect(try read("b.txt", in: workspace.folder) == "b2\n")
    }

    @MainActor
    @Test func fondiGliAccettatiNeedsAnAcceptedBlocco() async throws {
        let (repo, workspace) = try await makeSession(files: ["a.txt": "a\n"])
        try write(["a.txt": "a2\n"], in: workspace.folder)
        let (store, id) = try makeStore(for: workspace, of: repo)

        await #expect(throws: MergeError.noneAccepted) {
            try await store.merge(id, message: "Prova", strategy: .squash, discardingRest: true)
        }
        #expect(try read("a.txt", in: repo) == "a\n")
    }
}
