import os
import SwiftUI

/// ⌘N: a new Sessione on a Progetto, with its title and branch proposed from the prompt, or from the Domanda or the
/// conversation it continues: whole from the Cronologia CLI, or up to a message with Continua da qui.
///
/// In a folder that is not trusted, the trust dialog comes first (#266).
struct NewSessionSheet: View {
    let store: SessionStore
    /// What the sheet starts from: empty for ⌘N, the Domanda for Trasforma in Sessione, a conversation for Riprendi.
    var draft = SessionDraft()
    var gate = TrustGate()
    @Environment(\.dismiss) private var dismiss
    @State private var project: URL?
    @State private var prompt = ""
    @State private var title = ""
    @State private var branch = Session.proposedBranch(for: "")
    @State private var isOnCheckout = false
    @State private var isChoosingFolder = false
    @State private var isAskingTrust = false
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        if isAskingTrust, let project {
            TrustSheet(folder: project, activations: RepoActivations(folder: project), start: { _ in start() },
                       gate: gate)
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
                if let conversation = draft.conversation {
                    LabeledContent {
                        Text(verbatim: conversation.title)
                            .lineLimit(2)
                    } label: {
                        if draft.upToMessage == nil {
                            Text("Riprende dalla Cronologia CLI")
                        } else {
                            Text("Continua da qui")
                        }
                    }
                }
                if draft.continuesQuestion {
                    LabeledContent("Continua la Domanda") {
                        Text(verbatim: draft.question)
                            .lineLimit(2)
                    }
                }
                TextField("Cosa deve fare Claude?", text: $prompt, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($isPromptFocused)
                TextField("Titolo", text: $title)
                Toggle(isOn: $isOnCheckout) {
                    Text("Lavora sul checkout")
                    Text(checkoutTaken?.errorDescription
                         ?? String(localized: "Senza copia isolata: le modifiche vanno direttamente nella cartella del Progetto."))
                        .foregroundStyle(checkoutTaken == nil ? Color.secondary : Palette.danger)
                }
                .tint(Palette.switchTrack)
                if !isOnCheckout {
                    TextField("Branch", text: $branch)
                        .font(.body.monospaced())
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Crea", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 520)
        .onAppear {
            project = project ?? draft.conversation?.folder ?? store.projects.first
            if draft.continuesQuestion { title = Session.proposedTitle(for: draft.question) }
            if let conversation = draft.conversation { title = Session.proposedTitle(for: conversation.title) }
            prompt = draft.prompt
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

    /// Why the Sessione cannot work on the checkout: another one of the Progetto already does.
    private var checkoutTaken: SessionError? {
        guard isOnCheckout, let project, let session = store.checkoutSession(of: project) else { return nil }
        return .checkoutTaken(by: session.title)
    }

    private var canCreate: Bool {
        project != nil && checkoutTaken == nil
            && (isOnCheckout || !branch.trimmingCharacters(in: .whitespaces).isEmpty)
            && (draft.canStartEmpty || !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        do {
            try store.start(draft.firstPrompt(text),
                            title: name.isEmpty ? Session.proposedTitle(for: text.isEmpty ? draft.question : text) : name,
                            branch: branch.trimmingCharacters(in: .whitespaces), in: project, onCheckout: isOnCheckout,
                            forkingFrom: draft.conversation, upTo: draft.upToMessage)
        } catch {
            // The sheet does not offer Crea while the checkout is taken: only a race gets here.
            Logger.sessions.error("Sessione not started: \(String(describing: error), privacy: .public)")
        }
    }
}
