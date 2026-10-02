import Foundation
import Testing
@testable import Bubo

/// A temporary home with a `~/.claude` of plugins and a Progetto, never the real one.
final class PluginHome {
    let home: URL
    let project: URL
    let folders: PluginFolders

    init() throws {
        home = URL.temporaryDirectory.appending(path: "plugin-home-\(UUID().uuidString)", directoryHint: .isDirectory)
        project = home.appending(path: "progetto", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        folders = PluginFolders.current(home: home, environment: [:])
    }

    deinit {
        try? FileManager.default.removeItem(at: home)
    }

    /// Writes `json` at `path`, relative to the home unless absolute.
    func write(_ json: Any, at path: String) throws {
        try write(JSONSerialization.data(withJSONObject: json), at: path)
    }

    /// Writes `data` at `path`, relative to the home unless absolute.
    func write(_ data: Data, at path: String) throws {
        let file = path.hasPrefix("/") ? URL(filePath: path) : home.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
    }

    /// Registers the Marketplace `name`, cloned in `marketplaces/name`, with `plugins` in its `marketplace.json`.
    func addMarketplace(_ name: String, plugins: [[String: Any]]) throws {
        let clone = folders.marketplaces.appending(path: name, directoryHint: .isDirectory)
        var known = (try? JSONSerialization.jsonObject(with: Data(contentsOf: folders.knownMarketplaces))) as? [String: Any] ?? [:]
        known[name] = ["source": ["source": "github", "repo": "esempio/\(name)"], "installLocation": clone.path]
        try write(known, at: folders.knownMarketplaces.path)
        try write(["name": name, "owner": ["name": "Esempio"], "plugins": plugins],
                  at: clone.appending(path: ".claude-plugin/marketplace.json").path)
    }

    /// Writes `installed_plugins.json` with `plugins`, each a list of installations.
    func install(_ plugins: [String: [[String: Any]]]) throws {
        try write(["version": 2, "plugins": plugins], at: folders.installedPlugins.path)
    }

    /// An installation for `installed_plugins.json`.
    func installation(scope: String = "user", project: URL? = nil, path: URL? = nil) -> [String: Any] {
        var installation: [String: Any] = ["scope": scope, "installPath": (path ?? home.appending(path: "nessuna")).path,
                                           "version": "1.0.0"]
        if let project { installation["projectPath"] = project.path }
        return installation
    }

    /// Writes `enabledPlugins` in the user's settings.
    func enableForUser(_ plugins: [String: Bool]) throws {
        try write(["enabledPlugins": plugins], at: folders.userSettings.path)
    }

    /// Writes `enabledPlugins` in the Progetto's shared settings.
    func enableForProject(_ plugins: [String: Bool]) throws {
        try write(["enabledPlugins": plugins], at: folders.projectSettings(of: project).shared.path)
    }

    /// `count` Marketplace entries of `marketplace`, with descriptions, categories and tags.
    static func entries(_ count: Int, in marketplace: String) -> [[String: Any]] {
        (0..<count).map { index in
            ["name": "\(marketplace)-plugin-\(index)",
             "description": "Plugin numero \(index) di \(marketplace): aiuta con il codice, i test, la revisione e la documentazione del Progetto.",
             "category": ["development", "security", "productivity"][index % 3],
             "tags": ["tag\(index % 50)", "comune"],
             "source": ["source": "url", "url": "https://example.com/\(marketplace)/\(index).git", "sha": String(repeating: "a", count: 40)]]
        }
    }
}

/// A `claude plugin list` that never answers, as with no network or no `claude`.
extension PluginListing {
    static let never = PluginListing {
        try await Task.sleep(for: .seconds(3_600))
        throw CancellationError()
    }

    /// A `claude plugin list` that answers `list` at once.
    static func answering(_ list: PluginList) -> PluginListing {
        PluginListing { list }
    }
}

/// Waits until `condition` holds, for at most `timeout`.
@MainActor
func waitForCondition(timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Condizione non raggiunta entro \(timeout)")
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}
