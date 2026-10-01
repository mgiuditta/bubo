import Foundation
import Testing
@testable import Bubo

/// The provisional list of every Variante planned for the Catalogo (`docs/catalogo-elenco.json`, #377).
///
/// It is not `catalogo.json`: it stays out of the app bundle, holds Varianti that have no Forma yet,
/// and has its own shape (blocks of 24, a silhouette idea and two sample requests per entry).
struct CatalogoElencoTests {
    private struct Elenco: Decodable {
        let gruppi: [Gruppo]
        let blocchi: [Blocco]

        var voci: [Voce] { blocchi.flatMap(\.varianti) }
    }

    private struct Gruppo: Decodable {
        let categoria: Categoria
        let nome: String
        let descrizione: String
    }

    private struct Blocco: Decodable {
        let numero: Int
        let varianti: [Voce]
    }

    private struct Voce: Decodable {
        let nome: String
        let categoria: Categoria
        let gruppo: String?
        let descrizione: String
        let silhouette: String
        let moto: String?
        let esempi: [String: String]
    }

    /// The list a model reads in one pass: a Categoria, or one of its gruppi when it has them.
    private struct Rosa: Hashable {
        let categoria: Categoria
        let gruppo: String?
    }

    /// Entries per block; the Catalogo grows one block at a time.
    private static let blockSize = 24
    /// At most this many entries in one rosa, so a pass of the on-device model stays well inside its context.
    private static let maxRosaCount = 40
    /// At most this many characters of `nome: descrizione` lines in one rosa (about 1,000 tokens).
    private static let maxRosaCharacters = 3_000

    private static let loaded = Result {
        let url = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../docs/catalogo-elenco.json").standardized
        return try JSONDecoder().decode(Elenco.self, from: Data(contentsOf: url))
    }

    @Test func theListHas480To520UniqueKebabCaseNames() throws {
        let names = try Self.loaded.get().voci.map(\.nome)
        #expect((480...520).contains(names.count))
        #expect(Set(names).count == names.count)
        for name in names {
            #expect(name.wholeMatch(of: /[a-z0-9]+(-[a-z0-9]+)*/) != nil, "\(name)")
        }
    }

    @Test func blocksAreNumberedInOrderAndHold24EntriesEach() throws {
        let blocchi = try Self.loaded.get().blocchi
        #expect(blocchi.map(\.numero) == Array(1...blocchi.count))
        for blocco in blocchi {
            #expect(blocco.varianti.count == Self.blockSize, "block \(blocco.numero)")
        }
    }

    @Test func everyEntryHasADescriptionASilhouetteAndAnItalianAndEnglishExample() throws {
        let voci = try Self.loaded.get().voci
        for voce in voci {
            #expect(!voce.descrizione.trimmingCharacters(in: .whitespaces).isEmpty, "\(voce.nome)")
            #expect(!voce.silhouette.trimmingCharacters(in: .whitespaces).isEmpty, "\(voce.nome)")
            #expect(voce.moto.map { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? true, "\(voce.nome)")
            #expect(Set(voce.esempi.keys) == ["it", "en"], "\(voce.nome)")
            #expect(voce.esempi.values.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, "\(voce.nome)")
        }
        let examples = voci.flatMap(\.esempi.values)
        #expect(Set(examples).count == examples.count)
    }

    @Test func everyCategoriaHasEntries() throws {
        let used = Set(try Self.loaded.get().voci.map(\.categoria))
        #expect(used == Set(Categoria.allCases))
    }

    @Test func aCategoriaIsSplitIntoDeclaredGruppiOrNotAtAll() throws {
        let elenco = try Self.loaded.get()
        let declared = Set(elenco.gruppi.map { Rosa(categoria: $0.categoria, gruppo: $0.nome) })
        #expect(declared.count == elenco.gruppi.count)
        #expect(elenco.gruppi.allSatisfy { !$0.descrizione.trimmingCharacters(in: .whitespaces).isEmpty })
        let grouped = Set(elenco.gruppi.map(\.categoria))
        for voce in elenco.voci {
            if grouped.contains(voce.categoria) {
                #expect(declared.contains(Rosa(categoria: voce.categoria, gruppo: voce.gruppo)), "\(voce.nome)")
            } else {
                #expect(voce.gruppo == nil, "\(voce.nome)")
            }
        }
        let used = Set(elenco.voci.map { Rosa(categoria: $0.categoria, gruppo: $0.gruppo) })
        #expect(declared.isSubset(of: used))
    }

    @Test func everyRosaFitsOnePassOfTheModel() throws {
        let rose = Dictionary(grouping: try Self.loaded.get().voci) { Rosa(categoria: $0.categoria, gruppo: $0.gruppo) }
        for (rosa, voci) in rose {
            let characters = voci.reduce(0) { $0 + "\($1.nome): \($1.descrizione)\n".count }
            #expect(voci.count <= Self.maxRosaCount, "\(rosa)")
            #expect(characters <= Self.maxRosaCharacters, "\(rosa)")
        }
    }

    @Test func everyCatalogoVarianteIsListedWithTheSameCategoriaAndDescription() throws {
        let voci = Dictionary(uniqueKeysWithValues: try Self.loaded.get().voci.map { ($0.nome, $0) })
        for variante in try Catalogo(bundle: .main).varianti {
            let voce = try #require(voci[variante.nome], "\(variante.nome)")
            #expect(voce.categoria == variante.categoria, "\(variante.nome)")
            #expect(voce.descrizione == variante.descrizione, "\(variante.nome)")
        }
    }

    @Test func theFirstBlockStartsWithTheVariantiAlreadyDrawn() throws {
        let first = try #require(try Self.loaded.get().blocchi.first).varianti.map(\.nome)
        let drawn = try Catalogo(bundle: .main).varianti.map(\.nome)
        #expect(Array(first.prefix(drawn.count)) == drawn)
    }
}
