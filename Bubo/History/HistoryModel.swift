import Foundation
import os

/// What the Cronologia window shows: the search, its filters with their counts, the results and the conversation read.
@Observable
final class HistoryModel {
    /// What is written in the search box.
    var text = ""
    /// The filters of the left column.
    var filters = HistoryFilters()
    /// Every conversation that answers `text`, by age, before the filters.
    private(set) var groups: [ConversationGroup] = []
    /// Whether the last search failed in the Indice.
    private(set) var hasFailed = false
    /// The conversation read on the right, also when the search no longer lists it.
    private(set) var reader: ConversationReader?
    /// Riprendi and Continua da qui on the conversation read; `nil` offers neither.
    @ObservationIgnored let actions: ResumeActions?

    /// Makes the search over the current Sessioni and Cronologia CLI.
    @ObservationIgnored private let makeSearch: () -> ConversationSearch
    /// Reads every message of a conversation, from `~/.claude` or from Bubo's copy.
    @ObservationIgnored private let readMessages: (String) async throws -> [CLIConversation.Message]

    init(search: @escaping () -> ConversationSearch,
         read: @escaping (String) async throws -> [CLIConversation.Message], actions: ResumeActions? = nil) {
        makeSearch = search
        readMessages = read
        self.actions = actions
    }

    /// Every result before the filters, in the order shown.
    var allResults: [ConversationResult] { groups.flatMap(\.results) }

    /// The results that pass the filters, by age, without the empty groups.
    func visibleGroups(at now: Date = .now) -> [ConversationGroup] {
        groups.compactMap { group in
            let results = group.results.filter { filters.admits($0, at: now) }
            return results.isEmpty ? nil : ConversationGroup(age: group.age, results: results)
        }
    }

    /// The Progetti of the results, by name, for the filter column.
    var projectNames: [String] {
        Set(allResults.compactMap(HistoryFilters.projectName(of:))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// How many results the filters would leave after `change`: the count next to each choice.
    func count(changing change: (inout HistoryFilters) -> Void, at now: Date = .now) -> Int {
        filters.changing(change).count(in: allResults, at: now)
    }

    /// Opens `result`, found by searching `text`: every filter off, its conversation read on the right.
    func open(_ result: ConversationResult, searching text: String) {
        self.text = text
        filters = HistoryFilters()
        read(result)
    }

    /// Reads `result` on the right, with the words searched now highlighted.
    func read(_ result: ConversationResult) {
        guard reader?.result.id != result.id || reader?.result.best != result.best else { return }
        let search = makeSearch()
        let session = search.sessions.first { $0.id.uuidString == result.id }
        reader = ConversationReader(result: result, words: MatchHighlight.words(of: text),
                                    resumeID: result.source == .session ? session?.conversations.last ?? result.conversation : nil,
                                    read: readMessages) { conversation in
            guard let index = search.index else { return [] }
            return try await index.messages(ofConversation: conversation).map { hit in
                CLIConversation.Message(id: hit.message?.id, isFromUser: hit.message?.isFromUser ?? false, text: hit.text,
                                        date: hit.message?.date)
            }
        }
    }

    /// Searches again for `text`.
    func refresh() async {
        let search = makeSearch()
        let words = text.trimmingCharacters(in: .whitespaces)
        do {
            // Not a PaletteQuery: here the filters are the column, so `cli` or `7g` are words to search.
            let found: [ConversationGroup]
            if words.isEmpty {
                found = search.recentGroups(filters: [], at: .now)
            } else {
                let hits = try await search.index?.hits(for: words, source: .conversations,
                                                       limit: ConversationSearch.fragmentLimit) ?? []
                found = search.groups(of: hits, filters: [], at: .now)
            }
            guard !Task.isCancelled else { return }
            groups = found
            hasFailed = false
        } catch is CancellationError {
            return
        } catch {
            Logger.history.error("Search failed: \(error)")
            groups = []
            hasFailed = true
        }
    }

    /// Reads the result `offset` rows below the one read, or above when negative, among the visible ones.
    func moveSelection(by offset: Int) {
        let results = visibleGroups().flatMap(\.results)
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == reader?.result.id } ?? (offset > 0 ? -1 : results.count)
        read(results[min(max(current + offset, 0), results.count - 1)])
    }
}
