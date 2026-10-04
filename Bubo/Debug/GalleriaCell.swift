#if DEBUG
import Foundation

/// One cell of the Galleria: a Variante of the Catalogo, a planned one of the elenco, or usually both.
nonisolated struct GalleriaCell: Identifiable, Sendable {
    let nome: String
    let categoria: Categoria
    /// The Variante, when its Forma is drawn and it is in `catalogo.json`.
    let variante: Variante?
    /// What the elenco plans for it, when the Galleria has the elenco.
    let voce: CatalogoElenco.Voce?

    var id: String { nome }

    /// Whether the Variante still waits for its Forma.
    var isToDraw: Bool { variante == nil }

    /// The cells the Galleria shows: the Varianti of the Catalogo, or with `blocco` the Varianti of that blocco in the
    /// elenco's order, drawn or not; either way only those of `categoria`, when one is given.
    static func cells(of catalogo: Catalogo, elenco: CatalogoElenco?, blocco: Int?, categoria: Categoria?) -> [GalleriaCell] {
        let all: [GalleriaCell] = if let blocco {
            (elenco?.blocco(blocco)?.varianti ?? []).map { voce in
                GalleriaCell(nome: voce.nome, categoria: voce.categoria, variante: drawnVariante(named: voce.nome, in: catalogo),
                             voce: voce)
            }
        } else {
            catalogo.varianti.map { variante in
                GalleriaCell(nome: variante.nome, categoria: variante.categoria, variante: variante,
                             voce: elenco?.voce(named: variante.nome))
            }
        }
        return categoria.map { categoria in all.filter { $0.categoria == categoria } } ?? all
    }

    /// How many Varianti of `blocco` have their Forma.
    static func drawnCount(of blocco: CatalogoElenco.Blocco, in catalogo: Catalogo) -> Int {
        blocco.varianti.count { drawnVariante(named: $0.nome, in: catalogo) != nil }
    }

    /// The Variante called `nome` with its Forma: from the Catalogo, or the owl of the Segno, which the elenco plans
    /// but no Domanda may choose, so it stays out of `catalogo.json`.
    private static func drawnVariante(named nome: String, in catalogo: Catalogo) -> Variante? {
        catalogo.variante(named: nome) ?? (nome == Gufo.variante.nome ? Gufo.variante : nil)
    }
}
#endif
