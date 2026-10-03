import os
import SwiftUI

/// «Salvato in [[nota]] · Annulla» under a Domanda that wrote in the Secondo cervello with `ricorda`.
struct SavedNoteLine: View {
    let change: BrainChange
    /// Puts the note back as it was before the write.
    let undo: () throws -> Void
    @Environment(\.openURL) private var openURL
    @State private var failure = ""
    @State private var isShowingFailure = false

    var body: some View {
        HStack(spacing: Spacing.small) {
            Label("Salvato in \(change.link)", systemImage: "bookmark")
                .font(Typography.body(size: 13))
                .foregroundStyle(Palette.textSecondary)
            if change.isUndone {
                Text("Annullato")
                    .font(Typography.body(size: 13))
                    .foregroundStyle(Palette.textSecondary)
            } else {
                Button("Apri la nota") { openURL(change.file) }
                    .accessibilityIdentifier("question.openNote")
                Button("Annulla", action: runUndo)
                    .help("Riporta la nota com'era prima di questo salvataggio")
                    .accessibilityHint(Text("Riporta \(change.link) com'era prima di questo salvataggio"))
                    .accessibilityIdentifier("question.undoNote")
            }
        }
        .alert("Salvataggio non annullato", isPresented: $isShowingFailure) {
            Button("OK") {}
        } message: {
            Text(verbatim: failure)
        }
    }

    private func runUndo() {
        do {
            try undo()
            return
        } catch BrainChange.UndoFailure.changedOnDisk {
            failure = String(localized: "La nota è cambiata dopo questo salvataggio: annullando perderesti le modifiche successive.")
        } catch {
            Logger.index.error("Note write not undone: \(String(describing: error), privacy: .private)")
            failure = String(localized: "Non riesco a riportare la nota com'era. Controlla di poter scrivere nella cartella del Secondo cervello, poi riprova.")
        }
        isShowingFailure = true
    }
}
