import Foundation
import Testing
@testable import Bubo

/// After the pull request, on a fake repo whose remote is a local bare repo and with a fake `gh` that answers
/// `gh pr view` from a file: the readings, Correggi, Aggiorna PR, merged and closed.
extension WorktreeManagerTests {
    /// A Sessione In revisione whose pull request #7 was opened on the fake remote, with `gh pr view` answering `pr`.
    func makeSessionInRevisione(answering pr: String) async throws
        -> (store: SessionStore, session: Session, bare: URL, workspace: Workspace) {
        let (repo, bare, workspace, cli) = try await makePullRequestSession()
        let flow = PullRequestFlow(cli: cli, worktrees: manager)
        let target = try await flow.target(of: workspace, in: repo)
        let link = try await flow.open(PullRequestText(title: "Login", description: ""), closing: .github(42),
                                       isDraft: false, from: workspace, to: target)
        try Data(pr.utf8).write(to: base.appending(path: "gh/pr.json"))
        var session = Session(id: UUID(), title: "Login", project: repo, workspace: workspace, activity: .ferma)
        session.phase = .inRevisione
        session.pullRequest = link
        let file = base.appending(path: "Sessioni.json")
        try JSONEncoder().encode([session]).write(to: file)
        let store = SessionStore(file: file, worktrees: manager) { throw CancellationError() }
        store.pullRequests.cli = cli
        return (store, session, bare, workspace)
    }

    static let failedActionsCheck = #"""
        {"state":"OPEN","mergedAt":null,"url":"https://github.com/o/r/pull/7","statusCheckRollup":[
          {"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"FAILURE",
           "detailsUrl":"https://github.com/o/r/actions/runs/5/job/99","workflowName":"CI"},
          {"__typename":"StatusContext","context":"vercel","state":"PENDING","targetUrl":"https://vercel.com/x"}]}
        """#

    @Test func withoutAPullRequestInRevisioneAReadingRunsNoGH() async throws {
        let (_, _, _, cli) = try await makePullRequestSession()
        let file = base.appending(path: "Sessioni.json")
        let store = SessionStore(file: file, worktrees: manager) { throw CancellationError() }
        store.pullRequests.cli = cli

        await store.readPullRequests()

        #expect(try ghCalls().isEmpty)
    }

    @Test func inTheBackgroundNothingIsRead() async throws {
        let (store, _, _, _) = try await makeSessionInRevisione(answering: Self.failedActionsCheck)

        store.followPullRequests(isForeground: false)

        #expect(!store.pullRequests.isPolling)
        store.followPullRequests(isForeground: true)
        #expect(store.pullRequests.isPolling)
        store.followPullRequests(isForeground: false)
        #expect(!store.pullRequests.isPolling)
    }

    @Test func anOpenPullRequestKeepsItsChecksAndWhetherTheSessionIsAhead() async throws {
        let (store, session, _, workspace) = try await makeSessionInRevisione(answering: Self.failedActionsCheck)

        await store.readPullRequests()
        let read = try #require(store.pullRequests.statuses[session.id])
        try write(["altro.txt": "x\n"], in: workspace.folder)
        await store.readPullRequests()

        #expect(read.failedChecks.map(\.name) == ["test"])
        #expect(read.failedChecks.first?.jobID == 99)
        #expect(!read.isBehind)
        #expect(store.pullRequests.statuses[session.id]?.isBehind == true)
        #expect(store.sessions.first?.phase == .inRevisione)
        #expect(try ghCalls().last?.contains("pr view 7 --repo github.com/o/r --json state,mergedAt,statusCheckRollup,url") == true)
    }

    @Test func aggiornaPRPushesTheNewWorkAndNothingIsPushedBeforeIt() async throws {
        let (store, session, bare, workspace) = try await makeSessionInRevisione(answering: Self.failedActionsCheck)
        let pushed = try git("rev-parse", "refs/heads/bubo/42-login", in: bare)
        try write(["altro.txt": "x\n"], in: workspace.folder)

        await store.readPullRequests()
        #expect(try git("rev-parse", "refs/heads/bubo/42-login", in: bare) == pushed)
        try await store.updatePullRequest(of: session.id)

        #expect(try git("show", "refs/heads/bubo/42-login:altro.txt", in: bare) == "x\n")
        #expect(store.pullRequests.statuses[session.id]?.isBehind == false)
        #expect(try await !PullRequestFlow(cli: store.pullRequests.cli, worktrees: manager).isBehind(workspace))
    }

    @Test func correggiAsksGitHubTheFailedLogAndStartsATurn() async throws {
        let (store, session, _, _) = try await makeSessionInRevisione(answering: Self.failedActionsCheck)
        await store.readPullRequests()

        await store.fixChecks(of: session.id)

        #expect(try ghCalls().contains { $0.contains("run view --job 99 --log-failed --repo github.com/o/r") })
        // Lavora, or Errore once the fake bridge refuses the turn: no longer Ferma.
        #expect(store.sessions.first?.activity != .ferma)
    }

    @Test func aMergedPullRequestMakesTheSessionFusaThenArchiviata() async throws {
        let (store, session, _, _) = try await makeSessionInRevisione(answering: #"""
            {"state":"MERGED","mergedAt":"2026-10-02T08:00:00Z","url":"https://github.com/o/r/pull/7","statusCheckRollup":[]}
            """#)
        var phases: [Session.Phase] = []
        store.onPhaseChange = { _, phase in phases.append(phase) }

        await store.readPullRequests()

        let merged = try #require(store.sessions.first { $0.id == session.id })
        #expect(phases == [.fusa])
        #expect(merged.phase == .archiviata)
        #expect(merged.mergedAt == (try Date("2026-10-02T08:00:00Z", strategy: .iso8601)))
        #expect(BoardColumn(phase: merged.phase, activity: merged.activity, mergedAt: merged.mergedAt,
                            now: try #require(merged.mergedAt).addingTimeInterval(60)) == .fusa)
    }

    @Test func aClosedPullRequestMakesTheSessionApertaWithANote() async throws {
        let (store, session, _, _) = try await makeSessionInRevisione(answering: #"""
            {"state":"CLOSED","mergedAt":null,"url":"https://github.com/o/r/pull/7","statusCheckRollup":[]}
            """#)

        await store.readPullRequests()

        let closed = try #require(store.sessions.first { $0.id == session.id })
        #expect(closed.phase == .aperta)
        #expect(closed.activity == .ferma)
        #expect(closed.pullRequest == nil)
        #expect(closed.summary?.contains("#7") == true)
        #expect(BoardColumn(closed, at: .now) == .daGuardare)
        #expect(store.pullRequests.statuses[session.id] == nil)
    }
}

/// The checks of `gh pr view` and the turn of Correggi.
struct PullRequestCheckTests {
    @Test func theRollupGivesEachCheckItsOutcome() throws {
        let pullRequest = try JSONDecoder().decode(GitHubPullRequest.self, from: Data(WorktreeManagerTests.failedActionsCheck.utf8))

        #expect(pullRequest.state == .open)
        #expect(pullRequest.mergedAt == nil)
        #expect(pullRequest.checks.map(\.outcome) == [.failed, .pending])
        #expect(pullRequest.checks.map(\.name) == ["test", "vercel"])
        #expect(pullRequest.checks.map(\.jobID) == [99, nil])
    }

    @Test func correggiSendsTheEndOfTheLogAsDataWithoutSecrets() {
        let log = (1...200).map { "riga \($0)" }.joined(separator: "\n") + "\ntoken ghp_abcdefghijklmnopqrstuvwxyz0123456789"
        let prompt = PullRequestFlow.fixPrompt(forPullRequest: 7, failures: [
            (PullRequestCheck(name: "test", outcome: .failed), log),
            (PullRequestCheck(name: "vercel", outcome: .failed, link: URL(string: "https://vercel.com/x")), nil),
        ])

        #expect(prompt.contains("PR #7"))
        #expect(prompt.contains("## test"))
        #expect(!prompt.contains("riga 50\n"))
        #expect(prompt.contains("riga 200"))
        #expect(!prompt.contains("ghp_abcdefghijklmnopqrstuvwxyz0123456789"))
        #expect(prompt.contains("https://vercel.com/x"))
    }

    @Test func theChecksSummaryCountsWhatMatters() {
        let checks = [PullRequestCheck(name: "a", outcome: .passed), PullRequestCheck(name: "b", outcome: .skipped)]

        #expect(PullRequestBadge.checksSummary(of: checks)?.symbol == "checkmark.circle.fill")
        #expect(PullRequestBadge.checksSummary(of: [PullRequestCheck(name: "b", outcome: .skipped)]) == nil)
    }
}
