import Foundation

/// What `claude plugin list --json --available` prints: the installations and what the Marketplaces offer.
nonisolated struct PluginList: Sendable, Equatable {
    /// One installation, as the CLI sees it after merging the settings.
    struct Installed: Sendable, Equatable {
        let id: PluginID
        let scope: String
        let isEnabled: Bool
        let version: String?
        let installPath: URL?
        let projectPath: URL?
        /// The load errors, when the plugin failed to load.
        let errors: [String]
    }

    /// One plugin a Marketplace offers and nobody installed.
    struct Available: Sendable, Equatable {
        let id: PluginID
        let summary: String?
        let version: String?
        let installCount: Int?
        let source: PluginSource
    }

    var installed: [Installed]
    var available: [Available]

    /// Creates a list of `installed` and `available` plugins.
    init(installed: [Installed] = [], available: [Available] = []) {
        self.installed = installed
        self.available = available
    }

    /// Reads the CLI's standard output: the object of `--available`, or the array of the installations alone.
    /// `nil` when it is neither.
    init?(output: String) {
        let text = output.drop { $0 != "{" && $0 != "[" }
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { return nil }
        let installed: [Any]
        let available: [Any]
        if let list = json as? [Any] {
            (installed, available) = (list, [])
        } else if let object = json as? [String: Any] {
            (installed, available) = (object["installed"] as? [Any] ?? [], object["available"] as? [Any] ?? [])
        } else {
            return nil
        }
        self.installed = installed.compactMap { item in
            guard let item = item as? [String: Any], let id = (item["id"] as? String).flatMap(PluginID.init) else { return nil }
            return Installed(id: id, scope: item["scope"] as? String ?? "user", isEnabled: item["enabled"] as? Bool ?? false,
                             version: item["version"] as? String,
                             installPath: (item["installPath"] as? String).map { URL(filePath: $0, directoryHint: .isDirectory) },
                             projectPath: (item["projectPath"] as? String).map { URL(filePath: $0, directoryHint: .isDirectory) },
                             errors: item["errors"] as? [String] ?? [])
        }
        self.available = available.compactMap { item in
            guard let item = item as? [String: Any], let id = (item["pluginId"] as? String).flatMap(PluginID.init)
            else { return nil }
            return Available(id: id, summary: item["description"] as? String, version: item["version"] as? String,
                             installCount: item["installCount"] as? Int, source: PluginSource(json: item["source"]))
        }
    }
}
