import Foundation

/// The one list of Varianti, read from `catalogo.json`; whatever chooses or draws a Variante reads it.
nonisolated struct Catalogo: Sendable {
    /// The Catalogo in the app bundle, read once; `nil` if it is missing or broken, which `CatalogoTests` rules out.
    static let bundled = try? Catalogo(bundle: .main)

    /// How many names the agent gets for its tag `⟦orb:nome⟧`: the list goes into every prompt, so it stays short.
    static let rosaLimit = 24

    /// Every Variante, in file order.
    let varianti: [Variante]

    /// Creates the Catalogo from the `catalogo.json` in `bundle`.
    ///
    /// - Throws: `CatalogoError.missingFile` if the bundle has no Catalogo, or any error of `init(json:)`.
    init(bundle: Bundle) throws(CatalogoError) {
        guard let url = bundle.url(forResource: "catalogo", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { throw .missingFile }
        try self.init(json: data)
    }

    /// Creates the Catalogo from the contents of a `catalogo.json`, checking every rule of an entry.
    ///
    /// - Throws: A `CatalogoError` naming the first broken rule.
    init(json: Data) throws(CatalogoError) {
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: json)
        } catch {
            throw .malformed(String(describing: error))
        }
        var names = Set<String>(), forme = Set<String>()
        for variante in file.varianti {
            guard variante.nome.wholeMatch(of: /[a-z0-9]+(-[a-z0-9]+)*/) != nil else {
                throw .invalidName(variante.nome)
            }
            guard names.insert(variante.nome).inserted else { throw .duplicateName(variante.nome) }
            guard forme.insert(variante.forma).inserted else { throw .duplicateForma(variante.forma) }
            guard (3...8).contains(variante.parole.count) else {
                throw .wordCount(nome: variante.nome, count: variante.parole.count)
            }
            guard !variante.descrizione.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw .missingDescription(variante.nome)
            }
        }
        varianti = file.varianti
    }

    /// The Variante called `nome`, if the Catalogo has it.
    func variante(named nome: String) -> Variante? {
        varianti.first { $0.nome == nome }
    }

    /// The Varianti of `categoria`, in file order.
    func varianti(in categoria: Categoria) -> [Variante] {
        varianti.filter { $0.categoria == categoria }
    }

    /// The Varianti the agent may choose from while it works: the first of each Categoria, which the bridge's fallback
    /// from tools uses, then those of `categoria`, then the others in file order, at most `limit`.
    func rosa(around categoria: Categoria? = nil, limit: Int = rosaLimit) -> [Variante] {
        let firsts = Categoria.allCases.compactMap { categoria in varianti.first { $0.categoria == categoria } }
        let near = categoria.map(varianti(in:)) ?? []
        var chosen = Set<Variante>()
        return Array((firsts + near + varianti).filter { chosen.insert($0).inserted }.prefix(limit))
    }

    /// The names of the Forme the Varianti need; each must have its SDF in `Orb.metal`.
    var formaNames: Set<String> {
        Set(varianti.map(\.forma))
    }

    /// The shape of `catalogo.json`.
    private struct File: Decodable {
        let varianti: [Variante]
    }
}
