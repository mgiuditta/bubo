import AppKit
import Testing
@testable import Bubo

/// The app menu has the standard items, and no two shortcuts collide.
// ponytail: "Controlla aggiornamenti…" e il CommandCatalog della Palette entrano qui quando esistono (feature 27 e 14).
@MainActor
struct MainMenuTests {
    @Test func appMenuHasTheStandardItems() throws {
        let mainMenu = try #require(NSApp.mainMenu)
        let appMenu = try #require(mainMenu.items.first?.submenu)
        let actions = appMenu.items.compactMap(\.action)
        #expect(actions.contains(#selector(NSApplication.orderFrontStandardAboutPanel(_:))), "Manca Informazioni su Bubo.")
        #expect(actions.contains(#selector(NSApplication.hide(_:))), "Manca Nascondi Bubo.")
        #expect(actions.contains(#selector(NSApplication.terminate(_:))), "Manca Esci da Bubo.")
        #expect(appMenu.items.contains { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command },
                "Manca Impostazioni… con ⌘,.")
    }

    @Test func editWindowAndHelpMenusExist() throws {
        let mainMenu = try #require(NSApp.mainMenu)
        #expect(Self.items(in: mainMenu).contains { $0.action == #selector(NSText.copy(_:)) }, "Manca il menu Modifica.")
        #expect(NSApp.windowsMenu != nil, "Manca il menu Finestra.")
        #expect(NSApp.helpMenu != nil, "Manca il menu Aiuto.")
    }

    @Test func menuAndGlobalShortcutsDoNotCollide() throws {
        let mainMenu = try #require(NSApp.mainMenu)
        let shortcuts = Self.items(in: mainMenu).compactMap(Self.shortcut(of:)) + [KeyShortcut.showHUD.displayName]
        #expect(Self.duplicates(in: shortcuts).isEmpty)
    }

    @Test func nuovaBozzaHasItsShortcut() throws {
        let mainMenu = try #require(NSApp.mainMenu)
        let item = try #require(Self.items(in: mainMenu).first { $0.title == String(localized: "Nuova Bozza…") })
        #expect(Self.shortcut(of: item) == "⌥⌘N")
    }

    @Test func theTerminalHasItsShortcut() throws {
        let mainMenu = try #require(NSApp.mainMenu)
        let item = try #require(Self.items(in: mainMenu).first { $0.title == String(localized: "Mostra il terminale") })
        // ⌃ and the key left of 1, whose character AppKit adapts to the keyboard layout: ` in English, < in Italian.
        #expect(item.keyEquivalentModifierMask.intersection([.command, .option, .control, .shift]) == .control)
        #expect(!item.keyEquivalent.isEmpty)
    }

    @Test func aRepeatedShortcutIsFound() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Uno", action: nil, keyEquivalent: "k")
        menu.addItem(withTitle: "Due", action: nil, keyEquivalent: "k")
        menu.addItem(withTitle: "Tre", action: nil, keyEquivalent: "K")
        let shortcuts = Self.items(in: menu).compactMap(Self.shortcut(of:))
        #expect(Self.duplicates(in: shortcuts) == ["⌘K"])
    }

    /// Every item of `menu` and of its submenus, depth first.
    private static func items(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in [item] + (item.submenu.map(items(in:)) ?? []) }
    }

    /// The item's shortcut written like a ``KeyShortcut``, such as `⇧⌘K`, or `nil` without one.
    private static func shortcut(of item: NSMenuItem) -> String? {
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

    /// The shortcuts that appear more than once, sorted.
    private static func duplicates(in shortcuts: [String]) -> [String] {
        Dictionary(grouping: shortcuts, by: \.self).filter { $0.value.count > 1 }.keys.sorted()
    }
}
