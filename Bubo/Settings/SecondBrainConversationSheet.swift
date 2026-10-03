import SwiftUI
import UniformTypeIdentifiers

/// The setup of the Secondo cervello as a conversation with the model the user picks: it proposes a folder and its
/// settings, applied only with "Applica". Without a model answering, the folder can still be chosen by hand.
struct SecondBrainConversationSheet: View {
    @Environment(SecondBrain.self) private var secondBrain
    @Environment(QuestionModel.self) private var questions
    @Environment(\.dismiss) private var dismiss
    @State private var conversation: SecondBrainConversation?
    @State private var draft = ""
    @State private var isChoosingFolder = false
    @State private var applyFailed = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if let conversation {
                    messages(of: conversation)
                }
            }
            .defaultScrollAnchor(.bottom)
            Divider()
            if let proposal = conversation?.proposal {
                proposalCard(proposal)
                Divider()
            }
            composer
        }
        .frame(width: 520, height: 520)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            guard case let .success(folder) = result else { return }
            guard questions.failure == nil, let conversation else {
                // No model answers: the folder is all the setup there can be.
                secondBrain.choose(folder)
                dismiss()
                return
            }
            conversation.send(Self.chosen(folder))
        }
        .task {
            let started = SecondBrainConversation(questions: questions, secondBrain: secondBrain)
            conversation = started
            started.start()
        }
        .onChange(of: questions.isAnswering) { conversation?.receive() }
    }

    private func messages(of conversation: SecondBrainConversation) -> some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(conversation.turns) { turn in
                Text(Self.markdown(turn.text))
                    .textSelection(.enabled)
                    .padding(10)
                    .background(turn.isUser ? Palette.switchTrack : .clear, in: .rect(cornerRadius: 10))
                    .frame(maxWidth: .infinity, alignment: turn.isUser ? .trailing : .leading)
            }
            if conversation.isWaiting {
                if questions.answer.isEmpty {
                    LoadingLabel("Il modello scrive…")
                } else {
                    Text(verbatim: SecondBrainProposal.prose(of: questions.answer))
                        .foregroundStyle(Palette.textSecondary)
                }
            } else if questions.failure != nil {
                Text("Il modello non risponde. Puoi scegliere la cartella a mano.")
                    .foregroundStyle(Palette.danger)
            }
        }
        .padding(16)
    }

    private func proposalCard(_ proposal: SecondBrainProposal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch proposal.action {
            case .use: Text("Usa \(proposal.folder.lastPathComponent)").font(.headline)
            case .create: Text("Crea \(proposal.folder.lastPathComponent)").font(.headline)
            }
            Text(verbatim: proposal.folder.path)
                .font(.callout)
                .foregroundStyle(Palette.textSecondary)
            summary("Escluse", proposal.excludedFolders)
            summary("Prioritarie", proposal.priorityFolders)
            summary("Persone", proposal.people)
            summary("Progetti", proposal.projects)
            if applyFailed {
                Text("Non riesco a usare questa cartella. Chiedi un'altra proposta o sceglila a mano.")
                    .font(.callout)
                    .foregroundStyle(Palette.danger)
            }
            HStack {
                Spacer()
                Button("Applica") {
                    do {
                        try conversation?.apply()
                        dismiss()
                    } catch {
                        applyFailed = true
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    @ViewBuilder private func summary(_ title: LocalizedStringKey, _ names: [String]) -> some View {
        if !names.isEmpty {
            LabeledContent(title) { Text(verbatim: names.joined(separator: ", ")) }
                .font(.callout)
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            HStack {
                ModelPicker(model: questions)
                TextField("Rispondi", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button("Invia", action: send)
                    .disabled(conversation?.isWaiting != false || draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Button("Scegli la cartella a mano…") { isChoosingFolder = true }
                    .disabled(conversation?.isWaiting == true)
                Spacer()
                Button("Chiudi") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
    }

    private func send() {
        guard conversation?.isWaiting == false else { return }
        conversation?.send(draft)
        draft = ""
    }

    /// What the user tells the model on choosing `folder` by hand, so it proposes the settings of that folder.
    private static func chosen(_ folder: URL) -> String {
        let folders = SecondBrainLocation(folder: folder).topFolders()
        let listed = folders.isEmpty ? "nessuna sottocartella" : folders.joined(separator: ", ")
        // In Italian like the instructions the model reads, not shown as interface text.
        return "Ho scelto la cartella \(folder.path) (cartelle in cima: \(listed)). Proponi come usarla."
    }

    /// `text` with its inline Markdown, as the model writes it.
    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
