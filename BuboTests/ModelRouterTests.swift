import Foundation
import Testing
@testable import Bubo

struct ModelRouterTests {
    /// A catalog like Misura A of spec 10: Haiku without effort, Sonnet and Opus with every level.
    static let catalog = ModelCatalog(entries: [
        ModelCatalog.Entry(value: "default", resolvedModel: "claude-opus-5-5", displayName: "Default (recommended)",
                           supportedEffortLevels: Effort.allCases),
        ModelCatalog.Entry(value: "haiku", resolvedModel: "claude-haiku-4-5-20251001", displayName: "Haiku"),
        ModelCatalog.Entry(value: "sonnet", resolvedModel: "claude-sonnet-5-5", displayName: "Sonnet",
                           supportedEffortLevels: Effort.allCases),
        ModelCatalog.Entry(value: "opus", resolvedModel: "claude-opus-5-5", displayName: "Opus",
                           supportedEffortLevels: Effort.allCases),
    ])

    let router = ModelRouter()

    static func classification(_ type: RequestType, runnerUp: RequestType? = nil) -> RequestClassification {
        RequestClassification(type: type, runnerUp: runnerUp, categoria: .chat, variante: nil, engine: .rules)
    }

    @Test(arguments: [
        (RequestType.shortFact, ModelFamily.haiku, Effort?.none),
        (.summary, .haiku, nil),
        (.writing, .sonnet, .medium),
        (.reasoning, .opus, .medium),
        (.webSearch, .sonnet, .low),
    ])
    func aDomandaTakesItsTiposDefault(type: RequestType, family: ModelFamily, effort: Effort?) {
        let route = router.route(for: Self.classification(type), in: Self.catalog)
        #expect(route == Route(family: family, model: family.alias, effort: effort, reason: .type(type, runnerUp: nil)))
    }

    // The reason line on 100% of the answers: every Tipo routes to a model, with or without the catalog.
    @Test(arguments: RequestType.allCases)
    func everyTipoHasARoute(type: RequestType) {
        for catalog in [Self.catalog, nil] {
            let route = router.route(for: Self.classification(type), in: catalog)
            #expect(route.family != nil)
            #expect(route.reason == .type(type, runnerUp: nil))
        }
    }

    @Test func withoutTheCatalogTheAliasGoesAsItIs() {
        let route = router.route(for: Self.classification(.reasoning), in: nil)
        #expect(route.model == "opus")
        #expect(route.effort == .medium)
    }

    @Test func anEffortTheModelLacksStepsDownNeverUp() {
        let catalog = ModelCatalog(entries: [
            ModelCatalog.Entry(value: "opus", displayName: "Opus", supportedEffortLevels: [.low, .high]),
            ModelCatalog.Entry(value: "sonnet", displayName: "Sonnet", supportedEffortLevels: [.medium, .high]),
        ])
        #expect(router.route(for: Self.classification(.reasoning), in: catalog).effort == .low)
        #expect(router.route(for: Self.classification(.webSearch), in: catalog).effort == nil)
    }

    @Test func aFamilyOutsideTheCatalogLeavesClaudesDefault() {
        let catalog = ModelCatalog(entries: [ModelCatalog.Entry(value: "sonnet", displayName: "Sonnet")])
        let route = router.route(for: Self.classification(.reasoning), in: catalog)
        #expect(route == Route(family: nil, model: nil, effort: nil, reason: .unavailable(.reasoning, .opus)))
    }

    @Test func anUncertainClassificationNamesBothTipi() {
        let route = router.route(for: Self.classification(.reasoning, runnerUp: .writing), in: Self.catalog)
        #expect(route.family == .opus)
        #expect(route.reason == .type(.reasoning, runnerUp: .writing))
    }

    @Test func noClassificationLeavesClaudesDefault() {
        #expect(router.route(for: nil, in: Self.catalog)
            == Route(family: nil, model: nil, effort: nil, reason: .unclassified))
    }

    @Test(arguments: [
        ("claude-haiku-4-5-20251001", "Haiku 4.5"),
        ("claude-opus-5-5", "Opus 5.5"),
        ("claude-sonnet-4-6[1m]", "Sonnet 4.6"),
        ("claude-fable-5", "Fable 5"),
        ("gpt-5", "gpt-5"),
        ("claude-opus", "claude-opus"),
    ])
    func theAnsweringModelReadsAsPeopleCallIt(id: String, name: String) {
        #expect(AnsweringModel(model: id, effort: nil).name == name)
    }
}

struct RoutedAnswerTests {
    static let resetsAt = Date(timeIntervalSince1970: 1_790_852_400)

    static func usage(_ mode: TurnUsage.Mode, cost: Decimal?) -> TurnUsage {
        TurnUsage(mode: mode, cost: cost, basis: .list, isComplete: cost != nil, models: [])
    }

    static var answer: RoutedAnswer { RoutedAnswer(route: .chosen("sonnet"), provider: .anthropic) }

    @Test func theWindowsShareComesFirstWithTheSubscription() {
        var answer = Self.answer
        answer.usage = Self.usage(.subscription, cost: 0.05)
        answer.fiveHourShare = 0.02
        #expect(answer.cost == .fiveHourShare(0.02))
    }

    @Test func aWindowThatDidNotMoveFallsBackToTheListValue() {
        var answer = Self.answer
        answer.usage = Self.usage(.subscription, cost: 0.05)
        #expect(answer.cost == .listValue(0.05))
    }

    @Test func theAPIKeyShowsTheSpesa() {
        var answer = Self.answer
        answer.usage = Self.usage(.apiKey, cost: 0.05)
        answer.fiveHourShare = 0.02
        #expect(answer.cost == .spesa(0.05))
    }

    @Test func aTurnWithoutAFigureShowsNoCost() {
        var answer = Self.answer
        answer.usage = Self.usage(.subscription, cost: nil)
        #expect(answer.cost == nil)
    }

    @Test func theShareIsTheGrowthOfTheSameWindow() throws {
        let before = Quota.Window(used: 0.19, resetsAt: Self.resetsAt)
        let share = try #require(RoutedAnswer.fiveHourShare(from: before, to: Quota.Window(used: 0.21, resetsAt: Self.resetsAt)))
        #expect(abs(share - 0.02) < 1e-9)
        // A window that started again from zero, or did not grow, says nothing of the turn.
        #expect(RoutedAnswer.fiveHourShare(from: before, to: Quota.Window(used: 0.01, resetsAt: Self.resetsAt + 18_000)) == nil)
        #expect(RoutedAnswer.fiveHourShare(from: before, to: before) == nil)
        #expect(RoutedAnswer.fiveHourShare(from: nil, to: before) == nil)
    }
}
