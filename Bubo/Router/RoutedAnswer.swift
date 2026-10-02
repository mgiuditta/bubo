import Foundation

/// What the reason line under an answer says: who answered, why, and what it cost (spec 10, Interfaccia).
nonisolated struct RoutedAnswer: Equatable, Sendable {
    /// The estimated cost of the turn, in the unit that matters to the user.
    enum Cost: Equatable, Sendable {
        /// Claude with the subscription: the share of the 5-hour window the turn used, from 0 to 1.
        case fiveHourShare(Double)
        /// Claude with the subscription, when the window did not move or was not reported: the Valore a listino.
        case listValue(Decimal)
        /// Claude with the API key, or another provider that reported it: the Spesa.
        case spesa(Decimal)
        /// Another provider on the user's key: the Spesa estimated with the PriceTable's prices of `pricesOf`.
        case estimate(Decimal, pricesOf: Date)
        /// A model on the Mac: nothing to pay.
        case free
        /// An endpoint in another cloud, paid on the user's key at a price Bubo does not know: the tokens it counted.
        case tokens(Int)
    }

    let route: Route
    /// The provider whose Tinta the line's dot takes; `nil` for the neutral Tinta.
    let provider: Provider?
    /// Who answered, once the bridge says; until then the line names the family the router asked for.
    var answeringModel: AnsweringModel?
    /// The tokens and figure of the turn, as the bridge last reported them.
    var usage: TurnUsage?
    /// The share of the 5-hour window used during the turn, when `claude` reported the window before and after it.
    var fiveHourShare: Double?
    /// The OpenAI-compatible endpoint that answered instead of `claude`, if one did.
    let endpoint: OpenAICompatibleEndpoint?
    /// The tokens the endpoint counted for the turn, input and output together.
    var endpointTokens: Int?

    init(route: Route, provider: Provider?, endpoint: OpenAICompatibleEndpoint? = nil) {
        self.route = route
        self.provider = provider
        self.endpoint = endpoint
    }

    /// The cost the line shows; `nil` when nothing is known of it.
    ///
    /// With the subscription the window's share comes first: it is what the user runs out of. A share that did not
    /// move (the window not reported, or under its precision) falls back to the Valore a listino.
    var cost: Cost? {
        if route.destination == .onDevice { return .free }
        if let endpoint {
            if endpoint.isOnMac { return .free }
            if let usage, let figure = usage.cost {
                if usage.origin == .priceTable, let date = usage.priceDate { return .estimate(figure, pricesOf: date) }
                return .spesa(figure)
            }
            return endpointTokens.map(Cost.tokens)
        }
        if usage?.mode != .apiKey, let fiveHourShare, fiveHourShare > 0 { return .fiveHourShare(fiveHourShare) }
        guard let usage, let figure = usage.cost else { return nil }
        return usage.mode == .apiKey ? .spesa(figure) : .listValue(figure)
    }

    /// The share of the 5-hour window used between `before` and `after`; `nil` unless both are the same window and
    /// it grew.
    static func fiveHourShare(from before: Quota.Window?, to after: Quota.Window?) -> Double? {
        guard let before, let after, abs(after.resetsAt.timeIntervalSince(before.resetsAt)) < 60,
              after.used > before.used
        else { return nil }
        return after.used - before.used
    }
}
