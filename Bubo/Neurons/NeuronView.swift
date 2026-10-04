import AppKit
import SwiftUI

/// The Neuroni: the map of the notes and their links, and on the right the list with the folder filter and the
/// search.
struct NeuronView: View {
    let model: NeuronModel
    /// The Domanda, whose last answer's cited notes the map rings.
    let questions: QuestionModel
    /// A note opened in Quick Look, when the Secondo cervello is not an Obsidian vault or Obsidian is missing.
    @State private var previewedNote: URL?

    var body: some View {
        HSplitView {
            map
                .frame(minWidth: 360)
            NeuronList(model: model, open: open)
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 480)
        }
        .foregroundStyle(Palette.textPrimary)
        .background(Palette.ink)
        .quickLookPreview($previewedNote)
        .task { await model.watch() }
        .task {
            for await answer in Observations({ [questions] in questions.answer }) {
                model.show(citations: NoteCitation.markdownLinking(answer, scheme: "nota").citations)
            }
        }
    }

    private var map: some View {
        ZStack(alignment: .topTrailing) {
            NeuronMap(model: model, open: open)
                .accessibilityHidden(true)
            NeuronLabels(model: model)
            if model.graph == nil {
                LoadingLabel("Leggo le note…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.graph?.notes.isEmpty == true {
                ContentUnavailableView("Nessuna nota nel Secondo cervello", systemImage: "point.3.connected.trianglepath.dotted",
                                       description: Text("Le note Markdown che aggiungi alla cartella compaiono qui da sole."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button("Mostra tutto", systemImage: "arrow.up.left.and.arrow.down.right") { model.fit() }
                .keyboardShortcut("0")
                .disabled(model.graph == nil)
                .help("Mostra tutte le note (⌘0)")
                .buttonStyle(.borderless)
                .controlSize(.small)
                .padding(.horizontal, Spacing.small)
                // Room for the window's buttons: the bar sits under its transparent title bar.
                .padding(.top, 28)
        }
    }

    /// Opens the note at `index` in Obsidian, or in Quick Look, as the citations of an answer do.
    private func open(_ index: Int) {
        guard let file = model.file(of: index) else { return }
        let hasObsidian = NoteDestination.obsidianLink(to: URL(filePath: "/"))
            .flatMap(NSWorkspace.shared.urlForApplication(toOpen:)) != nil
        switch NoteDestination(file: file, isObsidianVault: model.secondBrain.isObsidianVault, hasObsidian: hasObsidian) {
        case let .obsidian(link):
            NSWorkspace.shared.open(link)
        case let .quickLook(file):
            previewedNote = file
        }
    }
}
