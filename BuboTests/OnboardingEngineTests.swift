import Foundation
import Testing
@testable import Bubo

/// The step of the Motore at the start of the onboarding (#721, ADR 0014).
@MainActor
struct OnboardingEngineTests {
    let defaults: UserDefaults
    let settings: EndpointSettings
    let project = URL(filePath: "/Users/ada/Sviluppo/bubo", directoryHint: .isDirectory)
    let claudeReady = ClaudeReadiness.ready(version: "2.1.286", method: "Max")
    let copilotReady = CopilotReadiness.ready(version: "1.0.16", account: "ada")

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "OnboardingEngineTests-\(UUID().uuidString)"))
        settings = EndpointSettings(defaults: defaults)
    }

    /// What `claude` and `copilot` answer at each detection, the last answer repeated.
    final class Detections {
        var claude: [ClaudeReadiness]
        var copilot: [CopilotReadiness]
        private(set) var claudeCount = 0
        private(set) var copilotCount = 0

        init(claude: [ClaudeReadiness], copilot: [CopilotReadiness]) {
            self.claude = claude
            self.copilot = copilot
        }

        func nextClaude() -> ClaudeReadiness {
            defer { claudeCount += 1 }
            return claude[min(claudeCount, claude.count - 1)]
        }

        func nextCopilot() -> CopilotReadiness {
            defer { copilotCount += 1 }
            return copilot[min(copilotCount, copilot.count - 1)]
        }
    }

    /// The questions of the Sessioni started.
    final class Starts {
        var questions: [String] = []
    }

    func makeFlow(_ detections: Detections, starts: Starts = Starts(), hasSessions: Bool = false) -> OnboardingFlow {
        OnboardingFlow(hasSessions: hasSessions, defaults: defaults,
                       detect: { detections.nextClaude() },
                       detectCopilot: { @MainActor in detections.nextCopilot() },
                       settings: settings) { question, _ in
            starts.questions.append(question)
            return UUID()
        }
    }

    @Test func withOnlyCopilotItIsPreselectedAndTheFirstSessioneStartsOnIt() async {
        let starts = Starts()
        let flow = makeFlow(Detections(claude: [.missing], copilot: [copilotReady]), starts: starts)
        await flow.detectEngines()
        #expect(flow.engineOption == .copilot)
        #expect(flow.highlightedStep == .engine)

        flow.allowCopilot(sharingNotes: false)
        flow.confirmEngine()
        #expect(flow.isEngineChosen)
        #expect(PrimaryEngine.saved(in: defaults) == PrimaryEngine(engine: .copilot, hasReserve: false))
        #expect(!flow.needsRemedy)

        flow.choose(project)
        flow.draft = "Trova i TODO più vecchi"
        flow.send()
        #expect(starts.questions == ["Trova i TODO più vecchi"])
    }

    @Test func withOnlyClaudeItIsPreselected() async {
        let flow = makeFlow(Detections(claude: [.signedOut(version: "2.1.286")], copilot: [.missing]))
        await flow.detectEngines()
        #expect(flow.engineOption == .claude)
    }

    @Test func withBothNothingIsPreselected() async {
        let flow = makeFlow(Detections(claude: [claudeReady], copilot: [copilotReady]))
        await flow.detectEngines()
        #expect(flow.engineOption == nil)
        #expect(!flow.canConfirmEngine)
    }

    @Test func bothSavesThePrincipaleWithTheOtherAsReserve() async {
        let flow = makeFlow(Detections(claude: [claudeReady], copilot: [copilotReady]))
        await flow.detectEngines()
        flow.chooseEngine(.both)
        flow.primaryOfBoth = .copilot
        flow.allowCopilot(sharingNotes: true)
        flow.confirmEngine()
        #expect(PrimaryEngine.saved(in: defaults) == PrimaryEngine(engine: .copilot, hasReserve: true))
    }

    @Test func aMotoreNotReadyBlocksTheStepUntilRiprovaFindsItReady() async {
        let detections = Detections(claude: [.missing, claudeReady], copilot: [.missing])
        let flow = makeFlow(detections)
        await flow.detectEngines()
        flow.chooseEngine(.claude)
        #expect(!flow.canConfirmEngine)
        flow.confirmEngine()
        #expect(!flow.isEngineChosen)

        await flow.recheckEngines()
        #expect(flow.isReady(.claude))
        #expect(detections.copilotCount == 2)
        flow.confirmEngine()
        #expect(flow.isEngineChosen)
    }

    @Test func entrambiNeedsBothReady() async {
        let flow = makeFlow(Detections(claude: [claudeReady], copilot: [.signedOut(version: "1.0.16")]))
        await flow.detectEngines()
        flow.chooseEngine(.both)
        flow.allowCopilot(sharingNotes: false)
        #expect(!flow.canConfirmEngine)
    }

    @Test(arguments: [OnboardingFlow.EngineOption.copilot, .both])
    func copilotsConsentIsAskedInTheStep(option: OnboardingFlow.EngineOption) async {
        let flow = makeFlow(Detections(claude: [claudeReady], copilot: [copilotReady]))
        await flow.detectEngines()
        flow.chooseEngine(option)
        #expect(flow.needsCopilotConsent)
        #expect(!flow.canConfirmEngine)

        flow.allowCopilot(sharingNotes: false)
        #expect(settings.allowsCopilot)
        #expect(!flow.needsCopilotConsent)
        // The question on the notes was answered here: the first Domanda does not ask it.
        #expect(!settings.needsCopilotNotesConsent(hasSecondBrain: true))
        #expect(flow.canConfirmEngine)
    }

    @Test func claudeAloneNeedsNoConsent() async {
        let flow = makeFlow(Detections(claude: [claudeReady], copilot: [.missing]))
        await flow.detectEngines()
        flow.chooseEngine(.claude)
        #expect(!flow.needsCopilotConsent)
        flow.confirmEngine()
        #expect(PrimaryEngine.saved(in: defaults) == PrimaryEngine())
    }

    @Test func theQuestionWaitsForTheStepOfTheMotore() async {
        let starts = Starts()
        let flow = makeFlow(Detections(claude: [claudeReady], copilot: [.missing]), starts: starts)
        await flow.detectEngines()
        flow.choose(project)
        flow.draft = "Ciao"
        flow.send()
        #expect(starts.questions.isEmpty)
        flow.confirmEngine()
        #expect(starts.questions == ["Ciao"])
    }

    @Test func anExistingUserNeverSeesTheStep() {
        defaults.set(true, forKey: OnboardingFlow.completedKey)
        let flow = makeFlow(Detections(claude: [claudeReady], copilot: [.missing]))
        #expect(flow.isEngineChosen)
        #expect(flow.isDone(.engine))
        #expect(flow.primaryEngine == .claude)
    }

    @Test func aUserWithSessioniNeverSeesTheStep() {
        let flow = makeFlow(Detections(claude: [claudeReady], copilot: [.missing]), hasSessions: true)
        #expect(flow.isEngineChosen)
    }

    @Test func theChoiceSurvivesAQuit() async {
        let flow = makeFlow(Detections(claude: [claudeReady], copilot: [.missing]))
        await flow.detectEngines()
        flow.confirmEngine()
        let relaunched = makeFlow(Detections(claude: [claudeReady], copilot: [.missing]))
        #expect(relaunched.isEngineChosen)
    }

    @Test func theOrbAsksForTheMotoreFirst() {
        let flow = makeFlow(Detections(claude: [claudeReady], copilot: [.missing]))
        #expect(String(localized: flow.orbLine) == String(localized: "Con quale Motore lavoriamo?"))
    }
}
