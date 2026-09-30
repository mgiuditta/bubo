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
    /// The Tinta's grain; unlike spikes, not damped on a Forma.
    var grain: Float = 0
    /// The Tinta's light bands.
    var bands: Float = 0
    /// The Tinta's specular gloss.
    var gloss: Float = 0
    /// The Tinta's base and highlight colors.
    var base = Tinta.neutral.base
    var highlight = Tinta.neutral.highlight
}

extension OrbUniforms {
    /// Copies the clock, the Stato's motion and light, and the Tinta from `animation`.
    mutating func apply(_ animation: OrbAnimation) {
        time = animation.time
        amplitude = animation.motion.amplitude
        frequency = animation.motion.frequency
        speed = animation.motion.speed
        swirl = animation.motion.swirl
        glow = animation.motion.glow
        spike = animation.motion.spike + animation.tinta.spike
        audio = animation.audio
        grain = animation.tinta.grain
        bands = animation.tinta.bands
        gloss = animation.tinta.gloss
        base = animation.tinta.base
        highlight = animation.tinta.highlight
    }
}
