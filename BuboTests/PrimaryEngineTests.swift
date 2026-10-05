import Foundation
import Testing
@testable import Bubo

/// #720: the Motore principale, where Domande and Sessioni start when nothing more specific chose (ADR 0014).
struct PrimaryEngineTests {
    private let router = ModelRouter()
    private let defaults: UserDefaults
    private let suite = "PrimaryEngineTests-\(UUID().uuidString)"

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    private var copilotFirst: ModelRouter.Preferences {
        var preferences = ModelRouter.Preferences.none
        preferences.primaryEngine = .copilot
        return preferences
    }

    @Test func claudeWithoutReserveIsTheDefaultAndTheChoiceIsKept() {
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(PrimaryEngine.saved(in: defaults) == PrimaryEngine(engine: .claude, hasReserve: false))

        defaults.set(Session.Engine.copilot.rawValue, forKey: PrimaryEngine.engineKey)
        defaults.set(true, forKey: PrimaryEngine.reserveKey)

        #expect(PrimaryEngine.saved(in: defaults) == PrimaryEngine(engine: .copilot, hasReserve: true))
    }

    @Test(arguments: [RequestType.writing, .reasoning, .plan])
    func withCopilotFirstADomandaWithoutPreferenceGoesToCopilot(type: RequestType) {
        let route = router.route(for: ModelRouterTests.classification(type), preferences: copilotFirst,
                                 in: ModelRouterTests.catalog)

        #expect(route.copilotModel == .configured)
        #expect(route.reason == .type(type, runnerUp: nil))
    }

    @Test func withCopilotFirstAFattoBreveStillStaysOnTheMac() {
        let route = router.route(for: ModelRouterTests.classification(.shortFact), fit: .fits(tokens: 12),
                                 preferences: copilotFirst, in: ModelRouterTests.catalog)

        #expect(route.destination == .onDevice)
    }

    @Test func aPreferenceForTheTipoBeatsTheMotorePrincipale() {
        var preferences = copilotFirst
        preferences.choices = [.writing: .claude(Scala.Step(family: .opus, effort: .high))]

        let route = router.route(for: ModelRouterTests.classification(.writing), preferences: preferences,
                                 in: ModelRouterTests.catalog)

        #expect(route == Route(family: .opus, model: "opus", effort: .high, reason: .preferred(.writing)))
    }

    @Test func withClaudeFirstNothingChanges() {
        let route = router.route(for: ModelRouterTests.classification(.writing), in: ModelRouterTests.catalog)

        #expect(route == Route(family: .sonnet, model: "sonnet", effort: .medium, reason: .type(.writing, runnerUp: nil)))
    }

    @Test func aProjectWithoutChoiceStartsOnTheMotorePrincipale() {
        defer { defaults.removePersistentDomain(forName: suite) }
        let project = URL(filePath: "/tmp/repo")
        #expect(ProjectEngineStore(defaults: defaults).choice(for: project) == .claude)

        defaults.set(Session.Engine.copilot.rawValue, forKey: PrimaryEngine.engineKey)

        #expect(ProjectEngineStore(defaults: defaults).choice(for: project) == EngineChoice(engine: .copilot))
    }

    @Test func aProjectsChoiceBeatsTheMotorePrincipale() {
        defer { defaults.removePersistentDomain(forName: suite) }
        let project = URL(filePath: "/tmp/repo")
        defaults.set(Session.Engine.copilot.rawValue, forKey: PrimaryEngine.engineKey)

        ProjectEngineStore(defaults: defaults).setChoice(.claude, for: project)

        #expect(ProjectEngineStore(defaults: defaults).choice(for: project) == .claude)
        #expect(ProjectEngineStore(defaults: defaults).choice(for: URL(filePath: "/tmp/altro")) == EngineChoice(engine: .copilot))
    }
}
