import SwiftUI

/// The map the model proposed for the Secondo cervello, in the Bolla under its answer: the folder, its settings, the
/// Profilo and the Regole to read, and "Applica", the user's yes. Without a model answering, the folder alone can still
/// be used.
struct SecondBrainProposalCard: View {
    let conversation: SecondBrainConversation
    @State private var applyFailed = false

    var body: some View {
        if let proposal = conversation.proposal {
            card(proposal)
        } else if conversation.isActive, conversation.questions.failure != nil, !conversation.isNew {
            Button("Usa la cartella senza configurarla", action: conversation.useFolderAsItIs)
        }
    }

    private func card(_ proposal: SecondBrainProposal) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            switch proposal.action {
            case .use: Text("Usa \(proposal.folder.lastPathComponent)").font(.headline)
            case .create: Text("Crea \(proposal.folder.lastPathComponent)").font(.headline)
            }
            Text(verbatim: proposal.folder.path)
                .font(.callout)
                .foregroundStyle(Palette.textSecondary)
            summary("Cartelle escluse", proposal.excludedFolders)
            summary("Cartelle prioritarie", proposal.priorityFolders)
            summary("Persone", proposal.people)
            summary("Progetti", proposal.projects)
            preview("Profilo", proposal.profile)
            preview("Regole", proposal.rules)
            if applyFailed {
                Text("Non riesco a scrivere in questa cartella: controlla che esista e che tu possa modificarla, poi premi di nuovo Applica.")
                    .font(.callout)
                    .foregroundStyle(Palette.danger)
            }
            HStack {
                Spacer()
                Button("Applica") {
                    do {
                        try conversation.apply()
                    } catch {
                        applyFailed = true
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Spacing.medium)
        .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
    }

    @ViewBuilder private func summary(_ title: LocalizedStringKey, _ names: [String]) -> some View {
        if !names.isEmpty {
            LabeledContent(title) { Text(verbatim: names.joined(separator: ", ")) }
                .font(.callout)
        }
    }

    /// The file `text` becomes, to read before saying yes; nothing when it stays as it is.
    @ViewBuilder private func preview(_ title: LocalizedStringKey, _ text: String) -> some View {
        if !text.isEmpty {
            DisclosureGroup(title) {
                ScrollView {
                    Text(Self.markdown(text))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }
            .font(.callout)
        }
    }

    /// `text` with its inline Markdown, as the model writes it.
    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
