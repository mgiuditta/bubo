import Foundation
import Testing
@testable import Bubo

struct TeamRulesTests {
    static func rules(_ json: String) throws(TeamRulesError) -> TeamRules {
        try TeamRules(data: Data(json.utf8))
    }

    @Test func aValidFileGivesItsRulesNormalized() throws {
        let rules = try Self.rules(#"{"version": 1, "allow": ["Bash(npm test)  ", "Read(./src/**)"], "deny": ["Bash(rm *)"], "ask": ["Bash(git push *)\r\n"]}"#)
        #expect(rules == TeamRules(allow: ["Bash(npm test)", "Read(./src/**)"], deny: ["Bash(rm *)"], ask: ["Bash(git push *)"]))
        #expect(try Self.rules(#"{"version": 1}"#) == TeamRules())
    }

    @Test(arguments: [
        "not json",
        "[]",
        #"{"allow": ["Bash(ls)"]}"#,
        #"{"version": 2, "allow": ["Bash(ls)"]}"#,
        #"{"version": true}"#,
        #"{"version": "1"}"#,
        #"{"version": 1, "deni": ["Bash(rm *)"]}"#,
        #"{"version": 1, "deny": "Bash(rm *)"}"#,
        #"{"version": 1, "deny": ["Bash(rm *)", 3]}"#,
        #"{"version": 1, "allow": ["Bash(ls"]}"#,
        #"{"version": 1, "ask": [""]}"#,
    ])
    func anInvalidFileIsRefusedWhole(json: String) {
        #expect(throws: TeamRulesError.invalid) { try Self.rules(json) }
    }

    @Test func aFileTooLargeIsRefused() {
        let padding = String(repeating: " ", count: TeamRules.maximumSize)
        #expect(throws: TeamRulesError.invalid) { try Self.rules(#"{"version": 1}"# + padding) }
    }

    @Test func theHashIsOfTheNormalizedTextAndChangesWithOneCharacter() {
        #expect(TeamRules.hash(of: "Bash(npm test)") == TeamRules.hash(of: "Bash(npm test) \t\r\n"))
        #expect(TeamRules.hash(of: "Bash(npm test)") != TeamRules.hash(of: "Bash(npm tests)"))
        #expect(TeamRules.hash(of: "Bash(npm test)").count == 64)
    }
}

struct TeamResourceTests {
    /// A folder of its own under the temporary directory, with a ledger there.
    let base: URL
    let project: URL
    let ledger: TrustLedger

    init() throws {
        base = URL(filePath: TrustGate.realPath(FileManager.default.temporaryDirectory.path))
            .appending(path: "TeamResourceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        project = base.appending(path: "repo", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project.appending(path: ".git"), withIntermediateDirectories: true)
        ledger = TrustLedger(file: base.appending(path: "ledger.json"))
    }

    func writeRules(_ json: String) throws {
        try FileManager.default.createDirectory(at: project.appending(path: ".bubo"), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: project.appending(path: TeamRules.path))
    }

    func sessionRules(in folder: URL? = nil) -> TeamRules {
        TeamResourceReader.sessionRules(for: folder ?? project, ledger: ledger)
    }

    @Test func denyAndAskApplyAtOnceAndAllowOnlyOnceAccepted() throws {
        try writeRules(#"{"version": 1, "allow": ["Bash(npm test)"], "deny": ["Bash(rm *)"], "ask": ["WebFetch"]}"#)
        #expect(sessionRules() == TeamRules(deny: ["Bash(rm *)"], ask: ["WebFetch"]))

        try ledger.record(.accepted, about: "Bash(npm test)", inProject: project.path)
        #expect(sessionRules() == TeamRules(allow: ["Bash(npm test)"], deny: ["Bash(rm *)"], ask: ["WebFetch"]))
    }

    @Test func anAcceptedAllowChangedByOneCharacterNoLongerApplies() throws {
        try writeRules(#"{"version": 1, "allow": ["Bash(npm test)"]}"#)
        try ledger.record(.accepted, about: "Bash(npm test)", inProject: project.path)
        try writeRules(#"{"version": 1, "allow": ["Bash(npm tests)"]}"#)
        #expect(sessionRules().allow.isEmpty)
        #expect(ledger.decision(about: "Bash(npm tests)", inProject: project.path) == nil)

        let reader = TeamResourceReader(project: project, ledger: ledger)
        reader.reload()
        let voce = try #require(reader.voci.first)
        #expect(voce.decision == nil)
        #expect(voce.previous == "Bash(npm test)")
        #expect(reader.pendingCount == 1)
    }

    @Test func anIgnoredAllowNeitherAppliesNorWaits() throws {
        try writeRules(#"{"version": 1, "allow": ["Bash(npm test)"]}"#)
        let reader = TeamResourceReader(project: project, ledger: ledger)
        reader.reload()
        try reader.ignore(try #require(reader.voci.first))
        #expect(reader.pendingCount == 0)
        #expect(sessionRules().allow.isEmpty)
    }

    @Test func anAllowOfLevelFourOrFiveHasNoAcceptAndNeverApplies() throws {
        try writeRules(#"{"version": 1, "allow": ["Bash(git push *)"]}"#)
        let reader = TeamResourceReader(project: project, ledger: ledger)
        reader.reload()
        let voce = try #require(reader.voci.first)
        #expect(!voce.isAcceptable)
        try reader.accept(voce)
        #expect(reader.voci.first?.decision == nil)
        // Even accepted behind Bubo's back, it does not reach the Sessione.
        try ledger.record(.accepted, about: "Bash(git push *)", inProject: project.path)
        #expect(sessionRules().allow.isEmpty)
    }

    @Test func anInvalidFileGivesNoRuleAndIsShownAsUnreadable() throws {
        try writeRules(#"{"version": 1, "allow": ["Bash(npm test)"], "deny": ["Bash(rm *)"], "oops": true}"#)
        try ledger.record(.accepted, about: "Bash(npm test)", inProject: project.path)
        #expect(sessionRules() == TeamRules())
        let reader = TeamResourceReader(project: project, ledger: ledger)
        reader.reload()
        #expect(reader.state == .unreadable)
    }

    @Test func aMissingFileGivesNoRule() {
        let reader = TeamResourceReader(project: project, ledger: ledger)
        reader.reload()
        #expect(reader.state == .missing)
        #expect(sessionRules() == TeamRules())
    }

    @Test func aLinkedFileIsNotFollowed() throws {
        let elsewhere = base.appending(path: "elsewhere.json")
        try Data(#"{"version": 1, "deny": ["Bash(rm *)"]}"#.utf8).write(to: elsewhere)
        try FileManager.default.createDirectory(at: project.appending(path: ".bubo"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: project.appending(path: TeamRules.path), withDestinationURL: elsewhere)
        #expect(throws: TeamRulesError.unsafeLocation) { try TeamRules.read(inProject: project) }
    }

    @Test func theRulesOfTheMainCheckoutApplyInASessionWorktree() throws {
        try writeRules(#"{"version": 1, "deny": ["Bash(rm *)"]}"#)
        let worktree = base.appending(path: "worktree", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        let admin = project.appending(path: ".git/worktrees/w", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: admin, withIntermediateDirectories: true)
        try Data("../..\n".utf8).write(to: admin.appending(path: "commondir"))
        try Data("gitdir: \(admin.path)\n".utf8).write(to: worktree.appending(path: ".git"))
        #expect(sessionRules(in: worktree).deny == ["Bash(rm *)"])
    }

    @Test func sharingAddsTheRuleKeepingTheOthersAndAcceptsIt() throws {
        try writeRules(#"{"version": 1, "deny": ["Bash(rm *)"]}"#)
        let writer = TeamResourceWriter(project: project, ledger: ledger)
        try writer.share("Bash(npm test)")
        try writer.share("Bash(npm test)")
        #expect(try TeamRules.read(inProject: project) == TeamRules(allow: ["Bash(npm test)"], deny: ["Bash(rm *)"]))
        #expect(sessionRules().allow == ["Bash(npm test)"])
    }

    @Test func sharingNeverOverwritesAnUnreadableFile() throws {
        let broken = #"{"version": 1, "deny": ["Bash(rm *)""#
        try writeRules(broken)
        #expect(throws: TeamRulesError.invalid) { try TeamResourceWriter(project: project, ledger: ledger).share("Bash(ls)") }
        #expect(try String(contentsOf: project.appending(path: TeamRules.path), encoding: .utf8) == broken)
    }

    @Test func theTeamRulesReachTheBridgeAsSessionRules() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"), settingSources: [],
                                         teamRules: TeamRules(allow: ["Bash(npm test)"], deny: ["Bash(rm *)"])).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","id":"a1","prompt":"Ciao","rules":{"allow":["Bash(npm test)"],"ask":[],"deny":["Bash(rm *)"]},"settingSources":[],"type":"ask","v":4}"# + "\n")
    }
}

struct RuleRiskTests {
    static let classifier = RiskClassifier(workingDirectory: URL(filePath: "/Users/me/dev/progetto"),
                                           home: URL(filePath: "/Users/me"))

    @Test(arguments: [
        "Bash", "Bash(*)", "Bash()", "Bash(rm *)", "Bash(git push *)", "Bash(git push:*)", "Bash(git *)", "Bash(sudo *)",
        "Bash(find *)", "Bash(bash *)", "Bash(npm publish)", "Bash(* --version)", "Read", "Read(~/**)", "Read(//**)",
        "Edit", "Edit(//etc/**)", "Edit(~/.zshrc)",
    ])
    func aRuleThatCoversLevelFourOrFiveIsDangerous(rule: String) {
        #expect(Self.classifier.risk(ofRule: rule).level.isDangerous)
    }

    @Test(arguments: [
        "Bash(npm test)", "Bash(npm test *)", "Bash(git status *)", "Bash(git diff:*)", "Bash(ls *)",
        "Read(./src/**)", "Edit(src/**)", "WebFetch(domain:docs.swift.org)", "WebSearch", "mcp__linear__create_issue",
    ])
    func aNarrowRuleIsBelowLevelFour(rule: String) {
        #expect(!Self.classifier.risk(ofRule: rule).level.isDangerous)
    }
}
