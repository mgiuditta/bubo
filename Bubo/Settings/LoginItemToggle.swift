import SwiftUI

/// "Apri Bubo al login", with the button to System Settings while the system waits for the user's approval, and why a
/// change failed.
struct LoginItemToggle: View {
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var requiresApproval = LoginItem.requiresApproval
    @State private var error: String?

    var body: some View {
        Toggle("Apri Bubo al login", isOn: $opensAtLogin)
            .tint(Palette.switchTrack)
            .onChange(of: opensAtLogin) { _, enabled in update(enabled) }
        if requiresApproval {
            HStack {
                Text("macOS aspetta la tua approvazione in Impostazioni di Sistema.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Apri Impostazioni di Sistema", action: LoginItem.openSystemSettings)
            }
        }
        if let error {
            Text(error)
                .font(.callout)
                .foregroundStyle(Palette.danger)
        }
    }

    private func update(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            error = nil
        } catch {
            self.error = String(localized: "Non riesco a cambiare l'apertura al login: \(error.localizedDescription)")
            opensAtLogin = LoginItem.isEnabled
        }
        requiresApproval = LoginItem.requiresApproval
    }
}
