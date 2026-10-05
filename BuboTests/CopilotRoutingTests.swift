import Foundation
import Testing
@testable import Bubo

/// Copilot in the router (#541, ADR 0011): only on the user's explicit choice, with the Tinta of the model's vendor.
struct CopilotRoutingTests {
    static let gpt = CopilotModel(id: "gpt-6", name: "GPT-6", supportedEfforts: [.low, .medium, .high],
                                  defaultEffort: .medium)
    static let gemini = CopilotModel(id: "gemini-3-pro", name: "Gemini 3 Pro")
    static let sonnet = CopilotModel(id: "claude-sonnet-5.5", name: "Claude Sonnet 5.5")
    static let models = [gpt, gemini, sonnet]

    let router = ModelRouter()

    // Acceptance of #541: no automatic path uses Copilot, whatever the network, the Quota, the Budgets or the fit.
    @Test(arguments: RequestType.allCases)
    func noAutomaticRouteUsesCopilot(type: RequestType) {
        var local = OpenAICompatibleEndpoint.known.first { $0.kind == .ollama }!
        local.model = "qwen3:8b"
        for isOffline in [false, true] {
            for fiveHourUsed in [nil, 0.5, 0.85, 0.97] {
                for overBudget in [Set<String>(), [Budgets.claude, Budgets.copilot]] {
                    for localModel in [nil, local] {
                        for fit in [OnDeviceFit.fits(tokens: 10), .tooLong(tokens: 9_000), .unavailable] {
                            var preferences = ModelRouter.Preferences(copilotModels: Self.models)
                            preferences.isOffline = isOffline
                            preferences.fiveHourUsed = fiveHourUsed
                            preferences.overBudget = overBudget
                            preferences.localModel = localModel
                            let route = router.route(for: ModelRouterTests.classification(type), fit: fit,
                                                     preferences: preferences, in: ModelRouterTests.catalog)
                            #expect(route.copilotModel == nil)
                        }
                    }
                }
            }
        }
        #expect(router.route(for: nil, preferences: ModelRouter.Preferences(copilotModels: Self.models),
                             in: nil).copilotModel == nil)
    }

    @Test func aCopilotPreferenceAnswersItsTipo() {
        let preferences = ModelRouter.Preferences(choices: [.writing: .copilot(id: "gpt-6", name: "GPT-6")],
                                                  copilotModels: Self.models)

        let route = router.route(for: ModelRouterTests.classification(.writing), preferences: preferences,
                                 in: ModelRouterTests.catalog)

        #expect(route == .copilot(Self.gpt, effort: nil, reason: .preferred(.writing)))
        // The other Tipi keep their default.
        #expect(router.route(for: ModelRouterTests.classification(.plan), preferences: preferences,
                             in: ModelRouterTests.catalog).copilotModel == nil)
    }

    @Test func aCopilotPreferenceIsTakenOnTrustUntilTheModelsAreRead() {
        let preferences = ModelRouter.Preferences(choices: [.writing: .copilot(id: "gpt-6", name: "GPT-6")])

        let route = router.route(for: ModelRouterTests.classification(.writing), preferences: preferences, in: nil)

        #expect(route.copilotModel == CopilotModel(id: "gpt-6", name: "GPT-6"))
    }

    // #725: Copilot reads the Allegati, so its preference answers with them too.
    @Test func aCopilotPreferencePausesOnlyWithoutItsModel() {
        let choices: [RequestType: TypePreference] = [.writing: .copilot(id: "gpt-6", name: "GPT-6")]
        let classification = ModelRouterTests.classification(.writing)

        let withAllegati = router.route(for: classification, hasAttachments: true,
                                        preferences: ModelRouter.Preferences(choices: choices, copilotModels: Self.models),
                                        in: ModelRouterTests.catalog)
        let withoutModel = router.route(for: classification,
                                        preferences: ModelRouter.Preferences(choices: choices, copilotModels: [Self.gemini]),
                                        in: ModelRouterTests.catalog)

        #expect(withAllegati.pausedPreference == nil)
        #expect(withAllegati.copilotModel == Self.gpt)
        #expect(withoutModel.pausedPreference == .endpointUnavailable)
        #expect(withoutModel.copilotModel == nil)
    }

    @Test func anOverBudgetCopilotPreferenceGoesToTheDefault() {
        var preferences = ModelRouter.Preferences(choices: [.writing: .copilot(id: "gpt-6", name: "GPT-6")],
                                                  copilotModels: Self.models)
        preferences.overBudget = [Budgets.copilot]

        let route = router.route(for: ModelRouterTests.classification(.writing), preferences: preferences,
                                 in: ModelRouterTests.catalog)

        #expect(route.copilotModel == nil)
        #expect(route.pausedPreference == .overBudget(Budgets.copilot))
    }

    // ADR 0011: Claude always goes through `claude`, so "Rifai con…" offers only Copilot's other vendors.
    @Test func rifaiConOffersCopilotsOtherVendorsOnly() {
        let alternatives = RetryAlternative.alternatives(
            around: Scala.Step(family: .sonnet, effort: .medium), on: Scala(catalog: ModelRouterTests.catalog),
            endpoints: [], copilotModels: Self.models, answeredBy: RetryAlternative(target: .copilot(Self.gemini)).id)

        #expect(alternatives.map(\.target) == [.claude(Scala.Step(family: .sonnet, effort: .low)),
                                               .claude(Scala.Step(family: .sonnet, effort: .high)),
                                               .copilot(Self.gpt)])
    }

    @Test(arguments: [
        ("gpt-6", Provider?.some(.openAI)), ("o4-mini", .openAI), ("claude-opus-5", .anthropic),
        ("gemini-3-pro", .google), ("grok-5", .xAI), ("mistral-large", .mistral), ("raptor-mini", nil),
    ])
    func theTintaIsTheVendors(id: String, provider: Provider?) {
        #expect(CopilotModel(id: id, name: id).provider == provider)
    }

    @Test func theScalaOfACopilotModelIsItsEfforts() {
        #expect(Self.gpt.effort(above: nil) == .high)
        #expect(Self.gpt.effort(above: .low) == .medium)
        #expect(Self.gpt.effort(above: .high) == nil)
        #expect(Self.gemini.effort(above: nil) == nil)
    }

    @Test func theReasonLineSaysViaCopilot() {
        let retried = String(localized: RouterLine.reason(for: .copilot(Self.gpt, effort: nil, reason: .retried)))
        let preferred = String(localized: RouterLine.reason(for: .copilot(Self.gpt, effort: nil,
                                                                          reason: .preferred(.writing))))

        #expect(retried.hasSuffix("via Copilot"))
        #expect(preferred.contains("GPT-6"))
        #expect(preferred.hasSuffix("via Copilot"))
    }
}
