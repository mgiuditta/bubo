import Foundation

/// The tokens and the figure of one turn of `claude`, as the bridge's UsageReader reads them from the SDK's `result`.
///
/// The figure is the SDK's list-price estimate, made on the Mac: never a bill.
nonisolated struct TurnUsage: Codable, Equatable, Sendable {
    /// How `claude` paid for the turn (ADR 0003).
    enum Mode: String, Codable, Sendable {
        case subscription, apiKey
    }

    /// Which price table the SDK estimated with; `unknown` prices an unknown model at the default model's rate.
    enum Basis: String, Codable, Sendable {
        case list, managed, unknown
    }

    /// The tokens of one model in the turn, subagents included.
    struct ModelTokens: Codable, Equatable, Sendable {
        var model: String
        var inputTokens: Int
        var outputTokens: Int
        var cacheReadTokens: Int
        var cacheWriteTokens: Int
        /// Already counted in `outputTokens`.
        var thinkingTokens: Int
        /// The model's share of the figure; `nil` when the turn stopped without a valid `result`.
        var cost: Decimal?
    }

    var mode: Mode
    /// In US dollars; `nil` when the turn stopped without a valid `result`, so only its tokens are known.
    var cost: Decimal?
    var basis: Basis
    /// Whether the figure covers the whole turn; `false` after a crash.
    var isComplete: Bool
    var models: [ModelTokens]

    /// Spesa with the API key, Valore a listino with the subscription.
    var unit: CostUnit { mode == .apiKey ? .spesa : .valoreListino }

    private enum CodingKeys: String, CodingKey {
        case mode, cost, basis, isComplete = "complete", models
    }
}
