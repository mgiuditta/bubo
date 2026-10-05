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
        // ponytail: not an HSplitView, which kept the list's width and spilled the map out of the window when the
        // sidebar widened; the map takes what is left, the list stays 300 pt.
        HStack(spacing: 0) {
            map
                .frame(minWidth: 0, maxWidth: .infinity)
            Divider()
                .overlay(Palette.line)
            NeuronList(model: model, open: open)
                .frame(width: 300)
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
            HStack(spacing: Spacing.xSmall) {
                // Only for a vault, with Obsidian on the Mac: the selected note, else the vault itself.
                if model.secondBrain.isObsidianVault, Self.hasObsidian {
                    Button("Apri in Obsidian", systemImage: "arrow.up.forward.app", action: openInObsidian)
                        .keyboardShortcut("o")
                        .help(model.selection == nil ? "Apri il vault in Obsidian (⌘O)" : "Apri la nota in Obsidian (⌘O)")
                }
                Button("Mostra tutto", systemImage: "arrow.up.left.and.arrow.down.right") { model.fit() }
                    .keyboardShortcut("0")
                    .disabled(model.graph == nil)
                    .help("Mostra tutte le note (⌘0)")
            }
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
        switch NoteDestination(file: file, isObsidianVault: model.secondBrain.isObsidianVault,
                               hasObsidian: Self.hasObsidian) {
        case let .obsidian(link):
            NSWorkspace.shared.open(link)
        case let .quickLook(file):
            previewedNote = file
        }
    }

    /// Whether Obsidian is on the Mac: something opens its `obsidian://` links.
    private static var hasObsidian: Bool {
        NoteDestination.obsidianLink(to: URL(filePath: "/"))
            .flatMap(NSWorkspace.shared.urlForApplication(toOpen:)) != nil
    }

    /// Opens the selected note in Obsidian, or the vault when no note is selected.
    private func openInObsidian() {
        let target = model.selection.flatMap(model.file(of:)) ?? model.secondBrain.url
        guard let link = NoteDestination.obsidianLink(to: target) else { return }
        NSWorkspace.shared.open(link)
    }
}
