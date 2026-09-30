/// A Forma the renderer can draw; the raw value is its SDF's name in `Orb.metal` and its `forma` in the Catalogo.
nonisolated enum Forma: String, CaseIterable, Sendable {
    case blob, lente

    /// The value of the shader's `FORMA` function constant that builds this Forma's pipeline.
    var functionConstant: Int32 {
        switch self {
        case .blob: 0
        case .lente: 1
        }
    }
}
