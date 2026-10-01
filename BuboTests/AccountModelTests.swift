import Foundation
import Synchronization
import Testing
@testable import Bubo

struct AccountModelTests {
    /// A `claude` whose login waits for the browser until cancelled, and whose status reads signed out.
    static let runner = ProcessRunner { executable, arguments in
        switch arguments.last {
        case "command -v claude": return ProcessOutput(exitCode: 0, standardOutput: "/usr/local/bin/claude\n")
        case "login":
            try await Task.sleep(for: .seconds(60))
            return ProcessOutput(exitCode: 0, standardOutput: "")
        default: return ProcessOutput(exitCode: 0, standardOutput: #"{"loggedIn": false}"#)
        }
    }

    @Test func cancellingTheLoginKeepsTheAccountAsItWas() async {
        let model = AccountModel(cli: ClaudeCLI(runner: Self.runner, isOnline: { true }, locator: .onlyLoginShell(Self.runner)))
        await model.refresh()
        let before = model.state
        #expect(before == .signedOut)

        let login = Task { await model.signIn() }
        while !model.isSigningIn { await Task.yield() }
        login.cancel()
        await login.value

        #expect(model.state == before)
        #expect(model.failure == nil)
        #expect(!model.isSigningIn)
    }
}
