import Foundation

/// The values of a plugin's `userConfig` to save, by key, each a single-line string as
/// `claude plugin configure --values-stdin` takes them, numbers and booleans included (spec 20).
///
/// Some are secrets: they reach `claude` only on its standard input, never in its arguments, and the description
/// says only how many there are, so no log or interpolation can show them.
nonisolated struct PluginOptionValues: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    /// The values, by key.
    let values: [String: String]

    /// Creates the values to save.
    init(_ values: [String: String]) {
        self.values = values
    }

    /// The JSON object for standard input.
    var json: Data {
        // Never fails on a dictionary of strings.
        (try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    var description: String { "\(values.count) values" }
    var debugDescription: String { description }
}
