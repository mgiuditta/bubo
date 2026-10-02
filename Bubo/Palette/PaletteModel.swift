import AppKit
import os

/// What the Palette shows: the query, the commands, conversations and notes that answer it, the chosen one and the
/// preview of a chosen conversation.
@Observable
final class PaletteModel {
    /// What is written in the box.
    var query = PaletteQuery()
    /// The rows that answer the query, in groups.
    private(set) var sections: [PaletteSection] = []
    /// The chosen row, which ↩ opens or runs; ↑↓ move it.
    var selection: PaletteItem.ID?
    /// The best message of the chosen conversation with the one before and the one after it.
    private(set) var preview: [SearchHit] = []
    /// Whether the last search failed in the Indice.
    private(set) var hasFailed = false
    /// Whether the Indice also searched by meaning, or only by words: no embedding model, or its vectors not ready yet.
    private(set) var searchesByMeaning = false

    /// Makes the search over the current Sessioni and Cronologia CLI.
    @ObservationIgnored private let makeSearch: () -> ConversationSearch
    /// The commands of Bubo's menus, read at each search since their titles and states change.
    @ObservationIgnored private let makeCommands: () -> [PaletteCommand]
    @ObservationIgnored private let usage: CommandUsage
    /// Opens a conversation, read only.
    @ObservationIgnored let open: (ConversationResult) -> Void
    /// Closes the Palette: esc.
    @ObservationIgnored var close: () -> Void = {}
    /// Riprendi and Continua da qui on the chosen conversation; `nil` offers neither.
    @ObservationIgnored var actions: ResumeActions?

    init(search: @escaping () -> ConversationSearch,
         commands: @escaping () -> [PaletteCommand] = { CommandCatalog.commands(in: NSApp.mainMenu) },
         usage: CommandUsage = CommandUsage(), open: @escaping (ConversationResult) -> Void) {
        makeSearch = search
        makeCommands = commands
        self.usage = usage
        self.open = open
    }

    /// Every row, in the order shown.
    var results: [PaletteItem] { sections.flatMap(\.items) }

    /// The chosen row.
    var selected: PaletteItem? {
        results.first { $0.id == selection } ?? results.first
    }

    /// The chosen conversation, whose messages the preview shows; `nil` when the chosen row is not a conversation.
    var selectedConversation: ConversationResult? {
        if case .conversation(let result) = selected { result } else { nil }
    }

    /// The words searched, for the highlights.
    var searchedWords: [String] { MatchHighlight.words(of: query.search.text) }

    /// Searches again for the current query; the first result becomes the chosen one.
    func refresh() async {
        let query = query
        let text = query.search.text
        let allCommands = makeCommands()
        let commands = text.isEmpty ? usage.mostUsed(among: allCommands)
            : CommandCatalog.commands(allCommands, matching: text)
        do {
            let search = makeSearch()
            searchesByMeaning = await search.index?.searchesByMeaning ?? false
            let conversations = query.shows(.conversations) ? try await search.groups(for: query) : []
            let notes = query.shows(.secondBrain) ? try await search.notes(for: query) : []
            guard !Task.isCancelled else { return }
            sections = PaletteSection.sections(for: query, commands: commands, conversations: conversations, notes: notes)
            hasFailed = false
        } catch is CancellationError {
            return
        } catch {
            Logger.palette.error("Search failed: \(error)")
            sections = PaletteSection.sections(for: query, commands: commands, conversations: [], notes: [])
            hasFailed = true
        }
        selection = results.first?.id
    }

    /// Reads from the Indice the preview of the chosen conversation; empty for a conversation with nothing searched.
    func loadPreview() async {
        guard let best = selectedConversation?.best, let message = best.message, let index = makeSearch().index else {
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

    /// Opens or runs the chosen row.
    func openSelection() {
        guard let selected else { return }
        activate(selected)
    }

    /// Riprendi on the chosen conversation, after closing the Palette: ⌥↩.
    ///
    /// - Returns: Whether it acted: only on a conversation that can be resumed.
    func resumeSelection() -> Bool {
        guard let result = selectedConversation, let actions, actions.canResume(result) else { return false }
        close()
        actions.resume(result)
        return true
    }

    /// Continua da qui on the chosen conversation, up to the message found, after closing the Palette: ⌘↩.
    ///
    /// - Returns: Whether it acted: only on a conversation with a message found.
    func continueFromSelection() -> Bool {
        guard let result = selectedConversation, let message = result.best?.message?.id, let actions else { return false }
        close()
        actions.continueFrom(result, upTo: message)
        return true
    }

    /// Opens the conversation or the note of `item`, or runs its command, after closing the Palette.
    func activate(_ item: PaletteItem) {
        switch item {
        case .conversation(let result):
            open(result)
        case .command(let command):
            close()
            usage.record(command)
            Logger.palette.info("Command run from the Palette")
            // On the next turn, once the window behind has taken the keyboard back.
            Task { command.perform() }
        case .note(let note):
            close()
            NSWorkspace.shared.open(URL(filePath: note.best.path))
        }
    }
}

extension Logger {
    nonisolated static let palette = Logger(subsystem: "com.mgiuditta.bubo", category: "palette")
}
