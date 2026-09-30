/// Why the Catalogo could not be loaded.
nonisolated enum CatalogoError: Error, Equatable {
    /// The bundle has no `catalogo.json`.
    case missingFile
    /// The JSON does not decode; the associated value says where.
    case malformed(String)
    /// A `nome` that is not kebab-case ASCII.
    case invalidName(String)
    /// A `nome` used by more than one Variante.
    case duplicateName(String)
    /// A `forma` used by more than one Variante.
    case duplicateForma(String)
    /// A Variante whose `parole` are not three to eight.
    case wordCount(nome: String, count: Int)
    /// A Variante with an empty `descrizione`.
    case missingDescription(String)
}
