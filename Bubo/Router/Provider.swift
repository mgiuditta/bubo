import Foundation

/// A model provider with its own Tinta; a provider outside this list gets the neutral Tinta.
nonisolated enum Provider: CaseIterable, Identifiable, Sendable {
    case anthropic, mistral, deepSeek, openAI, perplexity, google, meta, alibaba, cohere, xAI

    var id: Self { self }

    /// The provider's name as people know it; a brand, so it is never translated.
    var name: String {
        switch self {
        case .anthropic: "Anthropic"
        case .mistral: "Mistral"
        case .deepSeek: "DeepSeek"
        case .openAI: "OpenAI"
        case .perplexity: "Perplexity"
        case .google: "Google"
        case .meta: "Meta"
        case .alibaba: "Alibaba"
        case .cohere: "Cohere"
        case .xAI: "xAI"
        }
    }

    /// Creates the provider called `name`, ignoring case; `nil` for a provider outside the list.
    init?(named name: String) {
        guard let provider = Self.allCases.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        else { return nil }
        self = provider
    }
}
