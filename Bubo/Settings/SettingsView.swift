import SwiftUI

/// Bubo's settings window.
// ponytail: Aspetto, Account e Permessi si aggiungono con le feature che li riempiono (niente sezioni vuote).
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Generale", systemImage: "gearshape") {
                GeneralSettingsView()
            }
            Tab("Scorciatoie", systemImage: "keyboard") {
                ShortcutSettingsView()
            }
        }
        .frame(width: 480)
        .scenePadding()
    }
}
