import Foundation
import Testing
@testable import Bubo

/// The Galleria by blocco (#400): the Varianti of a blocco in the elenco's order, drawn or still to draw.
struct GalleriaTests {
    private static let catalogo = Result {
        try Catalogo(json: Data(#"""
            {"varianti": [
              {"nome": "radar", "forma": "radar", "categoria": "ricerca", "descrizione": "Quando Bubo scandaglia.", "parole": ["radar", "scansiona", "rileva"]},
              {"nome": "lente", "forma": "lente", "categoria": "ricerca", "descrizione": "Quando Bubo cerca.", "parole": ["cerca", "trova", "lente"]}
            ]}
            """#.utf8))
    }

    private static let elenco = Result {
        try CatalogoElenco(json: Data(#"""
            {"versione": 1, "gruppi": [], "blocchi": [
              {"numero": 1, "varianti": [
                {"nome": "lente", "categoria": "ricerca", "descrizione": "Quando Bubo cerca.", "silhouette": "Una lente.", "esempi": {}},
                {"nome": "binocolo", "categoria": "ricerca", "descrizione": "Quando Bubo osserva.", "silhouette": "Due tubi.", "moto": "Mette a fuoco.", "esempi": {}},
                {"nome": "nuvola", "categoria": "meteo", "descrizione": "Quando piove.", "silhouette": "Tre sbuffi.", "esempi": {}},
                {"nome": "gufo", "categoria": "creativo", "descrizione": "Il Segno.", "silhouette": "Un gufo.", "esempi": {}}
              ]},
              {"numero": 2, "varianti": [
                {"nome": "radar", "categoria": "ricerca", "descrizione": "Quando Bubo scandaglia.", "silhouette": "Un piatto.", "esempi": {}}
              ]}
            ]}
            """#.utf8))
    }

    @Test func aBloccoShowsItsVariantiInTheElencoOrderThoseToDrawIncluded() throws {
        let cells = GalleriaCell.cells(of: try Self.catalogo.get(), elenco: try Self.elenco.get(), blocco: 1, categoria: nil)
        #expect(cells.map(\.nome) == ["lente", "binocolo", "nuvola", "gufo"])
        #expect(cells.map(\.isToDraw) == [false, true, true, false], "the owl of the Segno has its Forma")
        #expect(cells[1].voce?.moto == "Mette a fuoco.")
    }

    @Test func theCategoriaNarrowsTheBlocco() throws {
        let cells = GalleriaCell.cells(of: try Self.catalogo.get(), elenco: try Self.elenco.get(), blocco: 1, categoria: .ricerca)
        #expect(cells.map(\.nome) == ["lente", "binocolo"])
    }

    @Test func withoutABloccoTheCatalogoComesWithWhatTheElencoPlanned() throws {
        let cells = GalleriaCell.cells(of: try Self.catalogo.get(), elenco: try Self.elenco.get(), blocco: nil, categoria: nil)
        #expect(cells.map(\.nome) == ["radar", "lente"])
        #expect(cells.allSatisfy { !$0.isToDraw && $0.voce != nil })
    }

    @Test func theCounterCountsTheDrawnOnes() throws {
        let blocco = try #require(try Self.elenco.get().blocco(1))
        #expect(GalleriaCell.drawnCount(of: blocco, in: try Self.catalogo.get()) == 2)
    }

    /// The Debug app carries the whole elenco: 20 blocchi of 24, every Variante of the Catalogo among them.
    @Test func theDebugBundleCarriesTheElenco() throws {
        let elenco = try CatalogoElenco(bundle: .main)
        #expect(elenco.blocchi.map(\.numero) == Array(1...20))
        #expect(elenco.blocchi.allSatisfy { $0.varianti.count == 24 })
        let catalogo = try Catalogo(bundle: .main)
        #expect(catalogo.varianti.allSatisfy { elenco.voce(named: $0.nome) != nil })
    }
}
