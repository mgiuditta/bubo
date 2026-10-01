import SwiftUI

/// Login item, Dock icon, Panel, conversations, Secondo cervello and editor.
struct GeneralSettingsView: View {
    @Environment(OrbPanelController.self) private var panel
    @AppStorage(DockIcon.defaultsKey) private var showsDockIcon = true
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        @Bindable var panel = panel
        Form {
            Toggle("Apri Bubo al login", isOn: $opensAtLogin)
                .onChange(of: opensAtLogin) { _, enabled in updateLoginItem(enabled) }
            if let loginItemError {
                Text(loginItemError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Toggle("Mostra l'icona nel Dock", isOn: $showsDockIcon)
                .onChange(of: showsDockIcon) { _, visible in DockIcon.apply(isVisible: visible) }
            Text("Bubo resta sempre nella barra dei menu.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Mostra il Panel con l'Orb", isOn: $panel.isShown)
            ConversationSettingsSection()
            SecondBrainSettingsSection()
            EditorSettingsSection()
        }
        .formStyle(.grouped)
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = String(localized: "Non riesco a cambiare l'apertura al login: \(error.localizedDescription)")
            opensAtLogin = LoginItem.isEnabled
        }
    }
}
