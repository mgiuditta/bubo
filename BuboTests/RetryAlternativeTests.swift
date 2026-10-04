import Foundation
import Testing
@testable import Bubo

struct RetryAlternativeTests {
    static let catalog = ModelCatalog(entries: [
        .init(value: "haiku", displayName: "Haiku"),
        .init(value: "sonnet", displayName: "Sonnet", supportedEffortLevels: [.low, .medium, .high]),
        .init(value: "opus", displayName: "Opus", supportedEffortLevels: [.low, .medium, .high, .xhigh, .max]),
    ])

    static func endpoint(_ id: String) -> OpenAICompatibleEndpoint {
        OpenAICompatibleEndpoint(id: id, kind: .custom, name: id, baseURL: URL(string: "https://\(id).test/v1")!,
                                 model: "m")
    }

    @Test func theNearestStepsComeFirstThenTheEndpoints() {
        let alternatives = RetryAlternative.alternatives(
            around: Scala.Step(family: .sonnet, effort: .medium), on: Scala(catalog: Self.catalog),
            endpoints: [Self.endpoint("a")], answeredBy: nil)

        #expect(alternatives.map(\.target) == [
            .claude(Scala.Step(family: .sonnet, effort: .low)),
            .claude(Scala.Step(family: .sonnet, effort: .high)),
            .endpoint(Self.endpoint("a")),
        ])
    }

    @Test func theEndpointThatAnsweredIsLeftOut() {
        let alternatives = RetryAlternative.alternatives(
            around: nil, on: Scala(catalog: Self.catalog), endpoints: [Self.endpoint("a"), Self.endpoint("b")],
            answeredBy: "a")

        #expect(alternatives.map(\.target) == [
            .claude(Scala.Step(family: .sonnet, effort: .medium)),
            .claude(Scala.Step(family: .opus, effort: .medium)),
            .endpoint(Self.endpoint("b")),
        ])
    }

    @Test func atTheBottomOnlyTheStepAboveIsOffered() {
        let alternatives = RetryAlternative.alternatives(
            around: Scala.Step(family: .haiku, effort: nil), on: Scala(catalog: Self.catalog), endpoints: [],
            answeredBy: nil)

        #expect(alternatives.map(\.target) == [.claude(Scala.Step(family: .sonnet, effort: .low))])
    }
}
