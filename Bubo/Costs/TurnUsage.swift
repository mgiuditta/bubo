import Foundation

/// The tokens and the figure of one turn: of `claude`, as the bridge's UsageReader reads them from the SDK's `result`,
/// or of another provider, as `UsageReader` reads its answer.
///
/// The figure is an estimate made on the Mac, never a bill, unless the provider reported it; `origin` says which.
nonisolated struct TurnUsage: Codable, Equatable, Sendable {
    /// How the turn was paid: `claude`'s subscription or API key (ADR 0003), or the user's key at another provider;
    /// `commandLine` for a turn of the Cronologia CLI, whose transcript does not say.
    enum Mode: String, Codable, Sendable {
        case subscription, apiKey, commandLine
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
    /// Where `cost` comes from; the SDK's estimate for what the bridge reports.
    var origin: CostOrigin = .listEstimate
    /// The day of the PriceTable's prices, for a figure priced with it: the price of the turn's time, never redone.
    var priceDate: Date?

    /// Gratis on the Mac; the command line's own list estimate for the Cronologia CLI; otherwise Spesa per use,
    /// Valore a listino with the subscription.
    var unit: CostUnit {
        if origin == .free { return .gratis }
        return switch mode {
        case .apiKey: .spesa
        case .subscription: .valoreListino
        case .commandLine: .rigaDiComando
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mode, cost, basis, isComplete = "complete", models, origin, priceDate
    }
}

nonisolated extension TurnUsage {
    /// Reads a turn; one from the bridge, or saved before origins existed, is the SDK's estimate.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(Mode.self, forKey: .mode)
        cost = try container.decodeIfPresent(Decimal.self, forKey: .cost)
        basis = try container.decode(Basis.self, forKey: .basis)
        isComplete = try container.decode(Bool.self, forKey: .isComplete)
        models = try container.decode([ModelTokens].self, forKey: .models)
        origin = try container.decodeIfPresent(CostOrigin.self, forKey: .origin) ?? .listEstimate
        priceDate = try container.decodeIfPresent(Date.self, forKey: .priceDate)
    }
}
