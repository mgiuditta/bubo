import Foundation
import Metal
import Testing
@testable import Bubo

struct CatalogoTests {
    private static let bundled = Result { try Catalogo(bundle: .main) }

    private static func json(_ varianti: String) -> Data {
        Data(#"{"varianti": [\#(varianti)]}"#.utf8)
    }

    private static func entry(nome: String = "lente", forma: String = "lente", categoria: String = "ricerca",
                              descrizione: String = "Quando Bubo cerca.",
                              parole: [String] = ["cerca", "trova", "lente"], ritirata: String? = nil) -> String {
        let words = parole.map { #""\#($0)""# }.joined(separator: ", ")
        let retired = ritirata.map { #", "ritirata": "\#($0)""# } ?? ""
        return #"{"nome": "\#(nome)", "forma": "\#(forma)", "categoria": "\#(categoria)", "descrizione": "\#(descrizione)", "parole": [\#(words)]\#(retired)}"#
    }

    // MARK: - The real catalogo.json

    @Test func theBundledCatalogoLoads() throws {
        let catalogo = try Self.bundled.get()
        #expect(!catalogo.varianti.isEmpty)
    }

    @Test func lenteIsTheRicercaVariante() throws {
        let catalogo = try Self.bundled.get()
        let lente = try #require(catalogo.variante(named: "lente"))
        #expect(lente.forma == "lente")
        #expect(lente.categoria == .ricerca)
        #expect(catalogo.varianti(in: .ricerca).contains(lente))
    }

    // MARK: - The rosa for the tag ⟦orb:nome⟧

    @Test func theRosaOfTheBundledCatalogoNamesTheVarianti() throws {
        let catalogo = try Self.bundled.get()
        #expect(Set(catalogo.rosa()).isSubset(of: Set(catalogo.varianti)))
        #expect(catalogo.rosa().count == min(catalogo.varianti.count, Catalogo.rosaLimit))
    }

    @Test func theRosaKeepsTheFirstOfEachCategoriaThenTheCategoriaAskedFor() throws {
        let catalogo = try Catalogo(json: Self.json([
            Self.entry(nome: "lente", forma: "lente"),
            Self.entry(nome: "binocolo", forma: "binocolo"),
            Self.entry(nome: "radar", forma: "radar"),
            Self.entry(nome: "parentesi", forma: "parentesi", categoria: "codice"),
            Self.entry(nome: "terminale", forma: "terminale", categoria: "codice"),
        ].joined(separator: ",")))

        #expect(catalogo.rosa(around: .codice, limit: 3).map(\.nome) == ["parentesi", "lente", "terminale"])
        #expect(catalogo.rosa(limit: 3).map(\.nome) == ["parentesi", "lente", "binocolo"])
        #expect(catalogo.rosa(around: .ricerca).count == 5)
    }

    @Test func everyCategoriaHasAVariante() throws {
        let catalogo = try Self.bundled.get()
        for categoria in Categoria.allCases {
            #expect(!catalogo.varianti(in: categoria).isEmpty, "\(categoria)")
        }
    }

    @Test func bundledNamesAreUniqueKebabCaseASCII() throws {
        let names = try Self.bundled.get().varianti.map(\.nome)
        #expect(Set(names).count == names.count)
        for name in names {
            #expect(name.wholeMatch(of: /[a-z0-9]+(-[a-z0-9]+)*/) != nil, "\(name)")
        }
    }

    @Test func bundledVariantiHaveThreeToEightWords() throws {
        for variante in try Self.bundled.get().varianti {
            #expect((3...8).contains(variante.parole.count), "\(variante.nome)")
        }
    }

    /// The Forme the app's shader library draws, read from its `forma_<name>` fragment functions.
    private static func drawnForme() throws -> Set<String> {
        let library = try #require(MTLCreateSystemDefaultDevice()?.makeDefaultLibrary())
        return Set(library.functionNames.filter { $0.hasPrefix(Forma.fragmentFunctionPrefix) }
            .map { String($0.dropFirst(Forma.fragmentFunctionPrefix.count)) })
    }

    @Test func everyBundledFormaHasItsSDFAndEverySDFIsUsed() throws {
        let required = try Self.bundled.get().formaNames
        // The Blob is no Variante, and the Orbite's and the owl's Forme are drawn for the Orbite and the greeting
        // alone, never through the Catalogo.
        let drawn = try Self.drawnForme().subtracting([Forma.blob.rawValue, Forma.orbite.rawValue, Forma.gufo.rawValue])
        #expect(required == drawn)
    }

    /// One Forma per file: `Orb/Forme/<name>.metal` makes `forma_<name>` and nothing else does.
    @Test func eachFormaIsTheFileNamedAfterIt() throws {
        let folder = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../Bubo/Orb/Forme").standardized
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "metal" }
        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(source.contains("ORB_FORMA(\(name))") || source.contains("ORB_FORMA_SDF(\(name),"), "\(name)")
        }
        let names = Set(files.map { $0.deletingPathExtension().lastPathComponent })
        let drawn = try Self.drawnForme()
        #expect(drawn == names.union([Forma.blob.rawValue]))
    }

    @Test(arguments: ["it", "en"])
    func everyBundledVarianteHasALabel(language: String) throws {
        let url = try #require(Bundle.main.url(forResource: language, withExtension: "lproj"))
        let localized = try #require(Bundle(url: url))
        for variante in try Self.bundled.get().varianti {
            #expect(variante.label.key == variante.nome)
            let label = localized.localizedString(forKey: variante.nome, value: "∅", table: variante.label.table)
            #expect(label != "∅" && label != variante.nome, "\(variante.nome) in \(language)")
        }
    }

    // MARK: - Loading rules

    @Test func findsVariantiByNameAndCategoria() throws {
        let catalogo = try Catalogo(json: Self.json(
            Self.entry() + ", " + Self.entry(nome: "busta", forma: "busta", categoria: "mail")))
        #expect(catalogo.variante(named: "busta")?.categoria == .mail)
        #expect(catalogo.variante(named: "drago") == nil)
        #expect(catalogo.varianti(in: .mail).map(\.nome) == ["busta"])
        #expect(catalogo.varianti(in: .meteo).isEmpty)
        #expect(catalogo.formaNames == ["lente", "busta"])
    }

    @Test(arguments: ["", "{", "[]", #"{"varianti": {}}"#, #"{"varianti": [{"nome": "lente"}]}"#])
    func malformedJSONIsAnExplicitError(json: String) {
        #expect {
            try Catalogo(json: Data(json.utf8))
        } throws: { error in
            if case .malformed = error as? CatalogoError { true } else { false }
        }
    }

    @Test func anUnknownCategoriaIsMalformed() {
        #expect {
            try Catalogo(json: Self.json(Self.entry(categoria: "sport")))
        } throws: { error in
            if case .malformed = error as? CatalogoError { true } else { false }
        }
    }

    @Test(arguments: ["Lente", "lente_rossa", "lente rossa", "lénte", "-lente", "lente-", "lente--rossa", ""])
    func namesMustBeKebabCaseASCII(name: String) {
        #expect(throws: CatalogoError.invalidName(name)) {
            try Catalogo(json: Self.json(Self.entry(nome: name)))
        }
    }

    @Test func namesMustBeUnique() {
        #expect(throws: CatalogoError.duplicateName("lente")) {
            try Catalogo(json: Self.json(Self.entry() + ", " + Self.entry(forma: "altra")))
        }
    }

    @Test func eachFormaServesOneVariante() {
        #expect(throws: CatalogoError.duplicateForma("lente")) {
            try Catalogo(json: Self.json(Self.entry() + ", " + Self.entry(nome: "lente-grande")))
        }
    }

    @Test(arguments: [2, 9])
    func wordsMustBeThreeToEight(count: Int) {
        let words = (0..<count).map { "parola\($0)" }
        #expect(throws: CatalogoError.wordCount(nome: "lente", count: count)) {
            try Catalogo(json: Self.json(Self.entry(parole: words)))
        }
    }

    @Test func aDescriptionIsRequired() {
        #expect(throws: CatalogoError.missingDescription("lente")) {
            try Catalogo(json: Self.json(Self.entry(descrizione: " ")))
        }
    }

    @Test func aBundleWithoutTheFileIsAnExplicitError() {
        #expect(throws: CatalogoError.missingFile) {
            try Catalogo(bundle: Bundle(for: BundleMarker.self))
        }
    }

    // MARK: - Retired Varianti and stable names (#401)

    /// A Catalogo with `binocolo` retired, first of its Categoria.
    private static func catalogoWithRetiredBinocolo() throws -> Catalogo {
        try Catalogo(json: json([
            entry(nome: "binocolo", forma: "binocolo", parole: ["binocolo", "osserva", "scruta"], ritirata: "#401"),
            entry(nome: "lente", forma: "lente"),
            entry(nome: "radar", forma: "radar", parole: ["radar", "scansiona", "rileva"]),
        ].joined(separator: ",")))
    }

    @Test func aRetiredVarianteKeepsItsNameAndForma() throws {
        let binocolo = try #require(try Self.catalogoWithRetiredBinocolo().variante(named: "binocolo"))
        #expect(binocolo.isRetired)
        #expect(binocolo.ritirata == "#401")
        #expect(binocolo.forma == "binocolo")
    }

    @Test func aRetiredVarianteIsNeverChosen() throws {
        let catalogo = try Self.catalogoWithRetiredBinocolo()
        #expect(catalogo.attive.map(\.nome) == ["lente", "radar"])
        #expect(catalogo.varianti(in: .ricerca).map(\.nome) == ["lente", "radar"])
        #expect(catalogo.rosa(around: .ricerca).map(\.nome) == ["lente", "radar"])
        #expect(!FoundationModelsClassifier.instructions(choosingAmong: catalogo.varianti(in: .ricerca)).contains("binocolo"))
    }

    @Test func theRulesNeverChooseARetiredVariante() throws {
        let rules = RuleClassifier(catalogo: try Self.catalogoWithRetiredBinocolo())
        let result = rules.classification(of: ClassifierInput(text: "Cerca con il binocolo, osserva e scruta"))
        #expect(result.variante?.nome != "binocolo")
    }

    /// A retired name that still arrives, from an old tag or conversation, turns the Orb: its Forma is still there.
    @Test func theOrbShowsARetiredNameThatStillArrives() throws {
        let orb = OrbControls()
        orb.showWork("binocolo", in: try Self.catalogoWithRetiredBinocolo())
        #expect(orb.variante?.nome == "binocolo")
    }

    /// Every name ever in `catalogo.json` stays there, active or retired: renaming or removing one fails here.
    @Test func noNameOfTheHistoryDisappears() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appending(path: "BuboTests/Fixtures/catalogo-nomi.json")
        let history = try JSONDecoder().decode(NameHistory.self, from: Data(contentsOf: url))
        let names = Set(try Self.bundled.get().varianti.map(\.nome))
        let missing = history.nomi.filter { !names.contains($0) }
        #expect(missing.isEmpty, "A name never leaves catalogo.json: retire it instead. Missing: \(missing)")
        let unrecorded = names.subtracting(history.nomi)
        #expect(unrecorded.isEmpty, "Append the new names to catalogo-nomi.json: \(unrecorded.sorted())")
    }
}

/// The shape of `catalogo-nomi.json`: every name ever in the Catalogo, only ever appended to.
private struct NameHistory: Decodable {
    let nomi: [String]
}

/// A class in the test bundle, which has no catalogo.json.
private final class BundleMarker {}
