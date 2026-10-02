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
        let errors: [LoadError]
    }

    /// A load error: `errorDetails` with its type, or a line of `errors` from a CLI without them.
    struct LoadError: Sendable, Equatable {
        /// Such as `dependency-unsatisfied`; `nil` when the CLI gives only the text.
        let type: String?
        let message: String
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
                             errors: Self.loadErrors(of: item))
        }
        self.available = available.compactMap { item in
            guard let item = item as? [String: Any], let id = (item["pluginId"] as? String).flatMap(PluginID.init)
            else { return nil }
            return Available(id: id, summary: item["description"] as? String, version: item["version"] as? String,
                             installCount: item["installCount"] as? Int, source: PluginSource(json: item["source"]))
        }
    }

    /// The errors of an installation: `errorDetails` paired with the lines of `errors`, which say the same in words.
    private static func loadErrors(of item: [String: Any]) -> [LoadError] {
        let lines = item["errors"] as? [String] ?? []
        guard let details = item["errorDetails"] as? [Any], !details.isEmpty else {
            return lines.map { LoadError(type: nil, message: $0) }
        }
        // The CLI builds both from the same errors, one to one.
        let typed = details.enumerated().compactMap { index, detail in
            let detail = detail as? [String: Any] ?? [:]
            let message = index < lines.count ? lines[index] : detail["message"] as? String
            return message.map { LoadError(type: detail["type"] as? String, message: $0) }
        }
        return typed + lines.dropFirst(details.count).map { LoadError(type: nil, message: $0) }
    }
}
