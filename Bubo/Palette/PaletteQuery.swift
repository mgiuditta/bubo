import Foundation

/// A kind of result of the Palette, each in its own group.
nonisolated enum PaletteKind: Hashable, Sendable {
    case commands
    case conversations
    case secondBrain
}

/// A filter written in the Palette's box, which becomes a gettone: `@progetto`, `7g`, `cli`, `sessioni`, or a kind
/// of result: `comandi`, `conversazioni`, `cervello` or `note`.
nonisolated enum PaletteFilter: Hashable, Sendable {
    /// Only the conversations of the Progetti whose name contains this text.
    case project(String)
    /// Only the messages of the last this many days.
    case days(Int)
    /// Only the conversations from there.
    case source(ConversationSource)
    /// Only the results of this kind.
    case kind(PaletteKind)

    /// Reads the filter `word` names, or `nil` if it is a word to search.
    init?(_ word: some StringProtocol) {
        let word = word.lowercased()
        if word.hasPrefix("@"), word.count > 1 {
            self = .project(String(word.dropFirst()))
        } else if word.hasSuffix("g"), let days = Int(word.dropLast()), (1...9_999).contains(days) {
            self = .days(days)
        } else if word == "cli" {
            self = .source(.cli)
        } else if word == "sessioni" || word == "sessione" {
            self = .source(.session)
        } else if word == "comandi" || word == "comando" {
            self = .kind(.commands)
        } else if word == "conversazioni" || word == "conversazione" {
            self = .kind(.conversations)
        } else if word == "cervello" || word == "note" || word == "nota" {
            self = .kind(.secondBrain)
        } else {
            return nil
        }
    }

    /// The kind this filter names; `nil` for a filter on the conversations.
    var kind: PaletteKind? {
        if case .kind(let kind) = self { kind } else { nil }
    }

    /// Whether `other` filters on the same thing, so one replaces the other.
    func isSameKind(as other: PaletteFilter) -> Bool {
        switch (self, other) {
        case (.project, .project), (.days, .days), (.source, .source), (.kind, .kind): true
        default: false
        }
    }
}

/// What is written in the Palette's box: the filters already turned into gettoni, and the text still being written.
nonisolated struct PaletteQuery: Equatable, Sendable {
    /// The text in the box.
    var text = ""
    /// The gettoni, in the order they were written; at most one per kind.
    private(set) var filters: [PaletteFilter] = []

    /// Whether nothing is written and no gettone is set.
    var isEmpty: Bool { filters.isEmpty && text.allSatisfy(\.isWhitespace) }

    /// Whether the results of `kind` are shown: a gettone of another kind hides them, and so does a filter on the
    /// conversations for the commands and the Secondo cervello.
    func shows(_ kind: PaletteKind) -> Bool {
        let filters = search.filters
        if let chosen = filters.lazy.compactMap(\.kind).first { return chosen == kind }
        return kind == .conversations || filters.allSatisfy { $0.kind != nil }
    }

    /// The words to search for and every filter, also one still being written at the end of the text.
    var search: (text: String, filters: [PaletteFilter]) {
        var filters = filters
        var words: [Substring] = []
        for word in text.split(whereSeparator: \.isWhitespace) {
            if let filter = PaletteFilter(word) {
                Self.add(filter, to: &filters)
            } else {
                words.append(word)
            }
        }
        return (words.joined(separator: " "), filters)
    }

    /// Turns into gettoni the words of the text that name a filter and are already followed by a space.
    mutating func absorbFilters() {
        let words = text.split(whereSeparator: \.isWhitespace)
        let isLastComplete = text.last?.isWhitespace == true
        var kept: [Substring] = []
        var absorbed = false
        for (position, word) in words.enumerated() {
            let isComplete = isLastComplete || position < words.count - 1
            if isComplete, let filter = PaletteFilter(word) {
                Self.add(filter, to: &filters)
                absorbed = true
            } else {
                kept.append(word)
            }
        }
        guard absorbed else { return }
        text = kept.joined(separator: " ") + (isLastComplete && !kept.isEmpty ? " " : "")
    }

    /// Removes the gettone `filter`.
    mutating func remove(_ filter: PaletteFilter) {
        filters.removeAll { $0 == filter }
    }

    /// Removes the last gettone, as ⌫ does in an empty box.
    mutating func removeLastFilter() {
        _ = filters.popLast()
    }

    private static func add(_ filter: PaletteFilter, to filters: inout [PaletteFilter]) {
        filters.removeAll { $0.isSameKind(as: filter) }
        filters.append(filter)
    }
}
