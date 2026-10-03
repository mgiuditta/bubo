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

    /// The fields an entry may have; `JSONDecoder` would silently drop a misspelled one.
    private static let fields: Set<String> = ["nome", "categoria", "gruppo", "descrizione", "silhouette", "moto", "esempi"]

    private static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let data = Result { try Data(contentsOf: root.appending(path: "docs/catalogo-elenco.json")) }
    private static let loaded = Result { try JSONDecoder().decode(Elenco.self, from: data.get()) }

    /// The texts of the labelled set of #85, which measures the router on requests it has never seen.
    private static func labelledRequests() throws -> [String] {
        struct LabelledSet: Decodable {
            struct Request: Decodable { let testo: String }
            let richieste: [Request]
        }
        let url = root.appending(path: "BuboTests/Fixtures/richieste-etichettate.json")
        return try JSONDecoder().decode(LabelledSet.self, from: Data(contentsOf: url)).richieste.map(\.testo)
    }

    /// `text` lowercased, without punctuation and with single spaces around every word, to compare requests.
    private static func normalized(_ text: String) -> String {
        " " + text.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ") + " "
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
        func isBlank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for voce in voci {
            #expect(!isBlank(voce.descrizione), "\(voce.nome)")
            #expect(!isBlank(voce.silhouette), "\(voce.nome)")
            #expect(voce.moto.map { !isBlank($0) } ?? true, "\(voce.nome)")
            #expect(Set(voce.esempi.keys) == ["it", "en"], "\(voce.nome)")
            #expect(!voce.esempi.values.contains(where: isBlank), "\(voce.nome)")
        }
        let examples = voci.flatMap(\.esempi.values)
        #expect(Set(examples).count == examples.count)
    }

    @Test func everyEntryHasOnlyKnownFields() throws {
        let json = try #require(try JSONSerialization.jsonObject(with: Self.data.get()) as? [String: Any])
        let blocchi = try #require(json["blocchi"] as? [[String: Any]])
        for blocco in blocchi {
            for voce in try #require(blocco["varianti"] as? [[String: Any]]) {
                let unknown = Set(voce.keys).subtracting(Self.fields)
                #expect(unknown.isEmpty, "\(voce["nome"] ?? "?"): \(unknown.sorted())")
            }
        }
    }

    @Test func noExampleRepeatsARequestOfTheLabelledSet() throws {
        let labelled = try Self.labelledRequests().map(Self.normalized)
        for voce in try Self.loaded.get().voci {
            for example in voce.esempi.values.map(Self.normalized) {
                #expect(!labelled.contains { $0.contains(example) || example.contains($0) }, "\(voce.nome): \(example)")
            }
        }
    }

    @Test func everyCategoriaHasEntries() throws {
        let used = Set(try Self.loaded.get().voci.map(\.categoria))
        #expect(used == Set(Categoria.allCases))
    }

    @Test func aCategoriaIsSplitIntoDeclaredGruppiOrNotAtAll() throws {
        let elenco = try Self.loaded.get()
        let declared = Set(elenco.gruppi.map { Rosa(categoria: $0.categoria, gruppo: $0.nome) })
        #expect(declared.count == elenco.gruppi.count)
        #expect(elenco.gruppi.allSatisfy { !$0.descrizione.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        let grouped = Set(elenco.gruppi.map(\.categoria))
        // The first pass chooses among the Categorie without gruppi and every gruppo: it is a rosa too.
        #expect(Categoria.allCases.count - grouped.count + elenco.gruppi.count <= Self.maxRosaCount)
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
        // A duplicate name fails `theListHas480To520UniqueKebabCaseNames`, not the whole test process.
        let voci = Dictionary(try Self.loaded.get().voci.map { ($0.nome, $0) }) { first, _ in first }
        for variante in try Catalogo(bundle: .main).varianti {
            let voce = try #require(voci[variante.nome], "\(variante.nome)")
            #expect(voce.categoria == variante.categoria, "\(variante.nome)")
            #expect(voce.descrizione == variante.descrizione, "\(variante.nome)")
        }
    }

    @Test func theVariantiAlreadyDrawnAreInTheElenco() throws {
        let names = try Self.loaded.get().voci.map(\.nome)
        let drawn = try Catalogo(bundle: .main).varianti.map(\.nome)
        #expect(Set(drawn).isSubset(of: names))
    }
}
