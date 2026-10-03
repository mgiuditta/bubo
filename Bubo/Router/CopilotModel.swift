/// A model the user's Copilot plan offers, as `listModels()` of the Copilot SDK lists it; never a list written in the
/// code (ADR 0011). Models the plan's policy turns off do not reach Bubo.
nonisolated struct CopilotModel: Decodable, Equatable, Sendable {
    /// What `copilot` accepts as its model, such as `gpt-6`.
    let id: String
    let name: String
    /// How many credits a request costs against the base rate; `nil` when `copilot` does not say.
    var multiplier: Double?
    /// The reasoning efforts the model accepts; empty for a model without them.
    var supportedEfforts: [Effort]
    /// The effort the model uses when Bubo asks for none.
    var defaultEffort: Effort?

    init(id: String, name: String, multiplier: Double? = nil, supportedEfforts: [Effort] = [], defaultEffort: Effort? = nil) {
        self.id = id
        self.name = name
        self.multiplier = multiplier
        self.supportedEfforts = supportedEfforts
        self.defaultEffort = defaultEffort
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        multiplier = try container.decodeIfPresent(Double.self, forKey: .multiplier)
        // A level a newer `copilot` adds is skipped, not a reason to lose the whole list.
        supportedEfforts = (try container.decodeIfPresent([String].self, forKey: .supportedEfforts) ?? [])
            .compactMap(Effort.init(rawValue:))
        defaultEffort = try container.decodeIfPresent(String.self, forKey: .defaultEffort).flatMap(Effort.init(rawValue:))
    }

    /// The vendor of the model, whose Tinta the Orb takes while it answers: GPT via Copilot has OpenAI's (ADR 0011);
    /// `nil` for a vendor Bubo does not recognize from the id, and the neutral Tinta.
    var provider: Provider? {
        let id = id.lowercased()
        if id.hasPrefix("claude") { return .anthropic }
        if id.hasPrefix("gpt") || id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4") || id.hasPrefix("codex") {
            return .openAI
        }
        if id.hasPrefix("gemini") { return .google }
        if id.hasPrefix("grok") { return .xAI }
        return id.split(separator: "-").first.flatMap { Provider(named: String($0)) }
    }

    /// The effort just above `effort` among the model's own, for "Rifai più forte"; `nil` at the top, for a model
    /// without efforts, and when `effort` is not known.
    func effort(above effort: Effort?) -> Effort? {
        guard let current = effort ?? defaultEffort else { return nil }
        return supportedEfforts.filter { $0 > current }.min()
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, multiplier, supportedEfforts, defaultEffort
    }
}
