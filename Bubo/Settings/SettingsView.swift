import SwiftUI

/// Bubo's settings window.
struct SettingsView: View {
    /// The tab shown, kept across launches; another window may choose it before opening the settings.
    @AppStorage(SettingsTab.defaultsKey) private var tab = SettingsTab.general

    var body: some View {
        TabView(selection: $tab) {
            Tab("Generale", systemImage: "gearshape", value: SettingsTab.general) {
                GeneralSettingsView()
            }
            Tab("Aspetto", systemImage: "paintbrush", value: SettingsTab.appearance) {
                AppearanceSettingsView()
            }
            Tab("Account", systemImage: "person.crop.circle", value: SettingsTab.account) {
                AccountSettingsView()
            }
            Tab("Permessi", systemImage: "lock.shield", value: SettingsTab.permissions) {
                PermissionsSettingsView()
            }
            Tab("Modelli", systemImage: "cpu", value: SettingsTab.models) {
                ModelsSettingsView()
            }
            Tab("Budget", systemImage: "gauge.with.dots.needle.67percent", value: SettingsTab.budget) {
                BudgetSettingsView()
            }
            Tab("Macchine", systemImage: "server.rack", value: SettingsTab.machines) {
                MachinesSettingsView()
            }
            Tab("Voce", systemImage: "waveform", value: SettingsTab.voice) {
                VoiceSettingsView()
            }
            Tab("iPhone", systemImage: "iphone", value: SettingsTab.iPhone) {
                RemoteSettingsView()
            }
            // A Group: the builder takes at most 10 tabs.
            Group {
                Tab("Consegne", systemImage: "shippingbox", value: SettingsTab.deliveries) {
                    DeliveriesSettingsView()
                }
                Tab("Scorciatoie", systemImage: "keyboard", value: SettingsTab.shortcuts) {
                    ShortcutSettingsView()
                }
                Tab("Diagnostica", systemImage: "stethoscope", value: SettingsTab.diagnostics) {
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
