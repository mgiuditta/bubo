import Foundation

/// How hard a Claude model thinks on a turn, as the Agent SDK names its levels; weakest first.
nonisolated enum Effort: String, CaseIterable, Codable, Comparable, Sendable {
    case low, medium, high, xhigh, max

    /// The level as the reason line says it.
    var label: LocalizedStringResource {
        switch self {
        case .low: LocalizedStringResource("basso", comment: Self.comment)
        case .medium: LocalizedStringResource("medio", comment: Self.comment)
        case .high: LocalizedStringResource("alto", comment: Self.comment)
        case .xhigh: LocalizedStringResource("molto alto", comment: Self.comment)
        case .max: LocalizedStringResource("massimo", comment: Self.comment)
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    private static let comment: StaticString = "Effort level of a Claude model (sforzo), after the model's name: «Sonnet 5.5 · medio»."
}
