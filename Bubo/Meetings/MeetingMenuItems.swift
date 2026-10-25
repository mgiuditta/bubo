import SwiftUI

/// «Registra una Riunione…», or «Ferma e salva la Riunione» while one is recorded, then «Apri il Suggeritore», «Importa Riunioni…» and «Trascrivi un video da un link…»: in the menu
/// bar, the Orb's menu and, through the File menu, the Palette.
struct MeetingMenuItems: View {
    let recorder: MeetingRecorder

    var body: some View {
        if recorder.isRecording {
            Button("Ferma e salva la Riunione") { Task { await recorder.stop() } }
        } else {
            Button("Registra una Riunione…") { recorder.showWindow() }
        }
        Button("Apri il Suggeritore") { recorder.showPrompter() }
        Button("Importa Riunioni…") { recorder.imports.chooseFiles() }
            .disabled(recorder.imports.isImporting)
        Button("Trascrivi un video da un link…") { recorder.imports.chooseVideoLink() }
            .disabled(recorder.imports.isImporting)
    }
}

/// The menu bar item shown only while a Riunione is recorded: always visible, and read by VoiceOver.
struct MeetingIndicator: View {
    var body: some View {
        Label("Registrazione della Riunione in corso", systemImage: "record.circle.fill")
    }
}
