import SwiftUI
import UniformTypeIdentifiers

/// The setup of the Secondo cervello: the user chooses the folder (the current one, a vault, any folder or a new one),
/// then talks about it with the model they pick, which proposes its settings, applied only with "Applica". Without a
/// model answering, the folder alone can still be used.
struct SecondBrainConversationSheet: View {
    @Environment(SecondBrain.self) private var secondBrain
    @Environment(QuestionModel.self) private var questions
    @Environment(\.dismiss) private var dismiss
    @State private var conversation: SecondBrainConversation?
    @State private var draft = ""
    @State private var isChoosingFolder = false
    @State private var applyFailed = false
    /// The folders offered before the conversation: the current one first, then the Obsidian vaults on this Mac.
    @State private var candidates: [URL] = []
    @State private var chosen: URL?

    /// Where a new Secondo cervello is created.
    private static let newFolder = URL.documentsDirectory.appending(path: "Secondo cervello", directoryHint: .isDirectory)

    var body: some View {
        Group {
            if conversation?.folder == nil {
                chooser
            } else {
                chat
            }
        }
        .frame(width: 520, height: 520)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            guard case let .success(folder) = result else { return }
            if !candidates.contains(folder) { candidates.append(folder) }
            chosen = folder
        }
        .task {
            conversation = SecondBrainConversation(questions: questions, secondBrain: secondBrain)
            let current = secondBrain.location?.url
            candidates = (current.map { [$0] } ?? [])
                + SecondBrainLocation.suggestedVaults().filter { $0.standardizedFileURL != current?.standardizedFileURL }
            chosen = current ?? candidates.first
        }
        .onChange(of: questions.isAnswering) { conversation?.receive() }
    }

    /// The choice of the folder, which is the user's alone.
    private var chooser: some View {
        Form {
            Section {
                Picker("Cartella", selection: $chosen) {
                    ForEach(candidates, id: \.self) { candidate in
                        Group {
                            if candidate.standardizedFileURL == secondBrain.location?.url.standardizedFileURL {
                                Text("\(candidate.lastPathComponent) (configurata)")
                            } else {
                                Text(verbatim: candidate.lastPathComponent)
                            }
                        }
                        .help(candidate.path)
                        .tag(Optional(candidate))
                    }
                    Text("Nuovo Secondo cervello").tag(Optional(Self.newFolder))
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Button("Scegli un'altra cartella…") { isChoosingFolder = true }
            } header: {
                Text("Quale cartella?")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            } footer: {
                Text("Poi ne parli con il modello che scegli: ti fa qualche domanda e propone come configurarla.")
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                ModelPicker(model: questions)
                Spacer()
                Button("Annulla") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Avanti") {
                    guard let chosen else { return }
                    let isNew = chosen == Self.newFolder && !FileManager.default.fileExists(atPath: chosen.path)
                    conversation?.start(with: chosen, isNew: isNew)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen == nil)
            }
            .padding([.horizontal, .bottom], 20)
        }
    }

    private var chat: some View {
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
                Text("Il modello non risponde. Prova un altro modello o usa la cartella così com'è.")
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
                if questions.failure != nil, let folder = conversation?.folder, conversation?.isNew == false {
                    Button("Usa la cartella senza configurarla") {
                        secondBrain.choose(folder)
                        dismiss()
                    }
                }
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

    /// `text` with its inline Markdown, as the model writes it.
    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
