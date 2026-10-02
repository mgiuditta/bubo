/// A family of Claude models, as `claude` reaches its latest with an alias; weakest first.
nonisolated enum ModelFamily: String, CaseIterable, Comparable, Sendable {
    case haiku, sonnet, opus, fable

    /// The family of the model `id` names, such as `claude-opus-5-5`; `nil` when it names none.
    init?(model id: String) {
        let parts = id.split(separator: "-")
        guard let family = Self.allCases.first(where: { parts.contains(Substring($0.rawValue)) }) else { return nil }
        self = family
    }

    /// The `claude` alias of the family's latest model.
    var alias: String { rawValue }

    /// The family's name as people know it; a brand, so it is never translated.
    var name: String {
        switch self {
        case .haiku: "Haiku"
        case .sonnet: "Sonnet"
        case .opus: "Opus"
        case .fable: "Fable"
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}
