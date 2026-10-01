import Foundation

/// One row of the Palette: a command, a past conversation or a note of the Secondo cervello.
enum PaletteItem: Identifiable, Equatable {
    case command(PaletteCommand)
    case conversation(ConversationResult)
    case note(NoteResult)

    var id: String {
        switch self {
        case .command(let command): "comando:\(command.id)"
        case .conversation(let result): "conversazione:\(result.id)"
        case .note(let note): "nota:\(note.id)"
        }
    }
}

/// A group of rows of the Palette, under its title.
struct PaletteSection: Identifiable {
    var title: LocalizedStringResource
    var items: [PaletteItem]

    var id: String { items.first?.id ?? title.key }

    /// The Palette's groups for `query`: the commands first when the query names them, then the conversations by age,
    /// then the Secondo cervello; with an empty box, the recent conversations and then the most used commands.
    ///
    /// - Parameters:
    ///   - commands: The commands the query names, or the most used ones with an empty box.
    ///   - conversations: The conversations, already grouped by age.
    ///   - notes: The notes of the Secondo cervello.
    static func sections(for query: PaletteQuery, commands: [PaletteCommand], conversations: [ConversationGroup],
                         notes: [NoteResult]) -> [PaletteSection] {
        let commandSection = PaletteSection(title: query.search.text.isEmpty ? "Comandi più usati" : "Comandi",
                                            items: commands.map(PaletteItem.command))
        let conversationSections = conversations.map { group in
            PaletteSection(title: group.age.title, items: group.results.map(PaletteItem.conversation))
        }
        let noteSection = PaletteSection(title: "Secondo cervello", items: notes.map(PaletteItem.note))
        let ordered: [(PaletteKind, [PaletteSection])] = query.search.text.isEmpty
            ? [(.conversations, conversationSections), (.commands, [commandSection]), (.secondBrain, [noteSection])]
            : [(.commands, [commandSection]), (.conversations, conversationSections), (.secondBrain, [noteSection])]
        return ordered.filter { query.shows($0.0) }.flatMap(\.1).filter { !$0.items.isEmpty }
    }
}
