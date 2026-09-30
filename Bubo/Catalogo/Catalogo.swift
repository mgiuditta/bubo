import Foundation

/// The one list of Varianti, read from `catalogo.json`; whatever chooses or draws a Variante reads it.
nonisolated struct Catalogo: Sendable {
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

    /// The names of the Forme the Varianti need; each must have its SDF in `Orb.metal`.
    var formaNames: Set<String> {
        Set(varianti.map(\.forma))
    }

    /// The shape of `catalogo.json`.
    private struct File: Decodable {
        let varianti: [Variante]
    }
}
