import SwiftUI

/// The Sandbox of a Progetto in its settings: one switch, off by default, counting from the next turn (spec 22).
struct ProjectSandboxSection: View {
    /// The Progetto's folder.
    let project: URL
    let store: SandboxStore
    @State private var isOn = false

    var body: some View {
        Section("Sandbox") {
            Toggle("Esegui i comandi di Claude in Sandbox", isOn: $isOn)
            Text("I comandi di Claude scrivono solo nella cartella della Sessione, nelle cartelle temporanee e nelle cache dei pacchetti, raggiungono solo i registri dei pacchetti e non leggono ~/.ssh, ~/.aws, ~/.gnupg e ~/.netrc. Se la Sandbox non parte, la Sessione non parte. Il terminale e i server non sono in Sandbox. Vale dal prossimo turno.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .onAppear { isOn = store.isEnabled(in: project) }
        .onChange(of: isOn) { _, isOn in store.setEnabled(isOn, in: project) }
    }
}
