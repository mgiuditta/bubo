import Foundation
import Testing
@testable import Bubo

/// The first Sessione that does not answer: a refused credential, no network, no first token in 30 s (spec 26).
@MainActor
struct OnboardingFailureTests {
    let defaults: UserDefaults
    let project = URL(filePath: "/Users/ada/Sviluppo/bubo", directoryHint: .isDirectory)
    let session = UUID()
    let clock = FakeClock()
    let calls = Calls()

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "OnboardingFailureTests-\(UUID().uuidString)"))
        // Past the step of the Motore, on Claude as before it existed (ADR 0014).
        defaults.set(true, forKey: OnboardingFlow.engineChosenKey)
    }

    /// A clock that stands still: each wait ends only when the test calls `advance()`.
    @MainActor final class FakeClock {
        private(set) var waits: [Duration] = []
        private var sleepers: [CheckedContinuation<Void, Never>] = []

        func sleep(for duration: Duration) async {
            waits.append(duration)
            await withCheckedContinuation { sleepers.append($0) }
        }

        /// Ends every wait in progress, as if their time had passed.
        func advance() {
            let ending = sleepers
            sleepers = []
            for sleeper in ending { sleeper.resume() }
        }
    }

    /// What the flow asked of the Sessioni and of the credentials.
    final class Calls {
        var restarts: [UUID] = []
        var movesToAPIKey = 0
        var movesToSubscription = 0
        var isOnline = true
    }

    /// A flow whose first Sessione, `session`, already started on `readiness`.
    func makeStartedFlow(readiness: ClaudeReadiness = .ready(version: "2.1.286", method: "Max")) async -> OnboardingFlow {
        let flow = OnboardingFlow(hasSessions: false, defaults: defaults,
                                  moveToAPIKey: { [calls] in calls.movesToAPIKey += 1 },
                                  moveToSubscription: { [calls] in calls.movesToSubscription += 1 },
                                  sleep: { [clock] in await clock.sleep(for: $0) },
                                  isOnline: { [calls] in calls.isOnline },
                                  restart: { [calls] in calls.restarts.append($0) }) { [session] _, _ in session }
        flow.readiness = readiness
        flow.choose(project)
        flow.draft = "Trova i TODO più vecchi"
        flow.send()
        await waitForClock(waits: 1)
        return flow
    }

    /// Lets the flow's wait reach the clock `waits` times.
    func waitForClock(waits: Int) async {
        for _ in 0..<1_000 where clock.waits.count < waits { await Task.yield() }
    }

    /// Lets the flow react to the clock until `condition` holds.
    func settle(until condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() { await Task.yield() }
    }

    @Test func thirtySecondsWithoutTheFirstTokenSayClaudeIsNotAnswering() async {
        let flow = await makeStartedFlow()
        #expect(clock.waits == [.seconds(30)])
        #expect(flow.problem == nil)

        clock.advance()
        await settle { flow.problem != nil }
        #expect(flow.problem == .unanswered)

        flow.askAgain()
        #expect(calls.restarts == [session])
        #expect(flow.problem == nil)
        await waitForClock(waits: 2)
        #expect(clock.waits == [.seconds(30), .seconds(30)])
    }

    @Test func theFirstTokenInTimeEndsTheWait() async {
        let flow = await makeStartedFlow()
        flow.receiveFirstToken()
        clock.advance()
        await settle { false }
        #expect(flow.problem == nil)
        #expect(flow.isCompleted)
    }

    @Test func withoutTheNetworkTheWaitEndsOffline() async {
        calls.isOnline = false
        let flow = await makeStartedFlow()
        clock.advance()
        await settle { flow.problem != nil }
        #expect(flow.problem == .failed(.offline))
    }

    @Test func aFailureWithoutRemedyEndsInTheWait() async {
        let flow = await makeStartedFlow()
        flow.receiveFailure(AgentBridgeError.bridgeExited(status: 1), in: session)
        #expect(flow.problem == nil)
        clock.advance()
        await settle { flow.problem != nil }
        #expect(flow.problem == .unanswered)
    }

    @Test func theFailuresOfOtherSessioniDoNotCount() async {
        let flow = await makeStartedFlow()
        flow.receiveFailure(AgentBridgeError.signInRequired, in: UUID())
        #expect(flow.problem == nil)
    }

    @Test func aRefusedCredentialStopsTheWait() async {
        let flow = await makeStartedFlow()
        flow.receiveFailure(AgentBridgeError.signInRequired, in: session)
        #expect(flow.problem == .failed(.loginExpired))
        clock.advance()
        await settle { false }
        #expect(flow.problem == .failed(.loginExpired))
    }

    @Test func signingInFromARefusedKeyLeavesTheKey() async {
        let flow = await makeStartedFlow()
        await flow.useAPIKey()
        flow.receiveFailure(AgentBridgeError.signInRequired, in: session)
        #expect(flow.problem == .failed(.invalidKey))

        flow.signInAgain()
        #expect(calls.movesToSubscription == 1)
        #expect(!flow.usesAPIKey)
    }

    /// How the user remedies a failure.
    enum Remedy: CaseIterable {
        /// Signs in in the Terminal, then comes back to Bubo.
        case signIn
        /// Saves an API key.
        case apiKey
        /// Presses Riprova.
        case retry
    }

    /// Every failure with a remedy, and every remedy it offers: the same question asks again in the same Sessione.
    @Test(arguments: [
        (AgentBridgeError.signInRequired, ClaudeReadiness.ready(version: "2.1.286", method: "Max"), AuthFailure.loginExpired, Remedy.signIn),
        (AgentBridgeError.signInRequired, .ready(version: "2.1.286", method: "API key"), .invalidKey, .apiKey),
        (AgentBridgeError.signInRequired, .ready(version: "2.1.286", method: "API key"), .invalidKey, .signIn),
        (AgentBridgeError.failed(message: "Not logged in · Please run /login"), .ready(version: "2.1.286", method: "Max"),
         .signedOut, .signIn),
        (AgentBridgeError.turnFailed(TurnFailure(message: "x", reason: "oauth_org_not_allowed")),
         .ready(version: "2.1.286", method: "Max"), .accountWithoutClaudeCode, .signIn),
        (AgentBridgeError.turnFailed(TurnFailure(message: "x", reason: "oauth_org_not_allowed")),
         .ready(version: "2.1.286", method: "Max"), .accountWithoutClaudeCode, .apiKey),
        (AgentBridgeError.turnFailed(TurnFailure(message: "API Error: Connection error.", reason: "unknown")),
         .ready(version: "2.1.286", method: "Max"), .offline, .retry),
    ])
    func theQuestionAsksAgainAfterTheRemedy(error: AgentBridgeError, readiness: ClaudeReadiness, failure: AuthFailure,
                                            remedy: Remedy) async {
        let flow = await makeStartedFlow(readiness: readiness)
        flow.receiveFailure(error, in: session)
        #expect(flow.problem == .failed(failure))

        switch remedy {
        case .signIn:
            flow.signInAgain()
            #expect(calls.restarts.isEmpty)
            await flow.recheck()
        case .apiKey:
            await flow.useAPIKey()
            #expect(calls.movesToAPIKey == 1)
        case .retry:
            flow.askAgain()
        }

        #expect(calls.restarts == [session])
        #expect(flow.problem == nil)
        #expect(!flow.isAwaitingSignIn)
        #expect(flow.pendingQuestion == "Trova i TODO più vecchi")
    }
}
