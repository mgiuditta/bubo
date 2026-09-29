import SwiftUI

/// The menu of Bubo's menu bar item.
// ponytail: Sessioni in Attende te e quota arrivano con le feature 03 e 06.
struct MenuBarContent: View {
    @Environment(HUDPresenter.self) private var hud
    @Environment(HotKeyCenter.self) private var hotKeys
    @Environment(OrbPanelController.self) private var panel

    var body: some View {
        @Bindable var panel = panel
        Button("Mostra HUD  \(hotKeys.shortcut.displayName)") { hud.show() }
        Toggle("Mostra Panel", isOn: $panel.isShown)
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
