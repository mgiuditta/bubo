import AppKit
import os
import SwiftUI

/// Owns the app-wide services that must exist before any window appears.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Shows and hides the HUD.
    let hud = HUDPresenter()
    /// The always-on-top Panel with the Orb.
    let panel = OrbPanelController()
    /// The Indice, kept fresh while Bubo runs; `nil` when its database cannot be opened.
    let searchIndex: SearchIndex? = {
        do {
            return try SearchIndex.makeDefault()
        } catch {
            Logger.index.error("Indice unavailable: \(error)")
            return nil
        }
    }()
    /// The Domanda of the HUD, answered through the agent bridge.
    private(set) lazy var questions = QuestionModel(index: searchIndex)
    /// The global shortcut; created at launch so it works with no window open.
    private(set) lazy var hotKeys = HotKeyCenter { [hud] in hud.toggle() }

    func applicationWillFinishLaunching(_ notification: Notification) {
        FontRegistry.registerBundledFonts()
        UserDefaults.standard.register(defaults: [DockIcon.defaultsKey: true])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DockIcon.apply(isVisible: UserDefaults.standard.bool(forKey: DockIcon.defaultsKey))
        _ = hotKeys
        Task(priority: .utility) { [searchIndex] in await searchIndex?.keepFresh() }
        // The same SwiftUI menu as the menu bar's, so the two never drift apart.
        let menu = NSHostingMenu(rootView: MenuBarContent()
            .environment(hud)
            .environment(hotKeys)
            .environment(panel))
        panel.start(openingHUD: { [hud] in hud.show() }, menu: menu)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { hud.show() }
        return true
    }
}
