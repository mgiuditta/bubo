import Foundation
import Testing
@testable import Bubo

/// #164: the router avoids a provider whose Budget is past its threshold, when it has an alternative.
extension ModelRouterTests {
    static var cloud: OpenAICompatibleEndpoint {
        var endpoint = OpenAICompatibleEndpoint.known[0]
        endpoint.model = "gpt-prova"
        return endpoint
    }

    static var localModel: OpenAICompatibleEndpoint {
        var endpoint = OpenAICompatibleEndpoint.known[3]
        endpoint.model = "llama-prova"
        return endpoint
    }

    // Acceptance of #164: with an alternative, 0 automatic choices on the provider past its threshold.
    @Test func noTipoGoesToAPreferredProviderPastItsThreshold() {
        let choices = Dictionary(uniqueKeysWithValues: RequestType.allCases.map {
            ($0, TypePreference.endpoint(id: Self.cloud.id))
        })
        var preferences = ModelRouter.Preferences(choices: choices, endpoints: [Self.cloud])
        preferences.overBudget = [Self.cloud.name]

        let routes = RequestType.allCases.map { type in
            router.route(for: Self.classification(type), fit: .fits(tokens: 12), preferences: preferences,
                         in: Self.catalog)
        }

        #expect(routes.allSatisfy { $0.endpoint == nil })
        #expect(routes.allSatisfy { $0.pausedPreference == .overBudget(Self.cloud.name) })
        #expect(String(localized: RouterLine.reason(for: routes[0])).contains(Self.cloud.name))
    }

    @Test func claudeWithTheAPIKeyPastItsThresholdLeavesForTheModelloLocale() {
        var preferences = ModelRouter.Preferences(endpoints: [Self.localModel], localModel: Self.localModel)
        preferences.overBudget = [Budgets.claude]

        let route = router.route(for: Self.classification(.writing), preferences: preferences, in: Self.catalog)
        let withAllegati = router.route(for: Self.classification(.writing), hasAttachments: true,
                                        preferences: preferences, in: Self.catalog)

        #expect(route.endpoint == Self.localModel)
        #expect(route.avoidedBudget == Budgets.claude)
        #expect(withAllegati.destination == .claude)
    }

    @Test func withoutAnAlternativeTheProviderStays() {
        var preferences = ModelRouter.Preferences(choices: [.writing: .endpoint(id: Self.cloud.id)],
                                                  endpoints: [Self.cloud])
        preferences.overBudget = [Self.cloud.name, Budgets.claude]

        let route = router.route(for: Self.classification(.writing), preferences: preferences, in: Self.catalog)

        #expect(route.endpoint == Self.cloud)
        #expect(route.reason == .preferred(.writing))
    }

    @Test func aModelOnTheMacIsNeverAvoided() {
        var preferences = ModelRouter.Preferences(choices: [.writing: .endpoint(id: Self.localModel.id)],
                                                  endpoints: [Self.localModel])
        preferences.overBudget = [Self.localModel.name]

        let route = router.route(for: Self.classification(.writing), preferences: preferences, in: Self.catalog)

        #expect(route.endpoint == Self.localModel)
    }
}
