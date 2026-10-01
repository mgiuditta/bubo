/// A family of Claude models, as `claude` reaches its latest with an alias.
nonisolated enum ModelFamily: String, CaseIterable, Sendable {
    case haiku, sonnet, opus

    /// The `claude` alias of the family's latest model.
    var alias: String { rawValue }

    /// The family's name as people know it; a brand, so it is never translated.
    var name: String {
        switch self {
        case .haiku: "Haiku"
        case .sonnet: "Sonnet"
        case .opus: "Opus"
        }
    }
}
