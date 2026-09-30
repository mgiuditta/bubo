/// The Tinte of the providers, next to the other design tokens.
///
/// Hues sit about 30° apart so they stay distinct at 64 pt on dark and on light; where two
/// stay close, the character tells them apart. Values from the `prototype/tinta` prototype.
nonisolated extension Tinta {
    /// Anthropic: terracotta, soft bands.
    static let anthropic = Tinta(base: 0xD97757, highlight: 0xFFC3A0, bands: 0.45, gloss: 0.3)
    /// Mistral: amber, light spikes and bands.
    static let mistral = Tinta(base: 0xE0A040, highlight: 0xFFE2A6, spike: 0.12, bands: 0.6)
    /// DeepSeek: green, fine grain.
    static let deepSeek = Tinta(base: 0x8DB548, highlight: 0xDDF5B0, grain: 0.9, bands: 0.2)
    /// OpenAI: teal, glassy.
    static let openAI = Tinta(base: 0x3FAE8F, highlight: 0xB5F0DE, bands: 0.15, gloss: 0.95)
    /// Perplexity: cyan, grain and gloss.
    static let perplexity = Tinta(base: 0x36A9C0, highlight: 0xB2EEF7, grain: 0.5, gloss: 0.7)
    /// Google: blue, dense bands.
    static let google = Tinta(base: 0x4F7FE0, highlight: 0xBCD0FF, bands: 1, gloss: 0.4)
    /// Meta: indigo, medium grain.
    static let meta = Tinta(base: 0x6A62DE, highlight: 0xC9C5FF, grain: 0.45, bands: 0.35)
    /// Alibaba: violet, bands and gloss.
    static let alibaba = Tinta(base: 0x9A66DD, highlight: 0xDCC8FF, bands: 0.75, gloss: 0.6)
    /// Cohere: pink, matte and soft.
    static let cohere = Tinta(base: 0xD07FB0, highlight: 0xFFD3EA, bands: 0.3, gloss: 0.1)
    /// xAI: cold silver, lighter than the neutral Tinta, high gloss, light grain and spikes.
    static let xAI = Tinta(base: 0xC8CCD4, highlight: 0xF4F6FA, spike: 0.35, grain: 0.3, gloss: 0.95)
    /// A provider outside the list: warm matte grey, without character.
    static let neutral = Tinta(base: 0x9C918A, highlight: 0xE2D9D2)
}

nonisolated extension Provider {
    /// The Tinta the Orb takes on when this provider answers.
    var tinta: Tinta {
        switch self {
        case .anthropic: .anthropic
        case .mistral: .mistral
        case .deepSeek: .deepSeek
        case .openAI: .openAI
        case .perplexity: .perplexity
        case .google: .google
        case .meta: .meta
        case .alibaba: .alibaba
        case .cohere: .cohere
        case .xAI: .xAI
        }
    }
}
