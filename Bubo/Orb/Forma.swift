/// A Forma the renderer can draw; the raw value is its SDF's name in `Orb.metal` and its `forma` in the Catalogo.
nonisolated enum Forma: String, CaseIterable, Sendable {
    case blob, lente, nuvola, cuore, busta, clessidra, parentesi, nota, pennello, moneta, aereo, fumetto, robot
    /// The orbital diagram of the Orbite; it has no Variante in the Catalogo.
    case orbite

    /// The value of the shader's `FORMA` function constant that builds this Forma's pipeline.
    var functionConstant: Int32 {
        switch self {
        case .blob: 0
        case .lente: 1
        case .nuvola: 2
        case .cuore: 3
        case .busta: 4
        case .clessidra: 5
        case .parentesi: 6
        case .nota: 7
        case .pennello: 8
        case .moneta: 9
        case .aereo: 10
        case .fumetto: 11
        case .robot: 12
        case .orbite: 13
        }
    }
}
