import AppKit
import Testing
@testable import Bubo

/// The app menu has the standard items, and no two shortcuts collide.
@MainActor
struct MainMenuTests {
    @Test func appMenuHasTheStandardItems() throws {
        let mainMenu = try #require(NSApp.mainMenu)
        let appMenu = try #require(mainMenu.items.first?.submenu)
        let actions = appMenu.items.compactMap(\.action)
        // Informazioni su Bubo opens the standard panel with Bubo's credits, through its own action.
        #expect(appMenu.items.contains { $0.title == String(localized: "Informazioni su Bubo") }, "Manca Informazioni su Bubo.")
        // Off in a build that does not update itself, so with no action in the tests.
        #expect(appMenu.items.contains { $0.title == String(localized: "Controlla aggiornamenti…") },
                "Manca Controlla aggiornamenti….")
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

    @Test func sessioneDaIssueHasItsShortcut() throws {
        let mainMenu = try #require(NSApp.mainMenu)
        let item = try #require(Self.items(in: mainMenu).first { $0.title == String(localized: "Sessione da issue GitHub…") })
        #expect(Self.shortcut(of: item) == "⌘I")
    }

    @Test func theTerminalHasItsShortcut() throws {
        let mainMenu = try #require(NSApp.mainMenu)
        let item = try #require(Self.items(in: mainMenu).first { $0.title == String(localized: "Mostra il terminale") })
        // ⌃ and the key left of 1, whose character AppKit adapts to the keyboard layout: ` in English, < in Italian.
        #expect(item.keyEquivalentModifierMask.intersection([.command, .option, .control, .shift]) == .control)
        #expect(!item.keyEquivalent.isEmpty)
    }

    @Test func theAnteprimaHasItsShortcut() throws {
        let mainMenu = try #require(NSApp.mainMenu)
        let item = try #require(Self.items(in: mainMenu).first { $0.title == String(localized: "Mostra l'anteprima") })
        #expect(Self.shortcut(of: item) == "⇧⌘P")
    }

    @Test func agentiIsInTheWindowMenuWithoutAShortcut() throws {
        let windowMenu = try #require(NSApp.windowsMenu)
        let item = try #require(Self.items(in: windowMenu).first { $0.title == String(localized: "Agenti") })
        #expect(Self.shortcut(of: item) == nil)
    }

    @Test func pluginIsInTheWindowMenuWithoutAShortcut() throws {
        let windowMenu = try #require(NSApp.windowsMenu)
        let item = try #require(Self.items(in: windowMenu).first { $0.title == String(localized: "Plugin") })
        #expect(Self.shortcut(of: item) == nil)
    }

    @Test func automazioniIsInTheWindowMenuWithoutAShortcut() throws {
        let windowMenu = try #require(NSApp.windowsMenu)
        let item = try #require(Self.items(in: windowMenu).first { $0.title == String(localized: "Automazioni") })
        #expect(Self.shortcut(of: item) == nil)
    }

    @Test func cronologiaIsInTheWindowMenuWithoutAShortcut() throws {
        let windowMenu = try #require(NSApp.windowsMenu)
        let item = try #require(Self.items(in: windowMenu).first { $0.title == String(localized: "Cronologia") })
        #expect(Self.shortcut(of: item) == nil)
    }

    @Test func theGalassiaHasItsShortcut() throws {
        let mainMenu = try #require(NSApp.mainMenu)
        let item = try #require(Self.items(in: mainMenu).first { $0.title == String(localized: "Mostra la Galassia") })
        #expect(Self.shortcut(of: item) == "⌥⌘G")
    }

    @Test func thePaletteHasItsShortcut() throws {
        let mainMenu = try #require(NSApp.mainMenu)
        let item = try #require(Self.items(in: mainMenu).first { $0.title == String(localized: "Cerca…") })
        #expect(Self.shortcut(of: item) == "⌘K")
    }

    /// Every command of the menus is in the Palette, with the same shortcut (spec 14).
    @Test func everyMenuCommandIsInThePalette() throws {
        let mainMenu = try #require(NSApp.mainMenu)
        let commands = CommandCatalog.commands(in: mainMenu)
        #expect(commands.contains { $0.title == String(localized: "Mostra la Galassia") && $0.shortcut == "⌥⌘G" })
        #expect(commands.contains { $0.title == String(localized: "Sessione da issue GitHub…") && $0.shortcut == "⌘I" })
        #expect(commands.contains { $0.title == String(localized: "Agenti") && $0.shortcut == nil })
        #expect(commands.contains { $0.title == String(localized: "Plugin") && $0.shortcut == nil })
        let editMenu = try #require(mainMenu.items.compactMap(\.submenu).first {
            $0.items.contains { $0.action == #selector(NSText.copy(_:)) }
        })
        let left = Set(Self.items(in: editMenu).map(\.title) + [String(localized: "Cerca…")])
        for item in Self.items(in: mainMenu) where item.submenu == nil && item.action != nil && item.isEnabled && !item.isHidden
            && !item.isAlternate && item.view == nil && !item.title.isEmpty && !(item.target is NSWindow)
            && !left.contains(item.title) && item.menu !== NSApp.servicesMenu {
            #expect(commands.contains { $0.title == item.title && $0.shortcut == Self.shortcut(of: item) },
                    "Manca nella Palette: \(item.title)")
        }
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
        CommandCatalog.shortcut(of: item)
    }

    /// The shortcuts that appear more than once, sorted.
    private static func duplicates(in shortcuts: [String]) -> [String] {
        Dictionary(grouping: shortcuts, by: \.self).filter { $0.value.count > 1 }.keys.sorted()
    }
}
