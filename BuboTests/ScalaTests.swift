import Testing
@testable import Bubo

struct ScalaTests {
    typealias Step = Scala.Step

    nonisolated static func entry(_ family: ModelFamily, _ levels: [Effort] = Effort.allCases) -> ModelCatalog.Entry {
        ModelCatalog.Entry(value: family.alias, displayName: family.name,
                           supportedEffortLevels: family == .haiku ? [] : levels)
    }

    nonisolated static let withoutFable = ModelCatalog(entries: [
        ModelCatalog.Entry(value: "default", displayName: "Default (recommended)", supportedEffortLevels: Effort.allCases),
        entry(.haiku), entry(.sonnet), entry(.opus),
    ])
    nonisolated static let withFable = ModelCatalog(entries: withoutFable.entries + [entry(.fable)])
    /// `deniedModels: ["opus"]`: the organization's denied model is missing from `supportedModels()`.
    nonisolated static let opusDenied = ModelCatalog(entries: [entry(.haiku), entry(.sonnet), entry(.fable)])
    /// `maxEffortLevel: "medium"`, as a catalog whose models list only the levels up to it.
    nonisolated static let effortUpToMedium = ModelCatalog(entries: [
        entry(.haiku), entry(.sonnet, [.low, .medium]), entry(.opus, [.low, .medium]),
    ])

    nonisolated static let claudeSteps = [
        Step(family: .haiku, effort: nil),
        Step(family: .sonnet, effort: .low), Step(family: .sonnet, effort: .medium), Step(family: .sonnet, effort: .high),
        Step(family: .opus, effort: .medium), Step(family: .opus, effort: .high), Step(family: .opus, effort: .xhigh),
    ]

    @Test func effortFirstThenTheModel() {
        #expect(Scala(catalog: Self.withoutFable).steps == Self.claudeSteps)
    }

    @Test func fableIsTheTopWhenTheAccountHasIt() {
        let scala = Scala(catalog: Self.withFable)
        #expect(scala.steps == Self.claudeSteps + [Step(family: .fable, effort: .xhigh)])
        #expect(scala.step(above: Step(family: .opus, effort: .xhigh)) == Step(family: .fable, effort: .xhigh))
    }

    @Test func aDeniedModelIsSkipped() {
        let scala = Scala(catalog: Self.opusDenied)
        #expect(!scala.steps.contains { $0.family == .opus })
        #expect(scala.step(above: Step(family: .sonnet, effort: .high)) == Step(family: .fable, effort: .xhigh))
    }

    @Test func effortsAboveTheOrganizationsCeilingAreSkipped() {
        let scala = Scala(catalog: Self.effortUpToMedium)
        #expect(scala.steps == [Step(family: .haiku, effort: nil), Step(family: .sonnet, effort: .low),
                                Step(family: .sonnet, effort: .medium), Step(family: .opus, effort: .medium)])
        #expect(scala.step(above: Step(family: .sonnet, effort: .medium)) == Step(family: .opus, effort: .medium))
    }

    // `maxEffortLevel` is not always in the catalog: a step the SDK lowered caps its family from then on.
    @Test func anEffortTheSDKLoweredCapsItsFamily() {
        let scala = Scala(catalog: Self.withoutFable, effortCaps: [.opus: .high])
        #expect(scala.step(above: Step(family: .opus, effort: .high)) == nil)
        #expect(!scala.steps.contains(Step(family: .opus, effort: .xhigh)))
    }

    @Test(arguments: [withoutFable, opusDenied, effortUpToMedium])
    func theTopTurnsTheCommandOff(catalog: ModelCatalog) throws {
        let scala = Scala(catalog: catalog)
        #expect(scala.step(above: try #require(scala.steps.last)) == nil)
    }

    // 0 choices refused: every step is a model of the catalog, at an effort it lists, never `max`.
    @Test(arguments: [withoutFable, withFable, opusDenied, effortUpToMedium])
    func everyStepIsOneTheCatalogOffers(catalog: ModelCatalog) throws {
        for step in Scala(catalog: catalog).steps {
            let entry = try #require(catalog.entry(for: step.family.alias))
            if let effort = step.effort {
                #expect(entry.supportedEffortLevels.contains(effort))
                #expect(effort != .max)
            }
        }
    }

    @Test func aStepOffTheScalaClimbsToTheNextOneOn() {
        let scala = Scala(catalog: Self.withoutFable)
        #expect(scala.step(above: Step(family: .opus, effort: .low)) == Step(family: .opus, effort: .medium))
        #expect(scala.step(above: Step(family: .sonnet, effort: .xhigh)) == Step(family: .opus, effort: .medium))
    }

    @Test func withoutTheCatalogTheScalaStopsBelowFable() {
        #expect(Scala(catalog: nil).steps == Self.claudeSteps)
    }

    @Test func theRouteOfAnAnswerIsTheStepThatAnswered() {
        let route = Route(family: .opus, model: "opus", effort: .xhigh, reason: .type(.plan, runnerUp: nil))
        #expect(route.step(answeredBy: AnsweringModel(model: "claude-opus-5-5", effort: .high))
            == Step(family: .opus, effort: .high))
        #expect(route.step(answeredBy: nil) == Step(family: .opus, effort: .xhigh))
        #expect(Route(family: nil, model: nil, effort: nil, reason: .unclassified).step(answeredBy: nil) == nil)
    }
}
