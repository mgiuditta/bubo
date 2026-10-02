import SwiftUI
import UniformTypeIdentifiers

/// The editor the visore opens files in: the first one found, one of the others installed, or any app (spec 15).
struct EditorSettingsSection: View {
    @AppStorage(EditorLauncher.defaultsKey) private var chosenEditor = ""
    @State private var installed: [Editor] = []
    @State private var other: Editor?
    @State private var isChoosingApp = false

    var body: some View {
        Section {
            if installed.isEmpty && other == nil {
                Text("Nessun editor trovato. Installa VS Code, Cursor, Zed o Xcode, o scegli un'altra app.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Apri i file con", selection: $chosenEditor) {
                    if let first = installed.first {
                        Text("Automatico (\(first.name))").tag("")
                    }
                    ForEach(installed) { editor in
                        Text(verbatim: editor.name).tag(editor.bundleID)
                    }
                    if let other {
                        Text(verbatim: other.name).tag(other.bundleID)
                    }
                }
            }
            Button("Scegli un'altra app…") { isChoosingApp = true }
        } header: {
            Text("Editor")
        } footer: {
            Text("VS Code, Cursor, Zed e Xcode aprono il file alla riga giusta; le altre app lo aprono dall'inizio.")
        }
        .fileImporter(isPresented: $isChoosingApp, allowedContentTypes: [.applicationBundle]) { result in
            guard case let .success(application) = result,
                  let bundleID = Bundle(url: application)?.bundleIdentifier
            else { return }
            chosenEditor = bundleID
            refresh()
        }
        .task { refresh() }
    }

    /// Reads which editors are installed, and the chosen app when it is not one of them.
    private func refresh() {
        // An app uninstalled since it was chosen: back to the first editor found.
        if !chosenEditor.isEmpty && EditorLauncher.application(of: chosenEditor) == nil { chosenEditor = "" }
        installed = EditorLauncher.installed()
        let chosen = EditorLauncher.preferred(chosen: chosenEditor)
        other = chosen?.kind == .other ? chosen : nil
    }
}
