import SwiftUI

/// Bubo's settings window.
// ponytail: Aspetto e Permessi si aggiungono con le feature che li riempiono (niente sezioni vuote).
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Generale", systemImage: "gearshape") {
                GeneralSettingsView()
            }
            Tab("Account", systemImage: "person.crop.circle") {
                AccountSettingsView()
            }
            Tab("Scorciatoie", systemImage: "keyboard") {
                ShortcutSettingsView()
            }
        }
        .frame(width: 480)
        .scenePadding()
    }
}
