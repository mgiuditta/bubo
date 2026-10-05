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
    @State private var choice = EngineChoice.claude
    @State private var isProjectDefault = false
    @State private var isChoosingFolder = false
    @State private var isAskingTrust = false
    /// Why the Sessione did not start: the sheet stays open to say it.
    @State private var failure: String?
    /// While the `/` menu shows, Invio and Esc go to it, not to the sheet's buttons.
    @State private var isSlashMenuShowing = false
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
                if !draft.files.isEmpty {
                    LabeledContent("File da guardare") {
                        Text(verbatim: draft.files.map(\.lastPathComponent).formatted(.list(type: .and)))
                            .lineLimit(2)
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
                    .slashCompletion(text: $prompt, folder: project, isShowing: $isSlashMenuShowing)
                TextField("Titolo", text: $title)
                EngineChoiceField(choice: $choice, isProjectDefault: $isProjectDefault,
                                  copilotModels: store.copilotModels)
                Toggle(isOn: $isOnCheckout) {
                    Text("Lavora direttamente nella cartella")
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

            if let failure {
                Text(verbatim: failure)
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(isSlashMenuShowing ? nil : .cancelAction)
                Button("Crea", action: create)
                    .keyboardShortcut(isSlashMenuShowing ? nil : .defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 520)
        .onAppear {
            project = project ?? draft.project ?? draft.conversation?.folder ?? store.projects.first
            if draft.continuesQuestion { title = Session.proposedTitle(for: draft.question) }
            if let conversation = draft.conversation { title = Session.proposedTitle(for: conversation.title) }
            prompt = draft.prompt
            isPromptFocused = true
        }
        // The proposals follow the prompt until the user writes their own.
        .onChange(of: prompt) { old, new in
            if title == Session.proposedTitle(for: old) { title = Session.proposedTitle(for: new) }
        }
        // Each Progetto starts on its own engine and model.
        .onChange(of: project, initial: true) {
            guard let project else { return }
            choice = store.engines.choice(for: project)
            isProjectDefault = false
            // Straight in the Progetto's folder, on the branch it has open: no branch to name. A copy of its own
            // only when another Sessione already works there.
            isOnCheckout = store.checkoutSession(of: project) == nil
        }
        .task { await store.loadCopilotModels() }
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
            if start() { dismiss() }
        } else {
            isAskingTrust = true
        }
    }

    /// Starts the Sessione, and tells whether it started; the trust dialog closes the sheet on its own.
    @discardableResult
    private func start() -> Bool {
        guard let project else { return false }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if isProjectDefault { store.engines.setChoice(choice, for: project) }
        do {
            try store.start(draft.firstPrompt(text),
                            title: name.isEmpty ? Session.proposedTitle(for: text.isEmpty ? draft.question : text) : name,
                            branch: branch.trimmingCharacters(in: .whitespaces), in: project, onCheckout: isOnCheckout,
                            forkingFrom: draft.conversation, upTo: draft.upToMessage, choice: choice,
                            fromQuestion: draft.originQuestion)
            return true
        } catch {
            Logger.sessions.error("Sessione not started: \(String(describing: error), privacy: .public)")
            failure = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "La Sessione non è partita. Riprova.")
            return false
        }
    }
}
