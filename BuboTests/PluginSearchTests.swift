import Foundation
import Testing
@testable import Bubo

/// The one search of the Plugin window, over every Marketplace.
struct PluginSearchTests {
    static let entry = PluginEntry(id: PluginID(name: "code-simplifier", marketplace: "ufficiale"), displayName: "Semplificatore",
                                   summary: "Rende il codice più leggibile", category: "development", tags: ["refactoring"])

    @Test(arguments: ["code", "simpl", "code-sim", "semplif", "leggib", "develop", "refact", "CODICE", "piu", "Più leggi"])
    func anEntryIsFoundByNameDisplayNameDescriptionCategoryOrTag(_ query: String) {
        #expect(PluginSearch([Self.entry]).matches(query) == IndexSet(integer: 0))
    }

    @Test(arguments: ["odice", "simplifier-code", "sicurezza", "codice sicurezza"])
    func aWordThatBeginsNoWordFindsNothing(_ query: String) {
        #expect(PluginSearch([Self.entry]).matches(query) == IndexSet())
    }

    @Test(arguments: ["", "   "])
    func anEmptyQueryIsNoSearch(_ query: String) {
        #expect(PluginSearch([Self.entry]).matches(query) == nil)
    }

    @MainActor
    @Test func withAQueryTheResultsOfEverySourceAreGroupedBySource() async throws {
        let home = try PluginHome()
        try home.addMarketplace("zeta", plugins: [["name": "revisore-z", "source": "./a"], ["name": "altro", "source": "./b"]])
        try home.addMarketplace("alfa", plugins: [["name": "revisore-a", "description": "x", "source": "./c"]])
        let catalog = PluginCatalog(folders: home.folders, listing: .never)
        let following = Task { await catalog.follow(project: nil) }
        defer { following.cancel() }
        try await waitForCondition { catalog.snapshot != nil }

        let sections = catalog.entries(in: .installed, matching: "revisore")
        #expect(sections.map(\.marketplace) == ["alfa", "zeta"])
        #expect(sections.map { $0.entries.map(\.id.name) } == [["revisore-a"], ["revisore-z"]])
        #expect(catalog.entries(in: .installed, matching: "").isEmpty)
        #expect(catalog.entries(in: .marketplace("zeta"), matching: "").first?.entries.count == 2)
    }

    @MainActor
    @Test func searchingTwoThousandSixHundredEntriesTakesAtMost100ms() async throws {
        let plugins = (PluginHome.entries(314, in: "ufficiale") + PluginHome.entries(2_282, in: "community")).map { item in
            PluginEntry(id: PluginID(name: item["name"] as! String, marketplace: "m"), summary: item["description"] as! String,
                        category: item["category"] as? String, tags: item["tags"] as! [String])
        }
        let search = PluginSearch(plugins)
        let clock = ContinuousClock()
        var found: IndexSet?
        let elapsed = clock.measure {
            for query in ["c", "codi", "revisione test", "plugin-12", "zzz"] { found = search.matches(query) }
        }
        #expect(found == IndexSet())
        // Five searches, each within the budget.
        #expect(elapsed / 5 <= .milliseconds(100), "Ricerca: \(elapsed / 5)")
    }
}
