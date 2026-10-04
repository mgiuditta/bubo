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
            Tab("Voce", systemImage: "waveform", value: SettingsTab.voice) {
                VoiceSettingsView()
            }
            Tab("Scorciatoie", systemImage: "keyboard", value: SettingsTab.shortcuts) {
                ShortcutSettingsView()
            }
            Tab("Aggiornamenti", systemImage: "arrow.triangle.2.circlepath", value: SettingsTab.updates) {
                UpdatesSettingsView()
            }
            // A Group: the builder takes at most 10 tabs.
            Group {
                Tab("Diagnostica", systemImage: "stethoscope", value: SettingsTab.diagnostics) {
                    DiagnosticsView()
                }
                // Last, after the tabs in use: the areas that «Arriverà presto» in a Release build (PRD #514).
                Tab("Macchine", systemImage: "server.rack", value: SettingsTab.machines) {
                    ReleaseGated(.machines) {
                        MachinesSettingsView()
                    }
                }
                Tab("iPhone", systemImage: "iphone", value: SettingsTab.iPhone) {
                    ReleaseGated(.remote) {
                        RemoteSettingsView()
                    }
                }
                Tab("Consegne", systemImage: "shippingbox", value: SettingsTab.deliveries) {
                    ReleaseGated(.deliveries) {
                        DeliveriesSettingsView()
                    }
                }
            }
        }
        .frame(width: 480)
        .scenePadding()
        // System controls, but selection is lightness, not the system blue (design system).
        .tint(Palette.accent)
    }
}
