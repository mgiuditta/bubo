import SwiftUI

/// The menu of Bubo's menu bar item.
// ponytail: Sessioni in Attende te e quota arrivano con le feature 03 e 06.
struct MenuBarContent: View {
    @Environment(HUDPresenter.self) private var hud
    @Environment(HotKeyCenter.self) private var hotKeys

    var body: some View {
        Button("Mostra HUD  \(hotKeys.shortcut.displayName)") { hud.show() }
        Divider()
        SettingsLink {
            Text("Impostazioni…")
        }
        .keyboardShortcut(",")
        Divider()
        Button("Esci da Bubo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
