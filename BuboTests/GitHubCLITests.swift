import Foundation
import Testing
@testable import Bubo

/// `GitHubCLI` and ⌘I's start with a fake `gh` in the `PATH`: a script that records its arguments and its environment
/// and answers with fixtures. No request reaches GitHub.
struct GitHubCLITests {
    let folder: URL
    let cli: GitHubCLI
    let repository = GitHubRepository(remote: "git@github.com:o/r.git")!

    init() throws {
        folder = URL(filePath: TrustGate.realPath(FileManager.default.temporaryDirectory.path))
            .appending(path: "GitHubCLITests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = #"""
            #!/bin/sh
            here=$(dirname "$0")
            { printf 'ARGS'; for argument in "$@"; do printf ' %s' "$argument"; done; printf '\n'
              printf 'ENV %s\n' "$(env | sort | tr '\n' ' ')"; } >> "$here/calls.log"
            case "$1 $2" in
                "issue list") cat "$here/list.json" ;;
                "issue view") cat "$here/view.json" ;;
            esac
            exit $(cat "$here/exit" 2>/dev/null || echo 0)
            """#
        let gh = folder.appending(path: "gh")
        try Data(script.utf8).write(to: gh)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gh.path)
        try Data(#"""
            [{"number":42,"title":"Login rotto","labels":[{"id":"L1","name":"bug","description":"","color":"d73a4a"}],
              "updatedAt":"2026-09-30T10:00:00Z","url":"https://github.com/o/r/issues/42"}]
            """#.utf8).write(to: folder.appending(path: "list.json"))
        try Data(#"""
            {"title":"Login rotto","body":"Non entra.\n![schermata](https://x.test/a.png)",
             "comments":[{"author":{"login":"anna"},"body":"Anche a me","createdAt":"2026-09-30T11:00:00Z"}],
             "labels":[{"name":"bug"}],"url":"https://github.com/o/r/issues/42"}
            """#.utf8).write(to: folder.appending(path: "view.json"))
        // The system's folders after the fake, for the tools the script uses: a real `gh` there is never reached.
        cli = GitHubCLI(searchPath: [folder, URL(filePath: "/usr/bin"), URL(filePath: "/bin")],
                        base: ["HOME": "/Users/prova", "GH_TOKEN": "segreto", "USER": "prova"])
    }

    /// The calls the fake `gh` recorded: its arguments and its environment.
    func calls() throws -> [(arguments: String, environment: String)] {
        let file = folder.appending(path: "calls.log")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map(String.init)
        return stride(from: 0, to: lines.count - 1, by: 2).map { (lines[$0], lines[$0 + 1]) }
    }

    /// Checks the rules every call to `gh` keeps: no prompts, never a token, `issue develop` or a fork.
    func expectEveryCallIsSafe() throws {
        for call in try calls() {
            #expect(call.environment.contains("GH_PROMPT_DISABLED=1 "))
            #expect(call.environment.contains("GH_HOST=github.com"))
            #expect(!call.environment.contains("GH_TOKEN"))
            #expect(!call.arguments.contains("auth token"))
            #expect(!call.arguments.contains("issue develop"))
            #expect(!call.arguments.contains("fork"))
        }
    }

    @Test func theOpenIssuesAreListedWithAnExplicitLimitAndTheRepoFromTheRemote() async throws {
        let issues = try await cli.openIssues(of: repository)

        #expect(issues.map(\.number) == [42])
        #expect(issues.first?.labels.map(\.name) == ["bug"])
        let call = try #require(try calls().first)
        #expect(call.arguments == "ARGS issue list --repo github.com/o/r --state open --limit 100 --json number,title,labels,updatedAt,url")
        try expectEveryCallIsSafe()
    }

    @Test func theSearchGoesToGitHub() async throws {
        _ = try await cli.openIssues(of: repository, matching: "  login is:open  ")

        #expect(try calls().first?.arguments.hasSuffix("--search login is:open") == true)
        try expectEveryCallIsSafe()
    }

    @Test func theIssueIsReadWithItsCommentsLabelsAndURL() async throws {
        let context = try await cli.context(ofIssue: 42, in: repository)

        #expect(context.title == "Login rotto")
        #expect(context.comments.first?.author?.login == "anna")
        #expect(try calls().first?.arguments == "ARGS issue view 42 --repo github.com/o/r --json title,body,comments,labels,url")
        try expectEveryCallIsSafe()
    }

    @Test func aMissingLoginIsRecognisedFromTheExitCode() async throws {
        try Data("4".utf8).write(to: folder.appending(path: "exit"))

        await #expect(throws: GitHubCLIError.notAuthenticated(host: "github.com")) {
            try await cli.openIssues(of: repository)
        }
        #expect(GitHubCLIError.notAuthenticated(host: "github.com").errorDescription?.contains("gh auth login") == true)
        try expectEveryCallIsSafe()
    }

    @Test func anotherFailureSaysWhat() async throws {
        try Data("1".utf8).write(to: folder.appending(path: "exit"))

        await #expect(throws: GitHubCLIError.failed("")) { try await cli.openIssues(of: repository) }
    }

    @Test func withoutGhNothingRunsAndTheMessageSaysHowToInstallIt() async throws {
        let empty = folder.appending(path: "vuota", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let missing = GitHubCLI(searchPath: [empty])

        #expect(missing.executable == nil)
        await #expect(throws: GitHubCLIError.missing) { try await missing.openIssues(of: repository) }
        #expect(GitHubCLIError.missing.errorDescription?.contains("brew install gh") == true)
        #expect(try calls().isEmpty)
    }

    @Test func makingTheCLIRunsNothing() throws {
        _ = GitHubCLI(searchPath: [folder])
        #expect(try calls().isEmpty)
    }

    @Test func theRepoComesFromOriginBeforeTheOtherRemotes() async throws {
        let repo = folder.appending(path: "repo", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try Self.git(["init", "-q"], in: repo)
        await #expect(throws: GitHubCLIError.noGitHubRemote) { try await cli.repository(of: repo) }

        try Self.git(["remote", "add", "fork", "git@github.com:altro/r.git"], in: repo)
        try Self.git(["remote", "add", "origin", "https://ghe.example.com/team/app.git"], in: repo)

        #expect(try await cli.repository(of: repo).argument == "ghe.example.com/team/app")
    }

    static func git(_ arguments: [String], in folder: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", folder.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
    }

    @MainActor
    @Test func anIssueStartsASessionTitledLikeItWithItsTextAsMaterial() async throws {
        let file = folder.appending(path: "Sessioni.json")
        let project = folder.appending(path: "progetto", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: folder.appending(path: "Worktrees"))) {
            throw CancellationError()
        }

        store.start(issue: 42, try await cli.context(ofIssue: 42, in: repository), in: project)

        let session = try #require(store.sessions.first)
        #expect(session.title == "Login rotto")
        #expect(session.issue == .github(42))
        #expect(session.branchToPrepare == "bubo/42-login-rotto")
        #expect(session.prompt?.contains("BEGIN ISSUE-") == true)
        #expect(session.prompt?.contains("[\(String(localized: "immagine")) schermata](https://x.test/a.png)") == true)
        #expect(IssueLink.github(42).match(in: store.sessions, on: project) == .open(session))
        try expectEveryCallIsSafe()
    }

    @MainActor
    @Test func riprendiReopensTheArchivedSessionWithTheIssueReadAgain() async throws {
        let file = folder.appending(path: "Sessioni.json")
        var archived = Session(id: UUID(), title: "Login rotto", project: folder, activity: .ferma)
        archived.issue = .github(42)
        archived.phase = .archiviata
        archived.prompt = "vecchio"
        try JSONEncoder().encode([archived]).write(to: file)
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: folder.appending(path: "Worktrees"))) {
            throw CancellationError()
        }

        try store.reopen(archived.id, prompt: try await cli.context(ofIssue: 42, in: repository).prompt(number: 42))

        let session = try #require(store.sessions.first)
        #expect(store.sessions.count == 1)
        #expect(session.phase == .aperta)
        #expect(session.activity == .lavora)
        #expect(session.prompt?.contains("Login rotto") == true)
        #expect(session.ports != nil)
    }

    @MainActor
    @Test func riprendiLeavesAnOpenSessionAlone() throws {
        let file = folder.appending(path: "Sessioni.json")
        var open = Session(id: UUID(), title: "Login rotto", project: folder, activity: .ferma)
        open.prompt = "vecchio"
        try JSONEncoder().encode([open]).write(to: file)
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: folder)) { throw CancellationError() }

        try store.reopen(open.id, prompt: "nuovo")

        #expect(store.sessions.first?.prompt == "vecchio")
    }
}
