/// The per-frame parameters of the Orb shader; the layout matches `Uniforms` in `Orb.metal`.
struct OrbUniforms {
    var resolution: SIMD2<Float> = .zero
    var time: Float = 0
    var amplitude: Float = 0.07
    var frequency: Float = 1.5
    var speed: Float = 0.3
    var swirl: Float = 0
    var spike: Float = 0
    var glow: Float = 0.9
    var audio: Float = 0
    /// The halo margin: values above 1 shrink the Orb so the halo fades inside the view.
    var frame: Float = 1.3
    /// How far the Orb has turned from the Blob into the pipeline's Forma: 0 is Blob, 1 is the Forma.
    var morph: Float = 0
    /// How opaque the whole Orb is, halo included: below 1 only while fading with Reduce Motion on.
    var opacity: Float = 1
    // ponytail: provisional Anthropic Tinta; the provider palette comes with the Tinte ticket.
    var base = SIMD3<Float>(0xD9, 0x77, 0x57) / 255
    var highlight = SIMD3<Float>(0xFF, 0xC3, 0xA0) / 255
}

extension OrbUniforms {
    /// Copies the clock and the Stato's motion and light from `animation`.
    mutating func apply(_ animation: OrbAnimation) {
        time = animation.time
        amplitude = animation.motion.amplitude
        frequency = animation.motion.frequency
        speed = animation.motion.speed
        swirl = animation.motion.swirl
        glow = animation.motion.glow
        spike = animation.motion.spike
        audio = animation.audio
    }

    /// Swaps the Tinta for greys, as the Galleria del Catalogo draws: there only silhouette and halo count.
    mutating func applyMonochromeTinta() {
        base = SIMD3(repeating: 0.6)
        highlight = SIMD3(repeating: 0.92)
    }
}
