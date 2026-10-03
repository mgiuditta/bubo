import os
import SwiftUI

/// A write of Bubo in the Secondo cervello, in Impostazioni › Secondo cervello, with Annulla.
struct BrainChangeRow: View {
    let change: BrainChange
    @Environment(SecondBrain.self) private var secondBrain
    @State private var failure = ""
    @State private var isShowingFailure = false

    var body: some View {
        LabeledContent {
            if change.isUndone {
                Text("Annullato")
                    .foregroundStyle(.secondary)
            } else {
                Button("Annulla", action: runUndo)
                    .accessibilityHint(Text("Riporta \(change.link) com'era prima di questo salvataggio"))
            }
        } label: {
            Text(verbatim: change.link)
            Text(change.previous == nil ? "Nota nuova · \(change.date, format: .relative(presentation: .named))"
                                        : "Nota modificata · \(change.date, format: .relative(presentation: .named))")
        }
        .alert("Salvataggio non annullato", isPresented: $isShowingFailure) {
            Button("OK") {}
        } message: {
            Text(verbatim: failure)
        }
    }

    private func runUndo() {
        do {
            try secondBrain.undo(change)
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
