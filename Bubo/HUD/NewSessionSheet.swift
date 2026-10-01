import SwiftUI

/// ⌘N: a new Sessione on a Progetto, with its title and branch proposed from the prompt.
///
/// In a folder that is not trusted, the trust dialog comes first (#266).
struct NewSessionSheet: View {
    let store: SessionStore
    var gate = TrustGate()
    @Environment(\.dismiss) private var dismiss
    @State private var project: URL?
    @State private var prompt = ""
    @State private var title = ""
    @State private var branch = Session.proposedBranch(for: "")
    @State private var isChoosingFolder = false
    @State private var isAskingTrust = false
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        if isAskingTrust, let project {
            TrustSheet(folder: project, activations: RepoActivations(folder: project), start: start, gate: gate)
        } else {
            form
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Form {
                LabeledContent("Progetto") {
                    HStack {
                        Text(verbatim: project?.lastPathComponent ?? "")
                            .help(project?.path ?? "")
                        Button(project == nil ? "Scegli cartella…" : "Cambia…") { isChoosingFolder = true }
                    }
                }
                TextField("Cosa deve fare Claude?", text: $prompt, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($isPromptFocused)
                TextField("Titolo", text: $title)
                TextField("Branch", text: $branch)
                    .font(.body.monospaced())
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Crea", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(project == nil || branch.trimmingCharacters(in: .whitespaces).isEmpty
                              || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 520)
        .onAppear {
            project = project ?? store.projects.first
            isPromptFocused = true
        }
        // The proposals follow the prompt until the user writes their own.
        .onChange(of: prompt) { old, new in
            if title == Session.proposedTitle(for: old) { title = Session.proposedTitle(for: new) }
        }
        .onChange(of: title) { old, new in
            if branch == Session.proposedBranch(for: old) { branch = Session.proposedBranch(for: new) }
        }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(folder) = result { project = folder }
        }
    }

    private func create() {
        guard let project else { return }
        if gate.isTrusted(project) {
            start()
            dismiss()
        } else {
            isAskingTrust = true
        }
    }

    /// Starts the Sessione; the trust dialog closes the sheet on its own.
    private func start() {
        guard let project else { return }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        store.start(text, title: name.isEmpty ? Session.proposedTitle(for: text) : name,
                    branch: branch.trimmingCharacters(in: .whitespaces), in: project)
    }
}
