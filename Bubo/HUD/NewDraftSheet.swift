import SwiftUI

/// ⌥⌘N, or + Nuova Bozza on the Board: a Bozza written by hand, with its Progetto, title and text. Nothing starts:
/// the Bozza waits in Da iniziare for Avvia.
struct NewDraftSheet: View {
    let store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var project: URL?
    @State private var title = ""
    @State private var text = ""
    @State private var isChoosingFolder = false
    @State private var choice = EngineChoice.claude
    @State private var isProjectDefault = false
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Form {
                LabeledContent("Progetto") {
                    HStack {
                        Text(verbatim: project?.lastPathComponent ?? "")
                            .help(project?.path ?? "")
                        Button(project == nil ? "Scegli cartella…" : "Cambia…") { isChoosingFolder = true }
                    }
                }
                TextField("Titolo", text: $title)
                    .focused($isTitleFocused)
                TextField("Cosa deve fare Claude?", text: $text, axis: .vertical)
                    .lineLimit(3...8)
                EngineChoiceField(choice: $choice, isProjectDefault: $isProjectDefault,
                                  copilotModels: store.copilotModels)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Salva Bozza", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(project == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 520)
        .onAppear {
            project = project ?? store.drafts.drafts.last?.project ?? store.projects.first
            isTitleFocused = true
        }
        // Each Progetto starts on its own engine and model.
        .onChange(of: project, initial: true) {
            guard let project else { return }
            choice = store.engines.choice(for: project)
            isProjectDefault = false
        }
        .task { await store.loadCopilotModels() }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(folder) = result { project = folder }
        }
    }

    private func save() {
        guard let project else { return }
        if isProjectDefault { store.engines.setChoice(choice, for: project) }
        store.drafts.add(Draft(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                               text: text.trimmingCharacters(in: .whitespacesAndNewlines), project: project,
                               choice: choice))
        dismiss()
    }
}
