import AppKit
import Foundation
import Testing
@testable import Bubo

/// The Palette's commands, taken from menus made up here, the most used ones, and the order of its groups.
@MainActor
struct CommandCatalogTests {
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "CommandCatalogTests-\(UUID().uuidString)"))
    }

    /// A menu like Bubo's: File with a submenu, a separator, a hidden, a disabled and an alternate item; Modifica.
    private static func makeMenu() -> NSMenu {
        let main = NSMenu()
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Nuova Sessione…", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "n")
        let draft = file.addItem(withTitle: "Nuova Bozza…", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "n")
        draft.keyEquivalentModifierMask = [.option, .command]
        file.addItem(.separator())
        file.addItem(withTitle: "Mostra la Galassia", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Nascosto", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "").isHidden = true
        let disabled = file.addItem(withTitle: "Spento", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "")
        disabled.isEnabled = false
        file.autoenablesItems = false
        file.addItem(withTitle: "Senza azione", action: nil, keyEquivalent: "")
        main.addItem(withTitle: "File", action: nil, keyEquivalent: "").submenu = file
        let edit = NSMenu(title: "Modifica")
        edit.addItem(withTitle: "Copia", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        main.addItem(withTitle: "Modifica", action: nil, keyEquivalent: "").submenu = edit
        return main
    }

    @Test func theCommandsComeFromTheMenusWithTheirShortcuts() {
        let commands = CommandCatalog.commands(in: Self.makeMenu())
        #expect(commands.map(\.title) == ["Nuova Sessione…", "Nuova Bozza…", "Mostra la Galassia"])
        #expect(commands.map(\.shortcut) == ["⌘N", "⌥⌘N", nil])
    }

    @Test func aCommandIsFoundByTheStartOfItsWords() {
        let commands = CommandCatalog.commands(in: Self.makeMenu())
        #expect(CommandCatalog.commands(commands, matching: "galas").map(\.title) == ["Mostra la Galassia"])
        #expect(CommandCatalog.commands(commands, matching: "NUOVA boz").map(\.title) == ["Nuova Bozza…"])
        #expect(CommandCatalog.commands(commands, matching: "nuova login").isEmpty)
        #expect(CommandCatalog.commands(commands, matching: "").isEmpty)
    }

    @Test func runningACommandChoosesItsMenuItem() throws {
        let menu = NSMenu()
        let target = MenuTarget()
        let item = menu.addItem(withTitle: "Prova", action: #selector(MenuTarget.choose(_:)), keyEquivalent: "")
        item.target = target
        let command = try #require(CommandCatalog.commands(in: menu).first)
        command.perform()
        #expect(target.chosen == 1)
    }

    @Test func theMostUsedCommandsComeFirst() {
        let usage = CommandUsage(defaults: defaults)
        let commands = CommandCatalog.commands(in: Self.makeMenu())
        #expect(usage.mostUsed(among: commands).isEmpty)
        usage.record(commands[2])
        usage.record(commands[2])
        usage.record(commands[0])
        #expect(usage.mostUsed(among: commands).map(\.title) == ["Mostra la Galassia", "Nuova Sessione…"])
        #expect(usage.mostUsed(among: commands, limit: 1).map(\.title) == ["Mostra la Galassia"])
    }

    @Test func theCommandsComeFirstWhenTheQueryNamesThem() throws {
        let command = try #require(CommandCatalog.commands(in: Self.makeMenu()).first)
        let conversation = ConversationResult(id: "c", title: "Galassia", source: .cli, conversation: "c", date: .now)
        let note = NoteResult(best: SearchHit(path: "/note/galassia.md", source: .secondBrain, text: "Galassia"))
        let groups = [ConversationGroup(age: .lastWeek, results: [conversation])]

        var query = PaletteQuery()
        query.text = "galassia"
        let named = PaletteSection.sections(for: query, commands: [command], conversations: groups, notes: [note])
        #expect(named.map(\.items) == [[.command(command)], [.conversation(conversation)], [.note(note)]])

        let empty = PaletteSection.sections(for: PaletteQuery(), commands: [command], conversations: groups, notes: [])
        #expect(empty.map(\.items) == [[.conversation(conversation)], [.command(command)]])
    }

    @Test func aGettoneOfKindKeepsOnlyItsGroup() throws {
        let command = try #require(CommandCatalog.commands(in: Self.makeMenu()).first)
        let conversation = ConversationResult(id: "c", title: "Galassia", source: .cli, conversation: "c", date: .now)
        let note = NoteResult(best: SearchHit(path: "/note/galassia.md", source: .secondBrain, text: "Galassia"))
        let groups = [ConversationGroup(age: .lastWeek, results: [conversation])]
        func sections(_ text: String) -> [[PaletteItem]] {
            var query = PaletteQuery()
            query.text = text
            query.absorbFilters()
            return PaletteSection.sections(for: query, commands: [command], conversations: groups, notes: [note])
                .map(\.items)
        }
        #expect(sections("comandi galassia") == [[.command(command)]])
        #expect(sections("cervello galassia") == [[.note(note)]])
        #expect(sections("conversazioni galassia") == [[.conversation(conversation)]])
        // A filter on the conversations keeps only them.
        #expect(sections("cli galassia") == [[.conversation(conversation)]])
    }

    @Test func aNoteIsOneRowWithItsOtherSections() {
        let hits = [SearchHit(path: "/a.md", source: .secondBrain, text: "uno"),
                    SearchHit(path: "/b.md", source: .secondBrain, text: "due"),
                    SearchHit(path: "/a.md", source: .secondBrain, text: "tre")]
        let notes = ConversationSearch.notes(of: hits)
        #expect(notes.map(\.title) == ["a", "b"])
        #expect(notes.map(\.otherMatches) == [1, 0])
        #expect(notes.first?.best.text == "uno")
    }
}

/// Counts how many times its menu item was chosen.
private final class MenuTarget: NSObject {
    var chosen = 0

    @objc func choose(_ sender: Any?) {
        chosen += 1
    }
}
