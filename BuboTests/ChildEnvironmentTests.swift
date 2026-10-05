import Foundation
import Testing
@testable import Bubo

struct ChildEnvironmentTests {
    static let claude = URL(filePath: "/Users/u/.local/bin/claude")
    static let base = ["HOME": "/Users/u", "USER": "u", "PATH": "/evil", "ANTHROPIC_API_KEY": "leaked",
                       "CLAUDE_CODE_SANDBOXED": "1", "DYLD_INSERT_LIBRARIES": "/x.dylib"]

    @Test func onlyTheAllowedVariablesComeFromBubo() {
        let environment = ChildEnvironment.make(claude: Self.claude, base: Self.base)
        #expect(environment["HOME"] == "/Users/u")
        #expect(environment["ANTHROPIC_API_KEY"] == nil)
        #expect(environment["CLAUDE_CODE_SANDBOXED"] == nil)
        #expect(environment["DYLD_INSERT_LIBRARIES"] == nil)
        #expect(environment["PATH"]?.hasPrefix("/Users/u/.local/bin:") == true)
        #expect(environment["BUBO_CLAUDE_PATH"] == Self.claude.path)
    }

    // #719: with only `copilot`, the bridge starts without `claude`.
    @Test func withoutClaudeTheBridgeGetsNoClaudePath() {
        let environment = ChildEnvironment.make(claude: nil, base: Self.base)
        #expect(environment["BUBO_CLAUDE_PATH"] == nil)
        #expect(environment["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }

    @Test func theBridgeKnowsWhereToKeepTheConversations() {
        let environment = ChildEnvironment.make(claude: Self.claude, conversations: URL(filePath: "/tmp/C.sqlite"),
                                                base: Self.base)
        #expect(environment["BUBO_CONVERSATIONS"] == "/tmp/C.sqlite")
        #expect(ChildEnvironment.make(claude: Self.claude, base: Self.base)["BUBO_CONVERSATIONS"] == nil)
    }

    @Test func theAPIKeyIsThereOnlyWhenChosen() {
        let environment = ChildEnvironment.make(claude: Self.claude, apiKey: "sk-test", base: Self.base)
        #expect(environment["ANTHROPIC_API_KEY"] == "sk-test")
    }

    @Test(arguments: ["GH_TOKEN", "GITHUB_TOKEN", "COPILOT_GITHUB_TOKEN"])
    func noGitHubTokenReachesCopilotOrTheBridge(variable: String) {
        let base = Self.base.merging([variable: "gho_leaked"]) { $1 }
        let copilot = URL(filePath: "/opt/homebrew/bin/copilot")
        #expect(ChildEnvironment.makeForCopilot(copilot: copilot, base: base)[variable] == nil)
        #expect(ChildEnvironment.make(claude: Self.claude, base: base)[variable] == nil)
    }

    @Test func copilotFindsItsOwnFolderFirst() {
        let copilot = URL(filePath: "/Users/u/.npm-global/bin/copilot")
        let environment = ChildEnvironment.makeForCopilot(copilot: copilot, base: Self.base)
        #expect(environment["HOME"] == "/Users/u")
        #expect(environment["PATH"]?.hasPrefix("/Users/u/.npm-global/bin:") == true)
        #expect(environment["ANTHROPIC_API_KEY"] == nil)
    }
}
