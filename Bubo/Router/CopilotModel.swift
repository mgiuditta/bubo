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

    private enum CodingKeys: String, CodingKey {
        case id, name, multiplier, supportedEfforts, defaultEffort
    }
}
