import SwiftUI

/// Login item, Dock icon, Panel, conversations, Secondo cervello, search by meaning, editor and Linear.
struct GeneralSettingsView: View {
    @Environment(OrbPanelController.self) private var panel
    @AppStorage(DockIcon.defaultsKey) private var showsDockIcon = true

    var body: some View {
        @Bindable var panel = panel
        Form {
            LoginItemToggle()
            Toggle("Mostra l'icona nel Dock", isOn: $showsDockIcon)
                .tint(Palette.switchTrack)
                .onChange(of: showsDockIcon) { _, visible in DockIcon.apply(isVisible: visible) }
            Text("Bubo resta sempre nella barra dei menu.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Mostra il Panel con l'Orb", isOn: $panel.isShown)
                .tint(Palette.switchTrack)
            Toggle("Panel ridotto", isOn: $panel.isReduced)
                .tint(Palette.switchTrack)
                .disabled(!panel.isShown)
            Text("Orb piccolo in un angolo, con la conversazione nella Bolla. Vale solo per lo schermo in cui si trova ora il Panel.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ConversationSettingsSection()
            SecondBrainSettingsSection()
            ExcludedFoldersSection()
            PriorityFoldersSection()
            SemanticSearchSettingsSection()
            EditorSettingsSection()
            LinearSettingsSection()
        }
        .formStyle(.grouped)
    }
}
