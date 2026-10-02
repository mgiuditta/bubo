import SwiftUI

/// The Vista delle Sessioni and Riduci movimento.
struct AppearanceSettingsView: View {
    @AppStorage(VistaDelleSessioni.defaultsKey) private var vista = VistaDelleSessioni.colonna
    @AppStorage(Motion.reducesMotionKey) private var reducesMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReducesMotion

    var body: some View {
        Form {
            Picker("Vista delle Sessioni", selection: $vista) {
                ForEach(VistaDelleSessioni.allCases) { vista in
                    Text(vista.title).tag(vista)
                }
            }
            Text("L'HUD si apre con questa vista.")
                .font(.callout)
                .foregroundStyle(.secondary)
            // The system's setting wins: the switch shows it on and cannot turn it off.
            Toggle("Riduci movimento", isOn: systemReducesMotion ? .constant(true) : $reducesMotion)
                .tint(Palette.switchTrack)
                .disabled(systemReducesMotion)
            Group {
                if systemReducesMotion {
                    Text("Attivo nelle Impostazioni di Sistema, in Accessibilità › Display.")
                } else {
                    Text("L'Orb sfuma invece di cambiare forma e si muove più piano.")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
