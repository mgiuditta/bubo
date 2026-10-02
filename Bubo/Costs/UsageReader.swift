import Foundation

/// Turns what a provider says of a Domanda's turn into a `TurnUsage`, with its unit and origin (spec 18, Moduli).
///
/// Claude's turns come already read by the bridge; these are the others: the OpenAI-compatible endpoints and Apple FM.
nonisolated enum UsageReader {
    /// The turn `usage` of `endpoint`: gratis on the Mac, the figure the provider reported, tokens times the prices of
    /// `prices`, or, for a model the table does not have, only the tokens.
    static func turn(_ usage: OpenAICompatibleClient.Usage, from endpoint: OpenAICompatibleEndpoint,
                     prices: PriceTable.Snapshot) -> TurnUsage {
        let cached = min(usage.cachedInput, usage.input)
        let tokens = TurnUsage.ModelTokens(model: endpoint.model, inputTokens: usage.input - cached,
                                           outputTokens: usage.output, cacheReadTokens: cached, cacheWriteTokens: 0,
                                           thinkingTokens: usage.reasoning, cost: nil)
        var turn = TurnUsage(mode: .apiKey, cost: nil, basis: .list, isComplete: true, models: [tokens],
                             origin: .unpriced)
        if endpoint.isOnMac {
            turn.origin = .free
            turn.cost = 0
        } else if let reported = usage.cost {
            turn.origin = .reported
            turn.cost = reported
        } else if let provider = priceProvider(of: endpoint),
                  let figure = prices.cost(of: endpoint.model, at: provider)?
                      .figure(input: usage.input, cachedInput: cached, output: usage.output) {
            turn.origin = .priceTable
            turn.cost = figure
            turn.priceDate = prices.date
        }
        turn.models[0].cost = turn.cost
        return turn
    }

    /// A turn of Apple FM: gratis, with the tokens the model counted; tokens it could not count (before macOS 26.4)
    /// leave the turn incomplete.
    static func onDevice(input: Int?, output: Int?) -> TurnUsage {
        let tokens = TurnUsage.ModelTokens(model: "Apple FM", inputTokens: input ?? 0, outputTokens: output ?? 0,
                                           cacheReadTokens: 0, cacheWriteTokens: 0, thinkingTokens: 0, cost: 0)
        return TurnUsage(mode: .apiKey, cost: 0, basis: .list, isComplete: input != nil && output != nil,
                         models: [tokens], origin: .free)
    }

    /// The models.dev provider whose prices `endpoint` takes; `nil` for one the table does not cover.
    ///
    /// xAI is reached only as a custom endpoint, so it is known by its address.
    static func priceProvider(of endpoint: OpenAICompatibleEndpoint) -> String? {
        switch endpoint.kind {
        case .openAI: "openai"
        case .gemini: "google"
        case .openRouter, .ollama, .lmStudio: nil
        case .custom: endpoint.baseURL.host() == "api.x.ai" ? "xai" : nil
        }
    }
}
