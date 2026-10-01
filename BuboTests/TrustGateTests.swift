import Foundation
import Testing
@testable import Bubo

struct TrustGateTests {
    /// A folder of its own under the temporary directory, with a `TrustGate` reading `.claude.json` there.
    let base: URL
    let gate: TrustGate

    init() throws {
        base = URL(filePath: TrustGate.realPath(FileManager.default.temporaryDirectory.path))
            .appending(path: "TrustGateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        gate = TrustGate(configuration: base.appending(path: ".claude.json"))
    }

    func folder(_ path: String) throws -> URL {
        let url = base.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func writeConfiguration(_ json: String) throws {
        try Data(json.utf8).write(to: gate.configuration)
    }

    func configuration() throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: gate.configuration)) as? NSDictionary)
    }

    /// A repo at `main` with a worktree at `worktree`, laid out as `git worktree add` leaves them.
    func makeWorktree(of main: URL, at worktree: URL) throws {
        let admin = main.appending(path: ".git/worktrees/w", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: admin, withIntermediateDirectories: true)
        try Data("../..\n".utf8).write(to: admin.appending(path: "commondir"))
        try Data("gitdir: \(admin.path)\n".utf8).write(to: worktree.appending(path: ".git"))
    }

    @Test func aFolderIsNotTrustedWithoutTheFileOrTheKey() throws {
        let repo = try folder("repo")
        #expect(!gate.isTrusted(repo))
        #expect(gate.settingSources(for: repo) == ["user"])
        try writeConfiguration(#"{"projects":{"\#(repo.path)":{"allowedTools":[]}}}"#)
        #expect(!gate.isTrusted(repo))
    }

    @Test func aFolderTrustedByTheCLIIsTrusted() throws {
        let repo = try folder("repo")
        try writeConfiguration(#"{"projects":{"\#(repo.path)":{"hasTrustDialogAccepted":true}}}"#)
        #expect(gate.isTrusted(repo))
        #expect(gate.settingSources(for: repo) == ["user", "project", "local"])
    }

    @Test func trustChangesOnlyItsKey() throws {
        let repo = try folder("repo")
        try writeConfiguration(#"""
            {"numStartups": 41, "oauthAccount": {"emailAddress": "u@example.com"}, "futureKey": [1, 2.5, null, false],
             "projects": {"/elsewhere": {"hasTrustDialogAccepted": true}, "\#(repo.path)": {"allowedTools": ["Bash"], "unknown": {"a": 1}}}}
            """#)
        let before = try configuration().mutableCopy() as! NSMutableDictionary

        try gate.trust(repo)

        let projects = try #require(before["projects"] as? NSDictionary).mutableCopy() as! NSMutableDictionary
        let project = try #require(projects[repo.path] as? NSDictionary).mutableCopy() as! NSMutableDictionary
        project["hasTrustDialogAccepted"] = true
        projects[repo.path] = project
        before["projects"] = projects
        #expect(try configuration() == before)
        #expect(gate.isTrusted(repo))
        let permissions = try FileManager.default.attributesOfItem(atPath: gate.configuration.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func trustCreatesTheFileWhenMissing() throws {
        let repo = try folder("repo")
        try gate.trust(repo)
        #expect(gate.isTrusted(repo))
    }

    @Test func revokeTurnsTheTrustOff() throws {
        let repo = try folder("repo")
        try gate.trust(repo)
        try gate.revoke(repo)
        #expect(!gate.isTrusted(repo))
        let projects = try #require(try configuration()["projects"] as? NSDictionary)
        #expect((projects[repo.path] as? NSDictionary)?["hasTrustDialogAccepted"] as? Bool == false)
    }

    @Test func anUnreadableFileIsLeftAlone() throws {
        let repo = try folder("repo")
        try writeConfiguration("{ not json")
        #expect(throws: TrustGateError.unreadableConfiguration) { try gate.trust(repo) }
        #expect(try String(contentsOf: gate.configuration, encoding: .utf8) == "{ not json")
        #expect(!gate.isTrusted(repo))
    }

    @Test func theRootOfAWorktreeIsTheMainCheckout() throws {
        let main = try folder("main")
        let worktree = try folder("worktrees/w")
        try makeWorktree(of: main, at: worktree)
        #expect(TrustGate.root(of: worktree) == main.path)
        #expect(TrustGate.root(of: try folder("worktrees/w/Sources")) == main.path)
        #expect(TrustGate.root(of: try folder("main/Sources")) == main.path)
    }

    @Test func onlyAWorktreeHasAMainCheckoutToReadSettingsFrom() throws {
        let main = try folder("main")
        let worktree = try folder("worktrees/w")
        try makeWorktree(of: main, at: worktree)
        #expect(TrustGate.mainCheckout(ofWorktree: worktree) == main.path)
        #expect(TrustGate.mainCheckout(ofWorktree: try folder("worktrees/w/Sources")) == main.path)
        #expect(TrustGate.mainCheckout(ofWorktree: try folder("main/Sources")) == nil)
        #expect(TrustGate.mainCheckout(ofWorktree: try folder("notes")) == nil)
    }

    @Test func aWorktreeOfATrustedProjectIsTrusted() throws {
        let main = try folder("main")
        let worktree = try folder("worktrees/w")
        try makeWorktree(of: main, at: worktree)
        try gate.trust(main)
        #expect(gate.isTrusted(worktree))
        try gate.revoke(worktree)
        #expect(!gate.isTrusted(main))
    }

    @Test func outsideGitATrustedParentCounts() throws {
        let parent = try folder("notes")
        try gate.trust(parent)
        #expect(gate.isTrusted(try folder("notes/inner")))
        #expect(!gate.isTrusted(try folder("other")))
    }

    @Test func insideARepoATrustedParentAboveTheRepoDoesNotCount() throws {
        let parent = try folder("dev")
        let repo = try folder("dev/repo/.git").deletingLastPathComponent()
        try gate.trust(parent)
        #expect(!gate.isTrusted(repo))
    }

    @Test func theRootIsARealPath() throws {
        let repo = try folder("repo")
        let link = base.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repo)
        #expect(TrustGate.root(of: link) == repo.path)
    }
}

struct RepoActivationsTests {
    @Test func anEmptyFolderActivatesNothing() {
        #expect(RepoActivations(folder: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)).isEmpty)
    }

    @Test func everythingTheRepoWouldTurnOnIsListed() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "RepoActivations-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appending(path: ".claude"), withIntermediateDirectories: true)
        try Data(#"""
            {"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "./setup.sh"}]}]},
             "env": {"B": "2", "A": "1"}, "apiKeyHelper": "./key.sh",
             "permissions": {"allow": ["Bash(npm test:*)"], "additionalDirectories": ["../shared"], "deny": ["Read"]}}
            """#.utf8).write(to: folder.appending(path: ".claude/settings.json"))
        try Data(#"{"env": {"C": "3"}}"#.utf8).write(to: folder.appending(path: ".claude/settings.local.json"))
        try Data(#"""
            {"mcpServers": {"db": {"command": "npx", "args": ["-y", "mcp-db"]}, "web": {"type": "http", "url": "https://x.example"}}}
            """#.utf8).write(to: folder.appending(path: ".mcp.json"))

        #expect(RepoActivations(folder: folder) == RepoActivations(
            hooks: ["SessionStart: ./setup.sh"], environment: ["A", "B", "C"], apiKeyHelper: "./key.sh",
            mcpServers: ["db: npx -y mcp-db", "web: https://x.example"],
            allowRules: ["Bash(npm test:*)"], additionalDirectories: ["../shared"]))
    }

    @Test(arguments: [
        ("rm -rf ~\n# innocuo", #"rm -rf ~\n# innocuo"#),
        ("safe\u{202E}hs.lave", #"safe\u{202E}hs.lave"#),
        ("a\u{200B}b\u{7}c\td", #"a\u{200B}b\u{7}c\td"#),
        (#"C:\path"#, #"C:\\path"#),
        ("è ok 🦉", "è ok 🦉"),
    ])
    func untrustedTextIsEscaped(text: String, shown: String) {
        #expect(RepoActivations.escaped(text) == shown)
    }

    @Test func namesFromTheRepoAreEscaped() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "RepoActivations-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"mcpServers": {"ok\u202e": {"command": "evil\ncmd"}}}"#.utf8).write(to: folder.appending(path: ".mcp.json"))
        #expect(RepoActivations(folder: folder).mcpServers == [#"ok\u{202E}: evil\ncmd"#])
    }
}
