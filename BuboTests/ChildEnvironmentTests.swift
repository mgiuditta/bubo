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

    @Test func theAPIKeyIsThereOnlyWhenChosen() {
        let environment = ChildEnvironment.make(claude: Self.claude, apiKey: "sk-test", base: Self.base)
        #expect(environment["ANTHROPIC_API_KEY"] == "sk-test")
    }
}
