import Foundation
import Testing
@testable import Bubo

/// The Quota in the router (spec 10, #96): past 80% of the 5-hour window one step down the Scala, past 95% on the Mac.
struct QuotaRoutingTests {
    let router = ModelRouter()

    static func preferences(used: Double?, localModel: OpenAICompatibleEndpoint? = nil,
                            choices: [RequestType: TypePreference] = [:],
                            isOffline: Bool = false) -> ModelRouter.Preferences {
        var preferences = ModelRouter.Preferences(choices: choices, endpoints: localModel.map { [$0] } ?? [],
                                                  localModel: localModel, isOffline: isOffline)
        preferences.fiveHourUsed = used
        return preferences
    }

    func route(_ type: RequestType, used: Double?, fit: OnDeviceFit = .fits(tokens: 100),
               localModel: OpenAICompatibleEndpoint? = nil, choices: [RequestType: TypePreference] = [:],
               isOffline: Bool = false, in catalog: ModelCatalog? = ModelRouterTests.catalog) -> Route {
        router.route(for: ModelRouterTests.classification(type), fit: fit,
                     preferences: Self.preferences(used: used, localModel: localModel, choices: choices,
                                                   isOffline: isOffline),
                     in: catalog)
    }

    @Test func at79PercentTheDefaultStays() {
        #expect(route(.writing, used: 0.79) == Route(family: .sonnet, model: "sonnet", effort: .medium,
                                                     reason: .type(.writing, runnerUp: nil)))
    }

    @Test func at81PercentTheAutomaticChoiceTakesOneStepDown() {
        #expect(route(.writing, used: 0.81) == Route(family: .sonnet, model: "sonnet", effort: .low,
                                                     reason: .quota(.writing, threshold: 0.8)))
    }

    @Test func oneStepDownFollowsTheScala() {
        // The catalog offers no Opus · low on the Scala: below Opus · medium comes Sonnet · high.
        let stepped = route(.reasoning, used: 0.81)
        #expect(stepped.family == .sonnet)
        #expect(stepped.effort == .high)
        #expect(route(.webSearch, used: 0.81, in: nil).family == .haiku)
    }

    @Test func at96PercentTheModelloLocaleAnswers() {
        let local = LocalModelTests.local()

        let routed = route(.writing, used: 0.96, localModel: local)

        #expect(routed.endpoint == local)
        #expect(routed.reason == .quota(.writing, threshold: 0.95))
    }

    @Test func at96PercentWithoutAModelloLocaleAppleFMAnswers() {
        let routed = route(.plan, used: 0.96)

        #expect(routed.destination == .onDevice)
        #expect(routed.reason == .quota(.plan, threshold: 0.95))
    }

    @Test func at96PercentWhenNothingOnTheMacCanAnswerTheStepDownHolds() {
        let routed = route(.writing, used: 0.96, fit: .unavailable)

        #expect(routed.destination == .claude)
        #expect(routed.effort == .low)
        #expect(routed.reason == .quota(.writing, threshold: 0.8))
    }

    @Test func withoutANetworkTheModelloLocaleAnswersWhateverTheQuota() {
        let local = LocalModelTests.local()

        for used in [nil, 0.5, 0.96] {
            let routed = route(.writing, used: used, localModel: local, isOffline: true)
            #expect(routed.endpoint == local)
            #expect(routed.reason == .offline(.writing))
        }
    }

    @Test(arguments: [0.79, 0.81, 0.96])
    func nothingIsEverBlocked(used: Double) {
        for type in RequestType.allCases {
            for fit in [OnDeviceFit.fits(tokens: 100), .unavailable] {
                for catalog in [ModelRouterTests.catalog, nil] {
                    let routed = route(type, used: used, fit: fit, in: catalog)
                    #expect(routed.family != nil || routed.destination != .claude)
                }
            }
        }
    }

    @Test func atTheBottomOfTheScalaTheChoiceStays() {
        let routed = route(.shortFact, used: 0.81, fit: .tooLong(tokens: 9_000))

        #expect(routed.family == .haiku)
        #expect(routed.reason == .type(.shortFact, runnerUp: nil))
    }

    @Test func theUsersPreferenceStaysIntact() {
        let opus = TypePreference.claude(Scala.Step(family: .opus, effort: .high))

        let routed = route(.writing, used: 0.96, choices: [.writing: opus])

        #expect(routed == Route(family: .opus, model: "opus", effort: .high, reason: .preferred(.writing)))
    }

    @Test func anUnknownQuotaChangesNothing() {
        #expect(route(.writing, used: nil).reason == .type(.writing, runnerUp: nil))
    }

    @Test func theThresholdsComeFromTheSettings() throws {
        let defaults = try #require(UserDefaults(suiteName: "QuotaRoutingTests.\(UUID())"))
        #expect(QuotaThresholds.saved(in: defaults) == QuotaThresholds())

        defaults.set(0.6, forKey: QuotaThresholds.stepDownKey)
        defaults.set(0.7, forKey: QuotaThresholds.onMacKey)
        let thresholds = QuotaThresholds.saved(in: defaults)
        var preferences = Self.preferences(used: 0.65)
        preferences.quotaThresholds = thresholds

        let routed = router.route(for: ModelRouterTests.classification(.writing), fit: .fits(tokens: 100),
                                  preferences: preferences, in: ModelRouterTests.catalog)

        #expect(thresholds == QuotaThresholds(stepDown: 0.6, onMac: 0.7))
        #expect(routed.reason == .quota(.writing, threshold: 0.6))
    }

    @Test func theReasonLineSaysTheThreshold() {
        let stepped = route(.writing, used: 0.81)

        let line = String(localized: RouterLine.reason(for: stepped))

        #expect(line.contains("80%"))
        #expect(line.contains(ModelFamily.sonnet.name))
        #expect(line != String(localized: RouterLine.reason(for: route(.writing, used: 0.79))))
    }
}
