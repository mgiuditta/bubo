import Foundation

/// The order of the steps model · effort that "Rifai più forte" climbs one at a time, effort first, then the model
/// (spec 10).
///
/// Only the steps the user's catalog offers: a model the organization denies is not in `supportedModels()`, and an
/// effort above its `maxEffortLevel` is skipped once the SDK is seen lowering it. So a step is never refused.
nonisolated struct Scala: Equatable, Sendable {
    /// One step: a family at an effort; Haiku has no effort.
    struct Step: Codable, Hashable, Comparable, Sendable {
        let family: ModelFamily
        let effort: Effort?

        /// The step as the reason line names it, such as «Sonnet · medio»; the family alone without effort.
        var name: String {
            guard let effort else { return family.name }
            return String(localized: "\(family.name) · \(String(localized: effort.label))",
                          comment: "Model and effort in the reason line, such as «Sonnet 5.5 · medio».")
        }

        /// Stronger model first, then stronger effort; no effort is the weakest.
        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.family != rhs.family { return lhs.family < rhs.family }
            guard let right = rhs.effort else { return false }
            guard let left = lhs.effort else { return true }
            return left < right
        }
    }

    /// The steps of the user, weakest first.
    let steps: [Step]

    /// The steps below Fable: `max` stays out, it is only for Sessioni.
    private static let claudeSteps: [Step] = [
        Step(family: .haiku, effort: nil),
        Step(family: .sonnet, effort: .low), Step(family: .sonnet, effort: .medium), Step(family: .sonnet, effort: .high),
        Step(family: .opus, effort: .medium), Step(family: .opus, effort: .high), Step(family: .opus, effort: .xhigh),
    ]

    /// Creates the Scala of `catalog`, without the efforts above `effortCaps`.
    ///
    /// - Parameters:
    ///   - catalog: What `supportedModels()` listed; without it, the steps below Fable, whose efforts the SDK lowers
    ///     by itself where the model lacks them.
    ///   - effortCaps: The strongest effort each family turned out to accept, as the SDK reported it.
    init(catalog: ModelCatalog?, effortCaps: [ModelFamily: Effort] = [:]) {
        var steps = Self.claudeSteps
        if let catalog {
            steps = steps.filter { step in
                guard let entry = catalog.entry(for: step.family.alias) else { return false }
                return step.effort.map(entry.supportedEffortLevels.contains) ?? true
            }
            // Fable, when the account has it, at its strongest effort short of `max`.
            if let fable = catalog.entry(for: ModelFamily.fable.alias) {
                let effort = fable.supportedEffortLevels.filter { $0 < .max }.max()
                if fable.supportedEffortLevels.isEmpty || effort != nil {
                    steps.append(Step(family: .fable, effort: effort))
                }
            }
        }
        self.steps = steps.filter { step in
            guard let cap = effortCaps[step.family], let effort = step.effort else { return true }
            return effort <= cap
        }
    }

    /// The first step stronger than `current`; `nil` at the top, where "Rifai più forte" is off.
    func step(above current: Step) -> Step? {
        steps.first { $0 > current }
    }
}
