/// The per-frame parameters of the Orb shader; the layout matches `Uniforms` in `Orb.metal`.
struct OrbUniforms {
    var resolution: SIMD2<Float> = .zero
    var time: Float = 0
    // ponytail: parameters of Riposo only; Stati interpolate these with the debug panel ticket.
    var amplitude: Float = 0.07
    var frequency: Float = 1.5
    var speed: Float = 0.3
    var swirl: Float = 0
    var spike: Float = 0
    var glow: Float = 0.9
    var audio: Float = 0
    /// The halo margin: values above 1 shrink the Orb so the halo fades inside the view.
    var frame: Float = 1.3
    // ponytail: provisional Anthropic Tinta; the provider palette comes with the Tinte ticket.
    var base = SIMD3<Float>(0xD9, 0x77, 0x57) / 255
    var highlight = SIMD3<Float>(0xFF, 0xC3, 0xA0) / 255
}
