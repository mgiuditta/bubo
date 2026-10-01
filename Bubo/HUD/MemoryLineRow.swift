import os
import SwiftUI

/// A line Ricordato or Richiamato in a Sessione's flow, with Apri and, for a Ricordato, Annulla (spec 13).
///
/// Annulla is disabled while a Sessione of the Progetto is in a turn: Bubo never writes in the memory while an agent may.
struct MemoryLineRow: View {
    let line: MemoryLine
    /// Whether a Sessione of the Progetto is in a turn.
    let isInTurn: Bool
    /// Puts the file back as it was before the write.
    let undo: () throws -> Void
    @State private var isOpen = false
    @State private var failure = ""
    @State private var isShowingFailure = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xxSmall) {
                Text(line.isRemembered ? "Ricordato" : "Richiamato")
                    .font(Typography.body(size: 11, weight: .semibold))
                Text(verbatim: line.subject)
                    .font(Typography.body(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Spacing.xSmall)
            Button("Apri") { isOpen = true }
            if line.isUndone {
                Text("Annullato")
                    .font(Typography.body(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            } else if line.canUndo {
                Button("Annulla", action: runUndo)
                    .disabled(isInTurn)
                    .help(isInTurn ? "Potrai annullare quando nessuna Sessione del Progetto sta lavorando"
                                   : "Rimette il file com'era prima di questa scrittura")
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .font(Typography.body(size: 11))
        .sheet(isPresented: $isOpen) {
            MemoryLineSheet(line: line)
        }
        .alert("Scrittura non annullata", isPresented: $isShowingFailure) {
            Button("OK") {}
        } message: {
            Text(verbatim: failure)
        }
    }

    private func runUndo() {
        do {
            try undo()
            return
        } catch ProjectMemoryError.changedOnDisk {
            failure = String(localized: "Il file è cambiato dopo questa scrittura: annullando perderesti le modifiche successive. Puoi modificarlo da Memoria del Progetto.")
        } catch ProjectMemoryError.inTurn {
            failure = String(localized: "Una Sessione del Progetto sta lavorando. Riprova quando si ferma.")
        } catch {
            Logger.memory.error("Memory write not undone: \(String(describing: error), privacy: .private)")
            failure = String(localized: "Non riesco a rimettere il file com'era. Controlla di poter scrivere nella cartella della memoria, poi riprova.")
        }
        isShowingFailure = true
    }
}
