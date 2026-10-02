import Foundation
import os

/// Bubo's own Anthropic prices, with the 1-hour cache write models.dev lacks: the list estimate of the Cronologia CLI
/// (spec 18, #163).
///
/// Written by `scripts/update-anthropic-prices.sh` in a file of its own, apart from the PriceTable's snapshot, which a
/// refresh from models.dev rewrites. Never refreshed by the app.
nonisolated struct AnthropicPriceTable: Codable, Equatable, Sendable {
    /// What a model costs, in dollars per million tokens.
    struct Price: Codable, Equatable, Sendable {
        var input: Decimal
        var output: Decimal
        var cacheRead: Decimal
        var cacheWrite5m: Decimal
        var cacheWrite1h: Decimal

        enum CodingKeys: String, CodingKey {
            case input, output
            case cacheRead = "cache_read"
            case cacheWrite5m = "cache_write_5m"
            case cacheWrite1h = "cache_write_1h"
        }

        /// The figure of a turn's tokens; a cache write not split by duration is priced as a 5-minute one.
        func figure(of tokens: CLIHistoryReader.Tokens) -> Decimal {
            let hour = min(tokens.cacheWrite1h, tokens.cacheWrite)
            let total = Decimal(tokens.input) * input + Decimal(tokens.output) * output
                + Decimal(tokens.cacheRead) * cacheRead + Decimal(tokens.cacheWrite - hour) * cacheWrite5m
                + Decimal(hour) * cacheWrite1h
            return total / 1_000_000
        }
    }

    /// When the prices were written.
    var date: Date
    /// The prices by model id.
    var models: [String: Price]

    /// The price of `model`, also when it carries a date, as in `claude-sonnet-4-5-20250929`; `nil` when the table
    /// does not have it.
    func price(of model: String) -> Price? {
        if let price = models[model] { return price }
        guard let dash = model.lastIndex(of: "-"), model[model.index(after: dash)...].count == 8,
              model[model.index(after: dash)...].allSatisfy(\.isNumber) else { return nil }
        return models[String(model[..<dash])]
    }

    /// The table in Bubo's bundle.
    static let bundled: AnthropicPriceTable? = {
        guard let url = Bundle.main.url(forResource: "PrezziAnthropic", withExtension: "json") else { return nil }
        do {
            return try decoder.decode(AnthropicPriceTable.self, from: Data(contentsOf: url))
        } catch {
            Logger.costs.error("Anthropic prices unreadable: \(error)")
            return nil
        }
    }()

    /// Reads the table's JSON, dates in ISO 8601.
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
