import os
import SwiftUI

/// Edits a memory file: the text shown is the file that Salva writes, so the editor is its own preview.
///
/// Salva writes only if the file is still as it was read, and only while no Sessione of the Progetto is in a turn.
struct MemoryEditor: View {
    let file: MemoryFile
    /// Whether a Sessione of the Progetto is in a turn: then Salva waits.
    let isInTurn: Bool
    /// Reads the memory again after a save.
    let saved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var failure: LocalizedStringResource?
    @State private var isSaving = false

    private var isIndex: Bool { file.name == ProjectMemory.indexName }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(verbatim: file.name)
                .font(.headline.monospaced())
                .accessibilityAddTraits(.isHeader)
            TextEditor(text: $text)
                .font(.body.monospaced())
                .accessibilityLabel(Text(verbatim: file.name))
            if isIndex {
                let index = ProjectMemory.Index(text: text)
                Text("\(index.lineCount) righe su \(ProjectMemory.lineLimit) · \(Int64(index.byteCount).formatted(.byteCount(style: .file))) su \(Int64(ProjectMemory.byteLimit).formatted(.byteCount(style: .file)))")
                    .font(.callout)
                    .foregroundStyle(index.isNearLimit ? Palette.danger : .secondary)
            }
            if isInTurn {
                Text("Una Sessione del Progetto sta lavorando: potrai salvare quando si ferma.")
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
                Button("Salva") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isInTurn || isSaving || text == file.text)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 560, height: 520)
        .onAppear { text = file.text }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try ProjectMemory.write(text, to: file.name, in: file.directory, expecting: file.text)
            await saved()
            dismiss()
        } catch ProjectMemoryError.changedOnDisk {
            failure = "Il file è cambiato su disco mentre lo modificavi. Chiudi e riaprilo per vedere la versione nuova."
        } catch {
            Logger.memory.error("Memory file not written: \(String(describing: error), privacy: .private)")
            failure = "Non riesco a salvare il file. Controlla di poter scrivere nella cartella, poi riprova."
        }
    }
}
