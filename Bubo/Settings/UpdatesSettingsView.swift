import SwiftUI

/// Impostazioni › Aggiornamenti: the automatic checks, the install on quit, the Canale beta and the version (spec 27).
struct UpdatesSettingsView: View {
    @Environment(UpdateController.self) private var updates

    var body: some View {
        @Bindable var updates = updates
        Form {
            Section {
                Toggle("Controlla aggiornamenti in automatico", isOn: $updates.checksAutomatically)
                    .tint(Palette.switchTrack)
                Toggle("Installa gli aggiornamenti quando esci", isOn: $updates.installsOnQuit)
                    .tint(Palette.switchTrack)
                    .disabled(!updates.checksAutomatically)
                Toggle("Ricevi le beta", isOn: $updates.receivesBeta)
                    .tint(Palette.switchTrack)
                Text("Le beta arrivano prima e possono avere difetti. Se le spegni, resti sulla versione che hai fino alla stabile successiva.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } footer: {
                if !updates.isEnabled {
                    Text("Gli aggiornamenti sono spenti in questa build.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!updates.isEnabled)
            Section {
                LabeledContent("Versione", value: Self.version)
                LabeledContent("Ultimo controllo") {
                    if let date = updates.lastCheckDate {
                        Text(date, format: .relative(presentation: .named))
                    } else {
                        Text("Mai")
                    }
                }
                Button("Controlla ora", action: updates.checkForUpdates)
                    .disabled(!updates.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
    }

    /// The release name and the build number, such as "1.2.0-beta.3 (build 42)".
    private static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let name = info["BuboReleaseName"] as? String ?? info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        return String(localized: "\(name) (build \(build))")
    }
}

#Preview {
    UpdatesSettingsView()
        .environment(UpdateController(isEnabled: false))
}
