import os
import SwiftUI

/// Confirms the deletion of a memory, showing the file that goes and the `MEMORY.md` that stays without its lines.
struct MemoryDeletion: View {
    /// A memory to delete, with the read it was chosen from.
    struct Request: Identifiable {
        let memory: ProjectMemory
        let topic: ProjectMemory.Topic

        var id: String { topic.name }
    }

    let request: Request
    /// Whether a Sessione of the Progetto is in a turn: then Cancella waits.
    let isInTurn: Bool
    /// Reads the memory again after the deletion.
    let deleted: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var failure: LocalizedStringResource?

    /// The index after the deletion, when it changes.
    private var trimmedIndex: String? {
        let trimmed = request.memory.index(removing: request.topic.name)
        return trimmed == request.memory.index?.text ? nil : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("Vuoi cancellare il ricordo «\(request.topic.title ?? request.topic.name)»?")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            preview(title: "Il file \(request.topic.name) viene cancellato:", text: request.topic.text)
            if let trimmedIndex {
                preview(title: "\(ProjectMemory.indexName) diventa:", text: trimmedIndex)
            }
            if isInTurn {
                Text("Una Sessione del Progetto sta lavorando: potrai cancellare quando si ferma.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(Palette.danger)
            }
            HStack {
                Spacer()
                Button("Annulla") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Cancella", role: .destructive) { Task { await delete() } }
                    .disabled(isInTurn)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 560, height: 560)
    }

    private func preview(title: LocalizedStringResource, text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(verbatim: text)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Spacing.xSmall)
            .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.small))
        }
    }

    private func delete() async {
        do {
            try request.memory.delete(request.topic)
            await deleted()
            dismiss()
        } catch ProjectMemoryError.changedOnDisk {
            failure = "La memoria è cambiata su disco. Chiudi e riapri il ricordo per vedere la versione nuova."
        } catch {
            Logger.memory.error("Memory file not deleted: \(String(describing: error), privacy: .private)")
            failure = "Non riesco a cancellare il file. Controlla di poter scrivere nella cartella, poi riprova."
        }
    }
}
