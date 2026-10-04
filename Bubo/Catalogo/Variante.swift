import Foundation

/// A named entry of the Catalogo: it ties a stable name to one Forma and one Categoria.
///
/// Colour comes from the Tinta and motion from the Forma's shader, so neither is here.
nonisolated struct Variante: Hashable, Identifiable, Decodable, Sendable {
    /// The stable name: Italian, kebab-case, ASCII; never renamed, at most retired.
    let nome: String
    /// The name of the Forma, its file in `Orb/Forme`; one Forma per Variante.
    let forma: String
    /// The thematic group.
    let categoria: Categoria
    /// One line on when to choose it.
    let descrizione: String
    /// Three to eight words, synonyms included, that point to it.
    let parole: [String]
    /// When and why it was retired, a date or a ticket; `nil` while it may be chosen.
    ///
    /// A retired Variante keeps its name, Forma and label, so an old tag still finds it, but nothing chooses it any more.
    var ritirata: String? = nil

    var id: String { nome }

    /// Whether the Variante is retired: the router and the agent no longer choose it.
    var isRetired: Bool { ritirata != nil }

    /// The name shown to the user, from the `Catalogo` String Catalog keyed by `nome`.
    var label: LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(nome), table: "Catalogo")
    }
}
