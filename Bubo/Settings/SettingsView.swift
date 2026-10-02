import SwiftUI

/// Bubo's settings window.
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
            Tab("Permessi", systemImage: "lock.shield") {
                PermissionsSettingsView()
            }
            Tab("Modelli", systemImage: "cpu") {
                ModelsSettingsView()
            }
            Tab("Macchine", systemImage: "server.rack") {
                MachinesSettingsView()
            }
            Tab("Voce", systemImage: "waveform") {
                VoiceSettingsView()
            }
            Tab("iPhone", systemImage: "iphone") {
                RemoteSettingsView()
            }
            // A Group: the builder takes at most 10 tabs.
            Group {
                Tab("Consegne", systemImage: "shippingbox") {
                    DeliveriesSettingsView()
                }
                Tab("Scorciatoie", systemImage: "keyboard") {
                    ShortcutSettingsView()
                }
                Tab("Diagnostica", systemImage: "stethoscope") {
                    DiagnosticsView()
                }
            }
        }
        .frame(width: 480)
        .scenePadding()
        // System controls, but selection is lightness, not the system blue (design system).
        .tint(Palette.accent)
    }
}
