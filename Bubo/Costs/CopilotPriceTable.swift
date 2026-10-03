import Foundation
import os

/// GitHub's list prices for the models of Copilot, the only place Bubo keeps them (ADR 0011, #542): the Spesa of a
/// Domanda or a Sessione on Copilot is estimated from its tokens with them, since no documented API says the credits
/// a turn used. One AI credit is a cent of a dollar, so the Spesa in dollars is also the credits.
///
/// Written by hand from "Models and pricing for GitHub Copilot" in `PrezziCopilot.json`, with the day of the copy.
/// Never refreshed by the app. The long-context prices, past 200k or 272k tokens of a single request, are left out:
/// the turn's tokens do not say how they were split among requests.
nonisolated struct CopilotPriceTable: Codable, Equatable, Sendable {
    /// What a model costs, in dollars per million tokens.
    struct Price: Codable, Equatable, Sendable {
        var input: Decimal
        var cacheRead: Decimal
        /// `nil` for a model whose cache writes cost nothing more than its input.
        var cacheWrite: Decimal?
        var output: Decimal

        enum CodingKeys: String, CodingKey {
            case input, output
            case cacheRead = "cache_read"
            case cacheWrite = "cache_write"
        }

        /// The figure of one model's tokens in a turn, the input without the cache; reasoning is already in the
        /// output.
        func figure(of tokens: TurnUsage.ModelTokens) -> Decimal {
            let total = Decimal(tokens.inputTokens) * input + Decimal(tokens.cacheReadTokens) * cacheRead
                + Decimal(tokens.cacheWriteTokens) * (cacheWrite ?? input) + Decimal(tokens.outputTokens) * output
            return total / 1_000_000
        }
    }

    /// The day the prices were copied from GitHub's page.
    var date: Date
    /// The prices by Copilot model id, such as `claude-sonnet-5.5`.
    var models: [String: Price]

    /// The price of `model`, its id in any case; `nil` when the table does not have it.
    func price(of model: String) -> Price? {
        models[model.lowercased()]
    }

    /// `usage`, the tokens of a Copilot turn as the bridge reports them, as Spesa priced with this table. A turn with a
    /// model the table does not have counts only its tokens, with no figure, outside the Budgets.
    ///
    /// `copilot` counts the input as OpenAI does, cache reads and writes included: the turn keeps, as Claude's, only
    /// what is left of it as input.
    func spesa(of usage: TurnUsage) -> TurnUsage {
        var priced = usage
        priced.mode = .apiKey
        priced.basis = .list
        for index in priced.models.indices {
            var tokens = priced.models[index]
            tokens.inputTokens = max(tokens.inputTokens - tokens.cacheReadTokens - tokens.cacheWriteTokens, 0)
            tokens.cost = price(of: tokens.model)?.figure(of: tokens)
            priced.models[index] = tokens
        }
        if priced.models.contains(where: { $0.cost == nil }) {
            priced.origin = .unpriced
            priced.cost = nil
            priced.priceDate = nil
        } else {
            priced.origin = .priceTable
            priced.cost = priced.models.reduce(0) { $0 + ($1.cost ?? 0) }
            priced.priceDate = date
        }
        return priced
    }

    /// The table in Bubo's bundle.
    static let bundled: CopilotPriceTable? = {
        guard let url = Bundle.main.url(forResource: "PrezziCopilot", withExtension: "json") else { return nil }
        do {
            return try AnthropicPriceTable.decoder.decode(CopilotPriceTable.self, from: Data(contentsOf: url))
        } catch {
            Logger.costs.error("Copilot prices unreadable: \(error)")
            return nil
        }
    }()
}
