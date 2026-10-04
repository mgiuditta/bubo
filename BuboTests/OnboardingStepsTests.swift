import Foundation
import Testing
@testable import Bubo

/// The steps 1 Progetto → 2 Domanda and the first Richiesta di permesso at the centre of the HUD (#674).
@MainActor
struct OnboardingStepsTests {
    let defaults: UserDefaults
    let project = URL(filePath: "/Users/ada/Sviluppo/bubo", directoryHint: .isDirectory)
    let session = UUID()

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "OnboardingStepsTests-\(UUID().uuidString)"))
    }

    func makeFlow() -> OnboardingFlow {
        let flow = OnboardingFlow(hasSessions: false, defaults: defaults) { [session] _, _ in session }
        flow.readiness = .ready(version: "2.1.286", method: "Max")
        return flow
    }

    @Test func beforeAnythingNoStepIsDoneOrHighlighted() {
        let flow = makeFlow()
        #expect(!flow.isDone(.project))
        #expect(!flow.isDone(.question))
        #expect(flow.highlightedStep == nil)
    }

    @Test func aQuestionTypedWithNoProjectHighlightsTheProject() {
        let flow = makeFlow()
        flow.draft = "Trova i TODO più vecchi"
        #expect(flow.highlightedStep == .project)
        flow.send()
        #expect(flow.isDone(.question))
        #expect(flow.highlightedStep == .project)
    }

    @Test func aProjectChosenFirstHighlightsTheQuestion() {
        let flow = makeFlow()
        flow.choose(project)
        #expect(flow.isDone(.project))
        #expect(flow.highlightedStep == .question)
    }

    @Test func bothStepsDoneHighlightNothing() {
        let flow = makeFlow()
        flow.choose(project)
        flow.draft = "Ciao"
        flow.send()
        #expect(flow.isDone(.project) && flow.isDone(.question))
        #expect(flow.highlightedStep == nil)
    }

    @Test func theFirstSessionAwaitsItsFirstPermissionUntilAnswered() {
        let flow = makeFlow()
        #expect(flow.sessionAwaitingFirstPermission == nil)
        flow.choose(project)
        flow.draft = "Ciao"
        flow.send()
        #expect(flow.sessionAwaitingFirstPermission == session)
        flow.answerFirstPermission()
        #expect(flow.sessionAwaitingFirstPermission == nil)
        #expect(OnboardingFlow(hasSessions: true, defaults: defaults) { _, _ in UUID() }.isFirstPermissionAnswered)
    }
}
