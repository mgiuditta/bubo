import Foundation

/// The words of every plugin, folded once per snapshot, for a search on ~2,600 entries within 100 ms.
nonisolated struct PluginSearch: Sendable {
    /// The folded words of each plugin, in the order of the snapshot's plugins.
    private let words: [[String]]

    /// Indexes the name, display name, description, category and tags of `plugins`, folded like the Palette.
    init(_ plugins: [PluginEntry]) {
        words = plugins.map { entry in
            let fields = [entry.id.name, entry.displayName, entry.summary, entry.category ?? ""] + entry.tags
            let folded = fields.map(MatchHighlight.fold)
            // Whole names too, so "code-sim" finds "code-simplifier".
            return Array(Set(folded.prefix(2) + folded.flatMap { $0.split { !$0.isLetter && !$0.isNumber }.map(String.init) }))
        }
    }

    /// Indexes `plugins` off the main actor.
    @concurrent static func indexing(_ plugins: [PluginEntry]) async -> PluginSearch {
        PluginSearch(plugins)
    }

    /// The indexes of the plugins where every word of `query` begins a word; `nil` for an empty query.
    func matches(_ query: String) -> IndexSet? {
        let terms = MatchHighlight.fold(query).split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return nil }
        var found = IndexSet()
        for (index, words) in words.enumerated()
        where terms.allSatisfy({ term in words.contains { $0.hasPrefix(term) } }) {
            found.insert(index)
        }
        return found
    }
}
