/// The abstract signature of a model provider that the Orb takes on: color and surface character.
///
/// The Orb's color always comes from the Tinta, never from the Variante. The character is a
/// second signal after the color; spikes are damped to 0.28 on a Forma, so every signature must
/// also rely on grain, bands or gloss.
nonisolated struct Tinta: Equatable, Sendable {
    /// The body color, as sRGB components from 0 to 1.
    var base: SIMD3<Float>
    /// The color of rims, bands and halo.
    var highlight: SIMD3<Float>
    /// How spiky the surface is, on top of the Stato's spikes; damped on a Forma.
    var spike: Float = 0
    /// How grainy the surface is, from 0 to 1.
    var grain: Float = 0
    /// How dense and bright the light bands are, from 0 to 1.
    var bands: Float = 0
    /// How sharp and bright the specular highlight is, from 0 to 1.
    var gloss: Float = 0

    /// Creates a Tinta from `0xRRGGBB` colors and its character.
    init(base: UInt32, highlight: UInt32, spike: Float = 0, grain: Float = 0, bands: Float = 0, gloss: Float = 0) {
        self.base = SIMD3(hex: base)
        self.highlight = SIMD3(hex: highlight)
        self.spike = spike
        self.grain = grain
        self.bands = bands
        self.gloss = gloss
    }

    /// Creates the Tinta of `provider`, or the neutral Tinta for a provider outside the list.
    init(for provider: Provider?) {
        self = provider?.tinta ?? .neutral
    }

    /// Whether the Tinta stays recognizable on a Forma, where spikes are damped.
    var hasCharacterBeyondSpikes: Bool {
        grain > 0 || bands > 0 || gloss > 0
    }

    /// The Tinta `fraction` of the way from this one to `other`: 0 is this one, 1 is `other`.
    func mixed(with other: Tinta, by fraction: Float) -> Tinta {
        func mix(_ from: Float, _ to: Float) -> Float { from + (to - from) * fraction }
        var result = self
        result.base += (other.base - base) * fraction
        result.highlight += (other.highlight - highlight) * fraction
        result.spike = mix(spike, other.spike)
        result.grain = mix(grain, other.grain)
        result.bands = mix(bands, other.bands)
        result.gloss = mix(gloss, other.gloss)
        return result
    }
}

nonisolated extension SIMD3 where Scalar == Float {
    /// Creates red, green and blue components from 0 to 1 out of a `0xRRGGBB` literal.
    init(hex: UInt32) {
        self.init(Float((hex >> 16) & 0xFF), Float((hex >> 8) & 0xFF), Float(hex & 0xFF))
        self /= 255
    }
}
