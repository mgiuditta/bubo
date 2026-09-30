import Testing
@testable import Bubo

struct AccountStateTests {
    @Test func signedInStatusShowsEmailAndPlan() {
        let output = ProcessOutput(exitCode: 0, standardOutput: """
            {"loggedIn": true, "authMethod": "claude.ai", "email": "ada@example.com", "subscriptionType": "max"}
            """)
        #expect(AccountState(statusOutput: output) == .signedIn(email: "ada@example.com", plan: "Max"))
    }

    @Test func signedInWithoutPlanKeepsEmail() {
        let output = ProcessOutput(exitCode: 0, standardOutput: #"{"loggedIn": true, "authMethod": "console", "email": "ada@example.com"}"#)
        #expect(AccountState(statusOutput: output) == .signedIn(email: "ada@example.com", plan: nil))
    }

    @Test func signedOutStatusExitsWithOne() {
        let output = ProcessOutput(exitCode: 1, standardOutput: #"{"loggedIn": false, "authMethod": "none", "apiProvider": "firstParty"}"#)
        #expect(AccountState(statusOutput: output) == .signedOut)
    }

    @Test func expiredLoginIsRecognized() {
        let output = ProcessOutput(exitCode: 1, standardOutput: "", standardError: "Login expired · Please run /login")
        #expect(AccountState(statusOutput: output) == .expired)
    }

    @Test func emailContainingExpiredIsNotAnExpiredLogin() {
        let output = ProcessOutput(exitCode: 0, standardOutput: #"{"loggedIn": true, "email": "expired@example.com"}"#)
        #expect(AccountState(statusOutput: output) == .signedIn(email: "expired@example.com", plan: nil))
    }

    @Test(arguments: ["", "not json", #"{"email": "ada@example.com"}"#])
    func unexpectedOutputIsAnUnknownError(standardOutput: String) {
        let output = ProcessOutput(exitCode: 0, standardOutput: standardOutput)
        #expect(AccountState(statusOutput: output) == .unknownError(exitCode: 0))
    }

    @Test func loggedInWithNonzeroExitIsAnUnknownError() {
        let output = ProcessOutput(exitCode: 2, standardOutput: #"{"loggedIn": true}"#)
        #expect(AccountState(statusOutput: output) == .unknownError(exitCode: 2))
    }
}
