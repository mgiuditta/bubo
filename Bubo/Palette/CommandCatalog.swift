import AppKit

/// A command of the Palette: an item of Bubo's menus, with its shortcut.
struct PaletteCommand: Identifiable, Equatable {
    /// The item's title, as the menu shows it.
    let title: String
    /// The item's shortcut, such as `⌥⌘G`; `nil` without one.
    let shortcut: String?
    /// The menu item that runs the command.
    let item: NSMenuItem

    var id: String { title }

    /// Runs the command as if its menu item were chosen.
    func perform() {
        guard let menu = item.menu else { return }
        let index = menu.index(of: item)
        guard index >= 0 else { return }
        menu.performActionForItem(at: index)
    }

    static func == (lhs: PaletteCommand, rhs: PaletteCommand) -> Bool {
        lhs.title == rhs.title && lhs.shortcut == rhs.shortcut && lhs.item === rhs.item
    }
}

/// The Palette's commands, taken from Bubo's menus: every command with a menu item enters the Palette on its own.
enum CommandCatalog {
    /// The commands of `menu` and of its submenus, in menu order, one per title.
    ///
    /// Left out: separators, section titles, hidden, disabled and alternate items, the open windows listed in the
    /// Finestra menu, the Servizi menu, the Modifica menu, whose items act on the text in front, which is the Palette's
    /// own box, and the Palette's own item.
    static func commands(in menu: NSMenu?) -> [PaletteCommand] {
        guard let menu else { return [] }
        var seen: Set<String> = []
        return items(in: menu).compactMap { item in
            guard seen.insert(item.title).inserted else { return nil }
            return PaletteCommand(title: item.title, shortcut: shortcut(of: item), item: item)
        }
    }

    /// The commands whose title has a word starting with each word of `text`, regardless of case and accents.
    static func commands(_ commands: [PaletteCommand], matching text: String) -> [PaletteCommand] {
        let searched = MatchHighlight.words(of: text).map(MatchHighlight.fold)
        guard !searched.isEmpty else { return [] }
        return commands.filter { command in
            let words = MatchHighlight.words(of: command.title).map(MatchHighlight.fold)
            return searched.allSatisfy { word in words.contains { $0.hasPrefix(word) } }
        }
    }

    /// The item's shortcut written like a ``KeyShortcut``, such as `⇧⌘K`, or `nil` without one.
    static func shortcut(of item: NSMenuItem) -> String? {
        guard !item.keyEquivalent.isEmpty else { return nil }
        var flags = item.keyEquivalentModifierMask.intersection([.command, .option, .control, .shift])
        // An uppercase key equivalent implies ⇧.
        if item.keyEquivalent != item.keyEquivalent.lowercased() { flags.insert(.shift) }
        let label = switch item.keyEquivalent {
        case " ": "Spazio"
        case "\r": "↩"
        case "\t": "⇥"
        case "\u{1b}": "⎋"
        default: item.keyEquivalent.uppercased()
        }
        return KeyShortcut(keyCode: 0, carbonModifiers: KeyShortcut.carbonModifiers(from: flags), keyLabel: label).displayName
    }

    /// The items of `menu` and of its submenus that run a command, depth first.
    private static func items(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item -> [NSMenuItem] in
            guard !item.isHidden, !item.isSeparatorItem, !item.isSectionHeader else { return [] }
            if let submenu = item.submenu {
                let isEditMenu = submenu.items.contains { $0.action == #selector(NSText.copy(_:)) }
                return submenu === NSApp.servicesMenu || isEditMenu ? [] : items(in: submenu)
            }
            return isCommand(item) ? [item] : []
        }
    }

    private static func isCommand(_ item: NSMenuItem) -> Bool {
        item.action != nil && item.isEnabled && !item.isAlternate && item.view == nil && !item.title.isEmpty
            // The open windows, which the Finestra menu lists by name.
            && !(item.target is NSWindow)
            && item.title != String(localized: "Cerca…")
    }
}
