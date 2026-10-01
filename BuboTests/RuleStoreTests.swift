import Foundation
import Testing
@testable import Bubo

struct ProjectRuleTests {
    static func rule(_ tool: String, command: String? = nil, url: String? = nil) -> ProjectRule? {
        ProjectRule(PermissionRequest(id: "1", tool: tool, command: command, url: url))
    }

    /// The content the CLI 2.1.286 reads from `text`, as its rule parser does: the first unescaped `(`, the last
    /// unescaped `)` at the end, then `\(` and `\)` unescaped before `\\`; empty or `*` means the whole tool.
    static func contentReadByTheCLI(_ text: String) -> (tool: String, content: String?) {
        func unescaped(_ character: Character, backwards: Bool) -> String.Index? {
            var indices = Array(text.indices)
            if backwards { indices.reverse() }
            return indices.first { index in
                guard text[index] == character else { return false }
                var slashes = 0
                var previous = index
                while previous > text.startIndex {
                    previous = text.index(before: previous)
                    guard text[previous] == "\\" else { break }
                    slashes += 1
                }
                return slashes.isMultiple(of: 2)
            }
        }
        guard let open = unescaped("(", backwards: false),
              let close = unescaped(")", backwards: true),
              close == text.index(before: text.endIndex), close > open
        else { return (text, nil) }
        let raw = String(text[text.index(after: open)..<close])
        if raw.isEmpty || raw == "*" { return (String(text[..<open]), nil) }
        let content = raw.replacing("\\(", with: "(").replacing("\\)", with: ")").replacing("\\\\", with: "\\")
        return (String(text[..<open]), content)
    }

    @Test(arguments: ["npm test", "git status && npm test", #"echo "(a)" \(b\) \\ end"#, "printf 'x)'\nls", "a\\"])
    func aCommandRuleIsTheExactCommandAsTheCLIReadsIt(command: String) throws {
        let rule = try #require(Self.rule("Bash", command: command))
        #expect(Self.contentReadByTheCLI(rule.text) == ("Bash", command))
    }

    @Test(arguments: ["ls *.swift", "npm run test:*", "*", "   ", ""])
    func aCommandTheCLIWouldReadAsAPatternGivesNoRule(command: String) {
        #expect(Self.rule("Bash", command: command) == nil)
    }

    @Test func aSiteRuleIsItsHostOnly() {
        #expect(Self.rule("WebFetch", url: "https://Docs.Swift.org/a?b=1")?.text == "WebFetch(domain:docs.swift.org)")
        #expect(Self.rule("WebFetch", url: "https://*.evil.dev/") == nil)
        #expect(Self.rule("WebFetch", url: "not a url") == nil)
    }

    @Test func anMCPRuleIsOneToolAndFileEditsGiveNone() {
        #expect(Self.rule("mcp__linear__create_issue")?.text == "mcp__linear__create_issue")
        #expect(Self.rule("mcp__linear__*") == nil)
        #expect(Self.rule("mcp__linear") == nil)
        #expect(ProjectRule(PermissionRequest(id: "1", tool: "Edit", path: "/p/a.swift")) == nil)
        #expect(Self.rule("Bash") == nil)
    }

    @Test func onlyRulesTheCLIReadsAreWellFormed() {
        for text in ["Bash(npm test)", "WebFetch(domain:a.dev)", "mcp__a__b", #"Bash(echo \(x\))"#] {
            #expect(ProjectRule.isWellFormed(text), "\(text)")
        }
        for text in ["", "Bash(", "Bash()", "Bash(x) y", "(x)", "Bash)"] {
            #expect(!ProjectRule.isWellFormed(text), "\(text)")
        }
    }
}

struct RuleStoreTests {
    let base: URL
    let project: URL
    let store: RuleStore

    init() throws {
        base = URL(filePath: TrustGate.realPath(FileManager.default.temporaryDirectory.path))
            .appending(path: "RuleStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        project = base.appending(path: "repo", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project.appending(path: ".git"), withIntermediateDirectories: true)
        var store = RuleStore(project: project)
        store.userSettings = base.appending(path: "home/.claude/settings.json")
        self.store = store
    }

    func write(_ json: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    func settings() throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: store.file)) as? NSDictionary)
    }

    @Test func theFirstRuleCreatesTheFileOfTheMainCheckout() throws {
        try store.add("Bash(npm test)")
        #expect(store.file.path == project.appending(path: ".claude/settings.local.json").path)
        #expect(try settings() == ["permissions": ["allow": ["Bash(npm test)"]]])
        #expect(store.entries == [.init(rule: "Bash(npm test)", origin: .local)])
    }

    @Test func aRuleWrittenByTheCLIChangesOnlyTheAllowList() throws {
        // As the CLI leaves it: other keys, deny and ask rules, hooks, keys Bubo does not know.
        try write(#"""
            {
              "permissions": {"allow": ["Bash(git log *)", "WebFetch(domain:a.dev)"], "deny": ["Read(./.env)"],
                              "ask": ["Bash(git push *)"], "defaultMode": "acceptEdits", "additionalDirectories": ["../x"]},
              "hooks": {"PostToolUse": [{"matcher": "Edit", "hooks": [{"type": "command", "command": "swift-format"}]}]},
              "env": {"A": "1"}, "futureKey": [1, 2.5, null, false], "enabledPlugins": {"p@m": true}
            }
            """#, to: store.file)
        let before = try settings().mutableCopy() as! NSMutableDictionary

        try store.add("Bash(npm test)")
        try store.add("Bash(npm test)")

        let permissions = try #require(before["permissions"] as? NSDictionary).mutableCopy() as! NSMutableDictionary
        permissions["allow"] = ["Bash(git log *)", "WebFetch(domain:a.dev)", "Bash(npm test)"]
        before["permissions"] = permissions
        #expect(try settings() == before)
    }

    @Test func aRuleIsChangedInPlaceAndRevoked() throws {
        try write(#"{"permissions": {"allow": ["Bash(a)", "Bash(b)", "Bash(c)"]}}"#, to: store.file)
        try store.replace("Bash(b)", with: "Bash(b --quiet)")
        #expect(store.entries.map(\.rule) == ["Bash(a)", "Bash(b --quiet)", "Bash(c)"])
        try store.replace("Bash(c)", with: "Bash(a)")
        #expect(store.entries.map(\.rule) == ["Bash(a)", "Bash(b --quiet)"])
        try store.remove("Bash(a)")
        #expect(store.entries.map(\.rule) == ["Bash(b --quiet)"])
    }

    @Test func aWorktreeSavesInTheMainCheckout() throws {
        let admin = project.appending(path: ".git/worktrees/w", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: admin, withIntermediateDirectories: true)
        try Data("../..\n".utf8).write(to: admin.appending(path: "commondir"))
        let worktree = base.appending(path: "worktrees/w", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try Data("gitdir: \(admin.path)\n".utf8).write(to: worktree.appending(path: ".git"))

        #expect(RuleStore(project: worktree).file.path == store.file.path)
    }

    @Test func everyOriginIsListedAndUnreadableFilesAreReported() throws {
        try write(#"{"permissions": {"allow": ["Bash(a)"]}}"#, to: store.file)
        try write(#"{"permissions": {"allow": ["Bash(shared)"]}}"#, to: project.appending(path: ".claude/settings.json"))
        try write(#"{"permissions": {"allow": ["Bash(mine)"]}"#, to: store.userSettings)
        #expect(store.entries == [.init(rule: "Bash(a)", origin: .local), .init(rule: "Bash(shared)", origin: .project)])
        #expect(store.unreadableFiles == [store.userSettings])
    }

    @Test(arguments: ["{not json", "[]", #"{"permissions": []}"#, #"{"permissions": {"allow": "Bash"}}"#,
                      #"{"permissions": {"allow": [1]}}"#])
    func aFileTheCLIWouldNotWriteIsLeftUntouched(json: String) throws {
        try write(json, to: store.file)
        #expect(throws: RuleStoreError.unreadableSettings) { try store.add("Bash(npm test)") }
        #expect(try String(contentsOf: store.file, encoding: .utf8) == json)
    }

    @Test func aLinkedFolderIsNeverWrittenThrough() throws {
        let elsewhere = base.appending(path: "home/.claude", directoryHint: .isDirectory)
        try write("{}", to: elsewhere.appending(path: "settings.local.json"))
        try FileManager.default.createSymbolicLink(at: project.appending(path: ".claude"), withDestinationURL: elsewhere)

        #expect(throws: RuleStoreError.unsafeLocation) { try store.add("Bash(npm test)") }
        #expect(try String(contentsOf: elsewhere.appending(path: "settings.local.json"), encoding: .utf8) == "{}")
    }

    @Test func aLinkedFileIsNeverWrittenThrough() throws {
        let target = base.appending(path: "home/.zshrc")
        try write("{}", to: target)
        try FileManager.default.createDirectory(at: store.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: store.file, withDestinationURL: target)

        #expect(throws: RuleStoreError.unsafeLocation) { try store.add("Bash(npm test)") }
        #expect(try String(contentsOf: target, encoding: .utf8) == "{}")
    }
}
