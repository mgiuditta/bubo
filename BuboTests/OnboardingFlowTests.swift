import Foundation
import Testing
@testable import Bubo

@MainActor
struct OnboardingFlowTests {
    let defaults: UserDefaults
    let project = URL(filePath: "/Users/ada/Sviluppo/bubo", directoryHint: .isDirectory)
    let ready = ClaudeReadiness.ready(version: "2.1.286", method: "Max")

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "OnboardingFlowTests-\(UUID().uuidString)"))
    }

    /// A flow that records the Sessioni it starts.
    final class Starts {
        var started: [(question: String, project: URL)] = []
    }

    func makeFlow(hasSessions: Bool = false, starts: Starts = Starts()) -> OnboardingFlow {
        OnboardingFlow(hasSessions: hasSessions, defaults: defaults) { question, project in
            starts.started.append((question, project))
            return UUID()
        }
    }

    @Test func aRecentProjectAQuestionAndReturnStartTheSessione() {
        let starts = Starts()
        let flow = makeFlow(starts: starts)
        flow.readiness = ready
        flow.choose(project)
        flow.draft = "Trova i TODO più vecchi"
        flow.send()
        #expect(starts.started.map(\.question) == ["Trova i TODO più vecchi"])
        #expect(starts.started.map(\.project) == [project])
        #expect(flow.draft.isEmpty)
    }

    @Test func aQuestionBeforeTheProjectWaitsAndStartsAtTheChoice() {
        let starts = Starts()
        let flow = makeFlow(starts: starts)
        flow.readiness = ready
        flow.draft = "Spiegami com'è fatto questo Progetto"
        flow.send()
        #expect(starts.started.isEmpty)
        #expect(String(localized: flow.orbLine) == String(localized: "In quale Progetto?"))
        flow.choose(project)
        #expect(starts.started.map(\.question) == ["Spiegami com'è fatto questo Progetto"])
    }

    @Test func aQuestionDuringTheDetectionWaitsForClaude() {
        let starts = Starts()
        let flow = makeFlow(starts: starts)
        #expect(String(localized: flow.orbLine) == String(localized: "Controllo cosa c'è sul Mac…"))
        flow.choose(project)
        flow.draft = "Ciao"
        flow.send()
        #expect(starts.started.isEmpty)
        flow.readiness = .signedOut(version: "2.1.286")
        #expect(starts.started.isEmpty)
        flow.readiness = ready
        #expect(starts.started.count == 1)
    }

    @Test func startsOnlyOneSessione() {
        let starts = Starts()
        let flow = makeFlow(starts: starts)
        flow.readiness = ready
        flow.choose(project)
        flow.draft = "Uno"
        flow.send()
        flow.draft = "Due"
        flow.send()
        flow.choose(URL(filePath: "/tmp/altro"))
        #expect(starts.started.map(\.question) == ["Uno"])
    }

    @Test func theWaitingQuestionSurvivesAQuitUntilTheFirstToken() {
        let flow = makeFlow()
        flow.draft = "Cosa è cambiato nell'ultima settimana?"
        flow.send()

        let starts = Starts()
        let reopened = makeFlow(starts: starts)
        #expect(reopened.pendingQuestion == "Cosa è cambiato nell'ultima settimana?")
        reopened.readiness = ready
        reopened.choose(project)
        #expect(starts.started.map(\.question) == ["Cosa è cambiato nell'ultima settimana?"])

        reopened.receiveFirstToken()
        #expect(reopened.isCompleted)
        #expect(reopened.pendingQuestion == nil)
        #expect(makeFlow().isCompleted)
    }

    @Test func aUserWithSessioniIsPastTheOnboarding() {
        #expect(makeFlow(hasSessions: true).isCompleted)
    }

    /// The answers of `claude` to each detection, in order; the last one repeats.
    final class Detections {
        var answers: [ClaudeReadiness]
        var count = 0

        init(_ answers: ClaudeReadiness...) {
            self.answers = answers
        }

        func next() -> ClaudeReadiness {
            defer { count += 1 }
            return answers[min(count, answers.count - 1)]
        }
    }

    func makeFlow(detections: Detections, starts: Starts, movedToAPIKey: Starts? = nil) -> OnboardingFlow {
        OnboardingFlow(hasSessions: false, defaults: defaults, checkInterval: .zero,
                       detect: { detections.next() },
                       moveToAPIKey: { movedToAPIKey?.started.append(("", URL(filePath: "/"))) }) { question, project in
            starts.started.append((question, project))
            return UUID()
        }
    }

    @Test func theQuestionWaitingStartsOnItsOwnOnceClaudeIsInstalledAndSignedIn() async {
        let starts = Starts()
        let detections = Detections(.missing, .signedOut(version: "2.1.286"), ready)
        let flow = makeFlow(detections: detections, starts: starts)
        flow.choose(project)
        flow.draft = "Trova i TODO più vecchi"
        flow.send()

        await flow.detectClaude()
        #expect(flow.needsRemedy)
        await flow.recheck()
        #expect(flow.readiness == .signedOut(version: "2.1.286"))
        #expect(starts.started.isEmpty)
        await flow.recheck()

        #expect(!flow.needsRemedy)
        #expect(starts.started.map(\.question) == ["Trova i TODO più vecchi"])
    }

    @Test func aReadyClaudeIsNotCheckedAgain() async {
        let detections = Detections(ready)
        let flow = makeFlow(detections: detections, starts: Starts())
        await flow.detectClaude()
        await flow.recheck()
        #expect(detections.count == 1)
    }

    @Test func anOutdatedClaudeStaysARemedyUntilUpdated() async {
        let detections = Detections(.outdated(version: "2.0.77"), .outdated(version: "2.0.77"), ready)
        let flow = makeFlow(detections: detections, starts: Starts())
        await flow.detectClaude()
        await flow.recheck()
        #expect(flow.readiness == .outdated(version: "2.0.77"))
        await flow.recheck()
        #expect(flow.isClaudeReady)
    }

    @Test func theAPIKeyStandsInForTheLogin() async {
        let starts = Starts()
        let moved = Starts()
        let flow = makeFlow(detections: Detections(.signedOut(version: "2.1.286")), starts: starts, movedToAPIKey: moved)
        flow.choose(project)
        flow.draft = "Ciao"
        flow.send()
        await flow.detectClaude()

        await flow.useAPIKey()

        #expect(moved.started.count == 1)
        #expect(flow.readiness == .ready(version: "2.1.286", method: "API key"))
        #expect(starts.started.map(\.question) == ["Ciao"])
    }

    @Test func theAPIKeyWithoutClaudeStillNeedsTheInstallationButNotTheLogin() async {
        let starts = Starts()
        let flow = makeFlow(detections: Detections(.missing, .signedOut(version: "2.1.286")), starts: starts)
        flow.choose(project)
        flow.draft = "Ciao"
        flow.send()
        await flow.detectClaude()

        await flow.useAPIKey()
        #expect(flow.readiness == .missing)
        #expect(starts.started.isEmpty)

        await flow.recheck()
        #expect(flow.readiness == .ready(version: "2.1.286", method: "API key"))
        #expect(starts.started.count == 1)
    }

    @Test func aQuitDuringTheFirstTurnKeepsTheOnboardingUntilItAnswers() {
        let flow = makeFlow()
        flow.draft = "Ciao"
        flow.send()
        let reopened = makeFlow(hasSessions: true)
        #expect(!reopened.isCompleted)
    }
}
