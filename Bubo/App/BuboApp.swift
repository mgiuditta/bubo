import SwiftUI

@main
struct BuboApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Bubo", id: HUDPresenter.windowID) {
            HUDView()
                .environment(appDelegate.hud)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .defaultLaunchBehavior(.presented)

        Settings {
            SettingsView()
                .environment(appDelegate.hotKeys)
                .environment(appDelegate.panel)
        }

        MenuBarExtra("Bubo", systemImage: "smallcircle.filled.circle") {
            MenuBarContent()
                .environment(appDelegate.hud)
                .environment(appDelegate.hotKeys)
                .environment(appDelegate.panel)
        }

        #if DEBUG
        Window("Debug Orb", id: OrbDebugView.windowID) {
            OrbDebugView(controls: .shared)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        #endif
    }
}
