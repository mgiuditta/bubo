import AppKit

/// Owns the app-wide services that must exist before any window appears.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Shows and hides the HUD.
    let hud = HUDPresenter()
    /// The always-on-top Panel with the Orb.
    let panel = OrbPanelController()
    /// The global shortcut; created at launch so it works with no window open.
    private(set) lazy var hotKeys = HotKeyCenter { [hud] in hud.toggle() }

    func applicationWillFinishLaunching(_ notification: Notification) {
        FontRegistry.registerBundledFonts()
        UserDefaults.standard.register(defaults: [DockIcon.defaultsKey: true])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DockIcon.apply(isVisible: UserDefaults.standard.bool(forKey: DockIcon.defaultsKey))
        _ = hotKeys
        panel.start(openingHUD: { [hud] in hud.show() })
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { hud.show() }
        return true
    }
}
