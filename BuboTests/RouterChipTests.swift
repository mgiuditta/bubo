import Foundation
import Testing
@testable import Bubo

/// The chip in the prompt: Tab and ⇧Tab change the model, ⌥↑ and ⌥↓ the effort, Esc hands back to the router.
@Suite(.timeLimit(.minutes(1)))
struct RouterChipTests {
    static let catalog = ModelRouterTests.catalog
    static let writing = Route(family: .sonnet, model: "sonnet", effort: .medium, reason: .type(.writing, runnerUp: nil))

    @Test func tabGoesToTheNextFamilyKeepingTheEffort() {
        #expect(Self.writing.choosingModel(forward: true, in: Self.catalog)
            == Route(family: .opus, model: "opus", effort: .medium, reason: .chosenByUser))
        #expect(Self.writing.choosingModel(forward: false, in: Self.catalog)
            == Route(family: .haiku, model: "haiku", effort: nil, reason: .chosenByUser))
    }

    @Test func tabWrapsAroundTheFamiliesOfTheCatalog() {
        let opus = Route(family: .opus, model: "opus", effort: .high, reason: .chosenByUser)
        // No Fable in the catalog: after Opus comes Haiku again.
        #expect(opus.choosingModel(forward: true, in: Self.catalog).family == .haiku)
    }

    @Test func fromAppleFMTabStartsAtTheWeakestAndShiftTabAtTheStrongest() {
        let onDevice = Route.onDevice(.shortFact, runnerUp: nil)
        #expect(onDevice.choosingModel(forward: true, in: Self.catalog).family == .haiku)
        #expect(onDevice.choosingModel(forward: false, in: Self.catalog).family == .opus)
    }

    // From Haiku, which has no effort, a model with effort starts at medium.
    @Test func aModelWithEffortGetsOneFromHaiku() {
        let haiku = Route(family: .haiku, model: "haiku", effort: nil, reason: .chosenByUser)
        #expect(haiku.choosingModel(forward: true, in: Self.catalog).effort == .medium)
    }

    @Test func theEffortStaysWithinTheLevelsOfTheModel() {
        let catalog = ModelCatalog(entries: [
            ModelCatalog.Entry(value: "sonnet", displayName: "Sonnet", supportedEffortLevels: [.low, .medium, .high]),
            ModelCatalog.Entry(value: "opus", displayName: "Opus", supportedEffortLevels: Effort.allCases),
        ])
        let opus = Route(family: .opus, model: "opus", effort: .xhigh, reason: .chosenByUser)
        #expect(opus.choosingModel(forward: false, in: catalog).effort == .high)
    }

    // `max` is only for Sessioni: ⌥↑ stops at molto alto.
    @Test func optionArrowsStepTheEffortWithoutMax() throws {
        let stronger = try #require(Self.writing.choosingEffort(stronger: true, in: Self.catalog))
        #expect(stronger == Route(family: .sonnet, model: "sonnet", effort: .high, reason: .chosenByUser))
        let xhigh = Route(family: .sonnet, model: "sonnet", effort: .xhigh, reason: .chosenByUser)
        #expect(xhigh.choosingEffort(stronger: true, in: Self.catalog) == nil)
        #expect(xhigh.choosingEffort(stronger: false, in: Self.catalog)?.effort == .high)
    }

    @Test func aModelWithoutEffortHasNoEffortControl() {
        let haiku = Route(family: .haiku, model: "haiku", effort: nil, reason: .type(.shortFact, runnerUp: nil))
        #expect(haiku.effortLevels(in: Self.catalog).isEmpty)
        #expect(haiku.choosingEffort(stronger: true, in: Self.catalog) == nil)
        #expect(Route.onDevice(.shortFact, runnerUp: nil).choosingEffort(stronger: true, in: nil) == nil)
    }

    @Test func theChipForecastsTheRouterWhileTyping() async throws {
        let model = try QuestionModelTests.routedModel(.writing)
        model.prompt = "Scrivi una mail"
        #expect(model.chipRoute == nil)
        await model.forecasting?.value

        #expect(model.chipRoute == Self.writing)
    }

    @Test func aModelPickedInTheChipIsSaidSoInTheLine() async throws {
        let model = try QuestionModelTests.routedModel(.writing)
        model.prompt = "Scrivi una mail"
        await model.forecasting?.value
        model.chooseModel(forward: false)
        #expect(model.chipRoute == Route(family: .haiku, model: "haiku", effort: nil, reason: .chosenByUser))

        model.ask()
        await model.answering?.value

        #expect(model.failure == nil)
        #expect(model.routedAnswer?.route == .chosen("haiku"))
        // The pick holds for the whole chat.
        #expect(model.chipChoice?.family == .haiku)
    }

    @Test func escHandsBackToTheRouterAndAnEmptyPromptKeepsThePick() async throws {
        let model = try QuestionModelTests.routedModel(.writing)
        model.prompt = "Scrivi una mail"
        model.chooseModel(forward: true)
        #expect(model.returnToRouter())
        #expect(model.chipChoice == nil)
        #expect(!model.returnToRouter())

        model.chooseModel(forward: true)
        model.prompt = ""
        #expect(model.chipChoice != nil)
    }
}
