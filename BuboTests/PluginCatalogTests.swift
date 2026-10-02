import Foundation
import Synchronization
import Testing
@testable import Bubo

/// The Plugin window's state: first draw from the files, `claude` in background, FSEvents, and never a write.
@MainActor
struct PluginCatalogTests {
    @Test func theFirstSnapshotComesFromTheFilesWithoutClaude() async throws {
        let home = try PluginHome()
        try home.addMarketplace("ufficiale", plugins: [["name": "revisore", "source": "./plugins/revisore"]])
        try home.install(["revisore@ufficiale": [home.installation()]])
        let catalog = PluginCatalog(folders: home.folders, listing: .never)
        let following = Task { await catalog.follow(project: home.project) }
        defer { following.cancel() }
        try await waitForCondition { catalog.snapshot != nil }

        #expect(catalog.snapshot?.marketplaces.map(\.name) == ["ufficiale"])
        #expect(catalog.entries(in: .installed, matching: "").first?.entries.map(\.id.name) == ["revisore"])
        #expect(!catalog.isListingUnavailable)
    }

    @Test func readingTwoMarketplacesOfTwoThousandSixHundredEntriesTakesLessThan300ms() async throws {
        let home = try PluginHome()
        try home.addMarketplace("claude-plugins-official", plugins: PluginHome.entries(314, in: "ufficiale"))
        try home.addMarketplace("claude-community", plugins: PluginHome.entries(2_282, in: "community"))
        let catalog = PluginCatalog(folders: home.folders, listing: .never)
        let clock = ContinuousClock()
        let start = clock.now
        let following = Task { await catalog.follow(project: home.project) }
        defer { following.cancel() }
        while catalog.snapshot == nil { await Task.yield() }
        let sections = catalog.entries(in: .marketplace("claude-community"), matching: "")
        let elapsed = clock.now - start
        #expect(sections.first?.entries.count == 2_282)
        #expect(elapsed < .milliseconds(300), "Primo disegno: \(elapsed)")
    }

    @Test func theListOfClaudeArrivesAfterAndAFailureLeavesTheFiles() async throws {
        let home = try PluginHome()
        try home.addMarketplace("ufficiale", plugins: [["name": "revisore", "source": "./plugins/revisore"]])
        let list = PluginList(available: [.init(id: PluginID(name: "revisore", marketplace: "ufficiale"), summary: nil,
                                                version: nil, installCount: 7, source: .relative(path: "./plugins/revisore"))])
        let catalog = PluginCatalog(folders: home.folders, listing: .answering(list))
        let following = Task { await catalog.follow(project: nil) }
        try await waitForCondition { catalog.snapshot?.plugins.first?.installCount == 7 }
        following.cancel()

        let failing = PluginCatalog(folders: home.folders, listing: PluginListing { throw PluginListingError.claudeMissing })
        let failingTask = Task { await failing.follow(project: nil) }
        defer { failingTask.cancel() }
        try await waitForCondition { failing.isListingUnavailable }
        #expect(failing.snapshot?.plugins.map(\.id.name) == ["revisore"])
    }

    @Test func theWindowOpensOnDaSistemareOnlyWhenItHasSomething() async throws {
        let home = try PluginHome()
        try home.addMarketplace("ufficiale", plugins: [["name": "formattatore", "source": "./f"]])
        let catalog = PluginCatalog(folders: home.folders, listing: .never)
        let following = Task { await catalog.follow(project: home.project) }
        try await waitForCondition { catalog.snapshot != nil }
        #expect(PluginSidebarItem.initialSelection(in: try #require(catalog.snapshot)) == .installed)
        following.cancel()

        try home.enableForProject(["formattatore@ufficiale": true])
        let again = PluginCatalog(folders: home.folders, listing: .never)
        let followingAgain = Task { await again.follow(project: home.project) }
        defer { followingAgain.cancel() }
        try await waitForCondition { again.snapshot != nil }
        let snapshot = try #require(again.snapshot)
        #expect(PluginSidebarItem.initialSelection(in: snapshot) == .toFix)
        #expect(again.entries(in: .toFix, matching: "").first?.entries.map(\.id.name) == ["formattatore"])
    }

    @Test func followingTheCatalogWritesNothing() async throws {
        let home = try PluginHome()
        try home.addMarketplace("ufficiale", plugins: [["name": "revisore", "source": "./plugins/revisore"]])
        try home.enableForProject(["revisore@ufficiale": true])
        try home.enableForUser(["revisore@ufficiale": true])
        let cache = home.folders.officialCatalogCache.path
        try home.write(["version": 1, "catalog": ["plugins": [:]]], at: cache)
        let catalog = PluginCatalog(folders: home.folders, listing: .answering(PluginList()))
        let following = Task { await catalog.follow(project: home.project) }
        defer { following.cancel() }
        try await waitForCondition { catalog.snapshot != nil && catalog.officialCache != nil }
        // Time for FSEvents to start, then a change from outside, as the terminal would make.
        try await Task.sleep(for: .seconds(1))
        try home.install(["revisore@ufficiale": [home.installation()]])
        let before = try Self.tree(under: [home.home.appending(path: ".claude"), home.project.appending(path: ".claude")])
        try await waitForCondition { catalog.snapshot?.plugins.first?.isInstalled == true }
        #expect(catalog.snapshot?.problems.isEmpty == true)
        try await Task.sleep(for: .milliseconds(200))
        #expect(try Self.tree(under: [home.home.appending(path: ".claude"), home.project.appending(path: ".claude")]) == before)
    }

    @Test func theOnlyCommandIsTheReadOnlyList() async throws {
        let home = try PluginHome()
        let claude = home.home.appending(path: ".local/bin/claude")
        let calls = Calls()
        let runner = ProcessRunner { executable, arguments in
            #expect(executable == claude)
            calls.arguments.withLock { $0.append(arguments) }
            return ProcessOutput(exitCode: 0, standardOutput: #"{"installed": [], "available": []}"#)
        }
        let listing = PluginListing.live(locator: ClaudeLocator(home: home.home, isExecutable: { $0 == claude }), runner: runner)
        #expect(try await listing.list() == PluginList())
        #expect(calls.arguments.withLock { $0 } == [["plugin", "list", "--json", "--available"]])

        let failing = PluginListing.live(locator: ClaudeLocator(home: home.home, isExecutable: { $0 == claude }),
                                         runner: ProcessRunner { _, _ in ProcessOutput(exitCode: 1, standardOutput: "") })
        await #expect(throws: PluginListingError.failed(exitCode: 1)) { try await failing.list() }
    }

    @Test func gitNeverAsksForAPassword() {
        let environment = PluginListing.environment(base: ["HOME": "/Users/x", "ANTHROPIC_API_KEY": "segreta",
                                                           "CLAUDE_CODE_PLUGIN_CACHE_DIR": "/c"])
        #expect(environment["GIT_TERMINAL_PROMPT"] == "0")
        #expect(environment["GIT_ASKPASS"] == "")
        #expect(environment["ANTHROPIC_API_KEY"] == nil)
        #expect(environment["CLAUDE_CODE_PLUGIN_CACHE_DIR"] == "/c")
    }

    /// The arguments of every command run.
    private final class Calls: Sendable {
        let arguments = Mutex<[[String]]>([])
    }

    /// Path, size and modification date of every file and folder under `roots`.
    private static func tree(under roots: [URL]) throws -> [String: String] {
        var tree: [String: String] = [:]
        for root in roots {
            let paths = FileManager.default.enumerator(atPath: root.path)?.compactMap { $0 as? String } ?? []
            for path in [""] + paths {
                let attributes = try FileManager.default.attributesOfItem(atPath: root.appending(path: path).path)
                tree[root.path + "/" + path] = "\(attributes[.size] ?? 0) \(attributes[.modificationDate] ?? 0)"
            }
        }
        return tree
    }
}
