import SwiftUI

/// Bubo's settings window.
// ponytail: Permessi si aggiunge con la feature che lo riempie (niente sezioni vuote).
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Generale", systemImage: "gearshape") {
                GeneralSettingsView()
            }
            Tab("Aspetto", systemImage: "paintbrush") {
                AppearanceSettingsView()
            }
            Tab("Account", systemImage: "person.crop.circle") {
                AccountSettingsView()
            }
            Tab("Scorciatoie", systemImage: "keyboard") {
                ShortcutSettingsView()
            }
            Tab("Diagnostica", systemImage: "stethoscope") {
                DiagnosticsView()
            }
        }
        .frame(width: 480)
        .scenePadding()
    }
}
