/// The Claude models the user's account offers, as `supportedModels()` lists them; never a list written in the code.
nonisolated struct ModelCatalog: Equatable, Sendable {
    /// One model of the catalog: an alias such as `opus`, or an explicit id.
    struct Entry: Decodable, Equatable, Sendable {
        /// What `claude` accepts as its model: an alias or an id.
        let value: String
        /// The id the alias stands for today, such as `claude-opus-5-5`.
        var resolvedModel: String?
        let displayName: String
        /// The effort levels the model accepts; empty for a model without effort, such as Haiku.
        var supportedEffortLevels: [Effort]

        init(value: String, resolvedModel: String? = nil, displayName: String, supportedEffortLevels: [Effort] = []) {
            self.value = value
            self.resolvedModel = resolvedModel
            self.displayName = displayName
            self.supportedEffortLevels = supportedEffortLevels
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = try container.decode(String.self, forKey: .value)
            resolvedModel = try container.decodeIfPresent(String.self, forKey: .resolvedModel)
            displayName = try container.decode(String.self, forKey: .displayName)
            // A level a newer SDK adds is skipped, not a reason to lose the whole catalog.
            supportedEffortLevels = (try container.decodeIfPresent([String].self, forKey: .supportedEffortLevels) ?? [])
                .compactMap(Effort.init(rawValue:))
        }

        private enum CodingKeys: String, CodingKey {
            case value, resolvedModel, displayName, supportedEffortLevels
        }
    }

    let entries: [Entry]

    /// The entry `claude` reaches with `value`, such as the alias `opus`; `nil` when the account does not offer it.
    func entry(for value: String) -> Entry? {
        entries.first { $0.value == value }
    }
}
