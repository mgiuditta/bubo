import Foundation
import os

/// What the Palette shows: the query, the conversations that answer it, the chosen one and its preview.
@Observable
final class PaletteModel {
    /// What is written in the box.
    var query = PaletteQuery()
    /// The conversations that answer the query, by age.
    private(set) var groups: [ConversationGroup] = []
    /// The chosen conversation, which ↩ opens; ↑↓ move it.
    var selection: ConversationResult.ID?
    /// The best message of the chosen conversation with the one before and the one after it.
    private(set) var preview: [SearchHit] = []
    /// Whether the last search failed in the Indice.
    private(set) var hasFailed = false

    /// Makes the search over the current Sessioni and Cronologia CLI.
    @ObservationIgnored private let makeSearch: () -> ConversationSearch
    /// Opens a conversation, read only.
    @ObservationIgnored let open: (ConversationResult) -> Void
    /// Closes the Palette: esc.
    @ObservationIgnored var close: () -> Void = {}

    init(search: @escaping () -> ConversationSearch, open: @escaping (ConversationResult) -> Void) {
        makeSearch = search
        self.open = open
    }

    /// Every result, in the order shown.
    var results: [ConversationResult] { groups.flatMap(\.results) }

    /// The chosen conversation.
    var selected: ConversationResult? {
        results.first { $0.id == selection } ?? results.first
    }

    /// The words searched, for the highlights.
    var searchedWords: [String] { MatchHighlight.words(of: query.search.text) }

    /// Searches again for the current query; the first result becomes the chosen one.
    func refresh() async {
        do {
            let found = try await makeSearch().groups(for: query)
            guard !Task.isCancelled else { return }
            groups = found
            hasFailed = false
        } catch is CancellationError {
            return
        } catch {
            Logger.palette.error("Search failed: \(error)")
            groups = []
            hasFailed = true
        }
        selection = results.first?.id
    }

    /// Reads from the Indice the preview of the chosen conversation; empty for a conversation with nothing searched.
    func loadPreview() async {
        guard let best = selected?.best, let message = best.message, let index = makeSearch().index else {
            preview = []
            return
        }
        do {
            let messages = try await index.messages(around: message.id, inConversation: best.path)
            guard !Task.isCancelled else { return }
            preview = messages
        } catch {
            Logger.palette.error("Preview not read: \(error)")
            preview = [best]
        }
    }

    /// Moves the choice `offset` rows down, or up when negative, staying within the results.
    func moveSelection(by offset: Int) {
        let results = results
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selection } ?? 0
        selection = results[min(max(current + offset, 0), results.count - 1)].id
    }

    /// Opens the chosen conversation.
    func openSelection() {
        guard let selected else { return }
        open(selected)
    }
}

extension Logger {
    nonisolated static let palette = Logger(subsystem: "com.mgiuditta.bubo", category: "palette")
}
