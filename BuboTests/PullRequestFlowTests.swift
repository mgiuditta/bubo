import Foundation
import Testing
@testable import Bubo

/// Apri PR on a fake repo whose remote looks like GitHub and is a local bare repo, with a fake `gh` in the `PATH`
/// that records its arguments: no request reaches GitHub and no real pull request is opened.
extension WorktreeManagerTests {
    /// A Sessione's repo with a GitHub-looking `origin` whose pushes land in the bare repo `remote.git`, and a fake
    /// `gh` that says `main` is the default branch and prints a pull request's URL.
    func makePullRequestSession(startingOn branch: String = "main", remote: String? = nil) async throws
        -> (repo: URL, remote: URL, workspace: Workspace, cli: GitHubCLI) {
        let repo = try makeRepo("repo", files: ["a.txt": "a\n"])
        try git("config", "user.name", "Bubo", in: repo)
        try git("config", "user.email", "bubo@example.com", in: repo)
        if branch != "main" { try git("checkout", "-q", "-b", branch, in: repo) }
        let bare = base.appending(path: "remote.git", directoryHint: .isDirectory)
        try git("init", "-q", "--bare", bare.path, in: base)
        try git("remote", "add", "origin", "https://github.com/o/r.git", in: repo)
        try git("config", "url.\(remote ?? bare.path).pushInsteadOf", "https://github.com/o/r.git", in: repo)
        let workspace = try await manager.prepare(repo, branch: "bubo/42-login")
        try write(["a.txt": "a2\n"], in: workspace.folder)
        try git("commit", "-q", "-am", "Agente", in: workspace.folder)
        try write(["nuovo.txt": "n\n"], in: workspace.folder)
        return (repo, bare, workspace, try makeFakeGitHubCLI())
    }

    func makeFakeGitHubCLI() throws -> GitHubCLI {
        let folder = base.appending(path: "gh", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = #"""
            #!/bin/sh
            here=$(dirname "$0")
            { printf 'ARGS'; for argument in "$@"; do printf ' %s' "$(printf '%s' "$argument" | tr '\n' '|')"; done; printf '\n'
              printf 'ENV %s\n' "$(env | sort | tr '\n' ' ')"; } >> "$here/calls.log"
            case "$1 $2" in
                "repo view") echo main ;;
                "pr view") cat "$here/pr.json" ;;
                "run view") printf 'build\tRun tests\tline 1\nbuild\tRun tests\terror: test failed\n' ;;
                "pr create")
                    case "$*" in
                        *--dry-run*) echo "Would have created a Pull Request with:" ;;
                        *) echo "https://github.com/o/r/pull/7" ;;
                    esac ;;
            esac
            """#
        let gh = folder.appending(path: "gh")
        try Data(script.utf8).write(to: gh)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gh.path)
        return GitHubCLI(searchPath: [folder, URL(filePath: "/usr/bin"), URL(filePath: "/bin")],
                         base: ["HOME": base.path, "USER": "prova"])
    }

    /// The arguments of each call to the fake `gh`, and whether every call kept its rules.
    func ghCalls() throws -> [String] {
        let file = base.appending(path: "gh/calls.log")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map(String.init)
        for environment in lines.filter({ $0.hasPrefix("ENV ") }) {
            #expect(environment.contains("GH_PROMPT_DISABLED=1 "))
        }
        let calls = lines.filter { $0.hasPrefix("ARGS ") }
        #expect(!calls.contains { $0.contains("fork") || $0.contains("issue develop") || $0.contains("auth token") })
        return calls
    }

    func remoteBranches(of bare: URL) throws -> String {
        try git("for-each-ref", "--format=%(refname)", "refs/heads", in: bare)
    }

    @Test func theTargetIsTheBranchTheSessionStartedFromAndNothingIsPushedBeforeCreaPR() async throws {
        let (repo, bare, workspace, cli) = try await makePullRequestSession()
        let flow = PullRequestFlow(cli: cli, worktrees: manager)

        let target = try await flow.target(of: workspace, in: repo)
        let preview = try await flow.preview(PullRequestText(title: "Login", description: "Sistema il login."),
                                             closing: .github(42), isDraft: false, to: target)

        #expect(workspace.baseBranch == "main")
        #expect(target == PullRequestFlow.Target(remote: "origin", repository: GitHubRepository(remote: "https://github.com/o/r")!,
                                                 head: "bubo/42-login", base: "main", defaultBranch: "main",
                                                 isBaseAssumed: false))
        #expect(target.isIntoDefaultBranch)
        #expect(preview.contains("Would have created"))
        #expect(try ghCalls().last?.hasSuffix("--dry-run") == true)
        #expect(try remoteBranches(of: bare).isEmpty)
    }

    @Test func creaPRSquashesPushesAndOpensThePullRequestWithTheClosingLine() async throws {
        let (repo, bare, workspace, cli) = try await makePullRequestSession()
        let flow = PullRequestFlow(cli: cli, worktrees: manager)
        let target = try await flow.target(of: workspace, in: repo)

        let link = try await flow.open(PullRequestText(title: "Sistema il login", description: "- Corregge il token."),
                                       closing: .github(42), isDraft: false, from: workspace, to: target)

        #expect(link.number == 7)
        #expect(link.url.absoluteString == "https://github.com/o/r/pull/7")
        #expect(try remoteBranches(of: bare) == "refs/heads/bubo/42-login\n")
        let base = try #require(workspace.base)
        #expect(try git("rev-list", "--parents", "-n", "1", "refs/heads/bubo/42-login", in: bare)
            .hasSuffix(" \(base)\n"))
        #expect(try git("show", "refs/heads/bubo/42-login:nuovo.txt", in: bare) == "n\n")
        #expect(try git("status", "--porcelain", in: workspace.folder).isEmpty)
        #expect(try git("rev-parse", "--abbrev-ref", "bubo/42-login@{upstream}", in: workspace.folder) == "origin/bubo/42-login\n")
        let create = try #require(try ghCalls().last)
        #expect(create.contains("pr create --repo github.com/o/r --head bubo/42-login --base main"))
        #expect(create.contains("--body - Corregge il token.||Closes #42"))
        #expect(!create.contains("--draft"))
    }

    @Test func aBaseOtherThanTheDefaultBranchIsWarnedAbout() async throws {
        let (repo, _, workspace, cli) = try await makePullRequestSession(startingOn: "sviluppo")

        let target = try await PullRequestFlow(cli: cli, worktrees: manager).target(of: workspace, in: repo)

        #expect(target.base == "sviluppo")
        #expect(!target.isIntoDefaultBranch)
    }

    @Test func aSessionSavedWithoutItsStartingBranchTargetsTheDefaultOneAndSaysSo() async throws {
        var (repo, _, workspace, cli) = try await makePullRequestSession()
        workspace.baseBranch = nil

        let target = try await PullRequestFlow(cli: cli, worktrees: manager).target(of: workspace, in: repo)

        #expect(target.base == "main")
        #expect(target.isBaseAssumed)
    }

    @Test func aRefusedPushStopsBeforeThePullRequestAndNeverForks() async throws {
        let (repo, _, workspace, cli) = try await makePullRequestSession(remote: base.appending(path: "assente.git").path)
        let flow = PullRequestFlow(cli: cli, worktrees: manager)
        let target = try await flow.target(of: workspace, in: repo)

        await #expect {
            _ = try await flow.open(PullRequestText(title: "Login", description: ""), closing: nil, isDraft: true,
                                    from: workspace, to: target)
        } throws: { error in
            if case PullRequestError.pushRefused = error { true } else { false }
        }
        #expect(try ghCalls().allSatisfy { !$0.contains("pr create") })
    }

    @Test func withoutGitHubCLIThereIsNoTarget() async throws {
        let (repo, _, workspace, _) = try await makePullRequestSession()
        let cli = GitHubCLI(searchPath: [base.appending(path: "vuota", directoryHint: .isDirectory)])

        await #expect(throws: GitHubCLIError.missing) {
            _ = try await PullRequestFlow(cli: cli, worktrees: manager).target(of: workspace, in: repo)
        }
    }

    @Test func creaPRMakesTheSessionInRevisioneInPRAperta() async throws {
        let (repo, _, workspace, cli) = try await makePullRequestSession()
        var session = Session(id: UUID(), title: "Sistema il login", project: repo, workspace: workspace, activity: .ferma)
        session.issue = .github(42)
        let file = base.appending(path: "Sessioni.json")
        try JSONEncoder().encode([session]).write(to: file)
        let store = SessionStore(file: file, worktrees: manager) { throw CancellationError() }

        let (target, rejected) = try await store.pullRequestTarget(of: session.id, with: cli)
        try await store.openPullRequest(of: session.id, PullRequestText(title: "Sistema il login", description: ""),
                                        isDraft: true, to: target, with: cli)

        let opened = try #require(store.sessions.first)
        #expect(rejected == 0)
        #expect(opened.phase == .inRevisione)
        #expect(opened.pullRequest?.number == 7)
        #expect(BoardColumn(opened, at: .now) == .prAperta)
        #expect(try ghCalls().last?.contains("--draft") == true)
    }
}

/// The text of Apri PR: the line that closes the issue is always Bubo's.
struct PullRequestTextTests {
    @Test func theClosingLineIsAddedOnceForEachSource() {
        let text = PullRequestText(title: "Login", description: "Sistema il login.")

        #expect(text.body(closing: .github(42)) == "Sistema il login.\n\nCloses #42")
        #expect(text.body(closing: .linear("ENG-123")) == "Sistema il login.\n\nFixes ENG-123")
        #expect(PullRequestText(title: "", description: "closes #42").body(closing: .github(42)) == "closes #42")
        #expect(PullRequestText(title: "", description: "").body(closing: .github(42)) == "Closes #42")
        #expect(text.body(closing: nil) == "Sistema il login.")
    }

    @Test func aModelsAnswerGivesTitleAndDescription() throws {
        let text = try #require(PullRequestText(answer: "**Titolo: Sistema il login**\n\n- Corregge il token.\n"))

        #expect(text.title == "Sistema il login")
        #expect(text.description == "- Corregge il token.")
        #expect(PullRequestText(answer: "  \n") == nil)
    }

    @Test func withoutAModelTheTextHasTheTitleTheSummaryAndThePerché() {
        let text = PullRequestText(title: "Login", summary: SessionSummary(done: ["Fatto il login."]),
                                   reasons: ["Il token scadeva.", "Il token scadeva."])

        #expect(text.title == "Login")
        #expect(text.description.contains("- Fatto il login."))
        #expect(text.description.hasSuffix("## Perché\n\n- Il token scadeva."))
    }

    @Test func theURLGHPrintsIsThePullRequest() {
        let link = PullRequestLink(url: "Creating pull request\nhttps://github.com/o/r/pull/12\n", base: "main")

        #expect(link?.number == 12)
        #expect(link?.label == "PR #12")
        #expect(PullRequestLink(url: "https://github.com/o/r/issues/12", base: "main") == nil)
    }
}
