#if DEBUG
import Foundation

/// The planned list of Varianti, `docs/catalogo-elenco.json` (#377), in blocchi of 24, those without a Forma included.
///
/// Only Debug builds carry it, for the Galleria to show what a blocco still lacks (#400); the Release has none of it.
nonisolated struct CatalogoElenco: Sendable {
    /// One planned Variante: what the model reads to choose it, and the idea of its Forma.
    struct Voce: Decodable, Hashable, Identifiable, Sendable {
        let nome: String
        let categoria: Categoria
        /// When to choose it, as the router's model reads it.
        let descrizione: String
        /// The idea of the Forma at 64 pt in monochrome.
        let silhouette: String
        /// Its own motion, if it has one.
        let moto: String?

        var id: String { nome }
    }

    /// A blocco of the elenco: the Varianti drawn together, in the elenco's order.
    struct Blocco: Decodable, Identifiable, Sendable {
        let numero: Int
        let varianti: [Voce]

        var id: Int { numero }
    }

    /// Every blocco, in order.
    let blocchi: [Blocco]
    private let vociByName: [String: Voce]

    /// Creates the elenco from the `catalogo-elenco.json` in `bundle`.
    ///
    /// - Throws: `CatalogoError.missingFile` if the bundle has no elenco, or any error of `init(json:)`.
    init(bundle: Bundle) throws(CatalogoError) {
        guard let url = bundle.url(forResource: "catalogo-elenco", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { throw .missingFile }
        try self.init(json: data)
    }

    /// Creates the elenco from the contents of a `catalogo-elenco.json`.
    ///
    /// - Throws: `CatalogoError.malformed` if the JSON does not decode.
    init(json: Data) throws(CatalogoError) {
        do {
            blocchi = try JSONDecoder().decode(File.self, from: json).blocchi
        } catch {
            throw .malformed(String(describing: error))
        }
        vociByName = Dictionary(blocchi.flatMap(\.varianti).map { ($0.nome, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The planned Variante called `nome`, if the elenco has it.
    func voce(named nome: String) -> Voce? {
        vociByName[nome]
    }

    /// The blocco numbered `numero`, if the elenco has it.
    func blocco(_ numero: Int) -> Blocco? {
        blocchi.first { $0.numero == numero }
    }

    /// The shape of `catalogo-elenco.json`; the gruppi and the esempi are the router's, not the Galleria's.
    private struct File: Decodable {
        let blocchi: [Blocco]
    }
}
#endif
