import Foundation

/// The `userConfig` of an installed plugin, as `claude plugin configure --json` shows it (spec 20, Impostazioni).
nonisolated struct PluginOptions: Sendable, Equatable {
    /// One option of the plugin.
    struct Option: Sendable, Equatable, Identifiable {
        /// What the form shows for the option.
        enum Kind: String, Sendable {
            case string, number, boolean, directory, file
        }

        /// The key the values are saved under.
        let id: String
        let kind: Kind
        let title: String
        let summary: String
        let isRequired: Bool
        /// Whether the value is a secret, kept in the Keychain by `claude`: never shown, never in an argument.
        let isSensitive: Bool
        /// The values to choose from, for a selector; empty for a free value.
        let choices: [String]
    }

    /// The options, in the order the manifest declares them.
    let options: [Option]
    /// The values saved, or the defaults, as strings; never a secret.
    let values: [String: String]
    /// The keys with a value saved.
    let configured: Set<String>

    /// Creates the options of a plugin.
    init(options: [Option], values: [String: String] = [:], configured: Set<String> = []) {
        self.options = options
        self.values = values
        self.configured = configured
    }

    /// Reads the output of `configure --json`; `nil` when it has no `schema`.
    ///
    /// The JSON object loses the order of the keys, so the options follow the order their keys first appear in the
    /// text, the manifest's.
    init?(json text: String) {
        guard let start = text.firstIndex(of: "{"),
              let object = try? JSONSerialization.jsonObject(with: Data(text[start...].utf8)) as? [String: Any],
              let schema = object["schema"] as? [String: Any]
        else { return nil }
        let inputs = object["inputs"] as? [String: String] ?? [:]
        let choices = object["choices"] as? [String: [String]] ?? [:]
        let schemaText = text.range(of: #""schema""#).map { text[$0.upperBound...] } ?? text[...]
        let position = { (key: String) in
            schemaText.range(of: "\"\(key)\"").map { schemaText.distance(from: schemaText.startIndex, to: $0.lowerBound) } ?? .max
        }
        let options = schema.compactMap { key, value -> Option? in
            guard let field = value as? [String: Any] else { return nil }
            let kind = Option.Kind(rawValue: field["type"] as? String ?? "") ?? .string
            let isSensitive = field["sensitive"] as? Bool ?? false
            return Option(id: key, kind: kind, title: field["title"] as? String ?? key,
                          summary: field["description"] as? String ?? "",
                          isRequired: field["required"] as? Bool ?? false, isSensitive: isSensitive,
                          // A boolean is a switch, not a selector of "true" and "false".
                          choices: kind == .boolean ? [] : choices[key] ?? field["options"] as? [String] ?? [])
        }
        self.init(options: options.sorted { (position($0.id), $0.id) < (position($1.id), $1.id) },
                  values: inputs.filter { key, _ in options.first { $0.id == key }?.isSensitive == false },
                  configured: Set(object["configured"] as? [String] ?? []))
    }

    /// The required options with no value saved: what puts the plugin in need of its Impostazioni.
    var missingRequired: [Option] {
        options.filter { $0.isRequired && !configured.contains($0.id) }
    }

    /// What to save of `edited`: the values that changed, as single-line strings, and a secret only when typed,
    /// since an empty secret field keeps the one saved.
    func changes(in edited: [String: String]) -> PluginOptionValues {
        var changed: [String: String] = [:]
        for option in options {
            let value = (edited[option.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if option.isSensitive {
                if !value.isEmpty { changed[option.id] = value }
            } else if value != (values[option.id] ?? "") && !(value.isEmpty && values[option.id] == nil) {
                changed[option.id] = value
            }
        }
        return PluginOptionValues(changed)
    }

    /// Whether the manifest of the plugin installed at `folder` declares a `userConfig`: only then it has Impostazioni.
    @concurrent static func areDeclared(at folder: URL?) async -> Bool {
        guard let folder,
              let data = try? Data(contentsOf: folder.appending(path: ".claude-plugin/plugin.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let options = manifest["userConfig"] as? [String: Any]
        else { return false }
        return !options.isEmpty
    }
}
