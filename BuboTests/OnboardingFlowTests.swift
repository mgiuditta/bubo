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

    @Test func aQuitDuringTheFirstTurnKeepsTheOnboardingUntilItAnswers() {
        let flow = makeFlow()
        flow.draft = "Ciao"
        flow.send()
        let reopened = makeFlow(hasSessions: true)
        #expect(!reopened.isCompleted)
    }
}
