/// A Forma the renderer can draw, named as its `forma` in the Catalogo.
///
/// Each Forma is a file of its own, `Orb/Forme/<name>.metal`, whose fragment function `forma_<name>`
/// builds its pipeline (ADR 0010). A name with no such function draws the Blob.
nonisolated struct Forma: RawRepresentable, Hashable, Sendable {
    /// The Forma's name: its file in `Orb/Forme` and its `forma` in the Catalogo.
    let rawValue: String

    /// Creates the Forma called `rawValue`, whether or not the shader library has it.
    init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The rest shape every Morph starts from and returns to.
    static let blob = Forma(rawValue: "blob")
    /// The orbital diagram of the Orbite; it has no Variante in the Catalogo.
    static let orbite = Forma(rawValue: "orbite")
    /// The owl of Bubo's Segno, the Orb's greeting; it has no Variante in the Catalogo.
    static let gufo = Forma(rawValue: "gufo")

    /// The prefix of every Forma's fragment function in the shader library.
    static let fragmentFunctionPrefix = "forma_"

    /// The name of the fragment function that builds this Forma's pipeline.
    var fragmentFunctionName: String { Self.fragmentFunctionPrefix + rawValue }
}
