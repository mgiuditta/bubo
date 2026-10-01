import os
import SwiftUI

/// A Cronologia CLI conversation, read only: the text of the user and of Claude, latest messages last.
struct CLITranscriptSheet: View {
    let conversation: CLIConversation
    /// Reads the messages of a conversation.
    let read: (CLIConversation) async throws -> [CLIConversation.Message]
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [CLIConversation.Message]?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(verbatim: conversation.title)
                .font(Typography.body(size: 15, weight: .semibold))
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            if let messages {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.small) {
                        ForEach(messages.indices, id: \.self) { index in
                            MessageView(message: messages[index])
                        }
                    }
                }
                .defaultScrollAnchor(.bottom)
            } else if failed {
                ErrorNotice("Non riesco a leggere la conversazione",
                            remedy: "Controlla che la CLI claude funzioni nel Terminale, poi riprova.",
                            actionTitle: "Riprova") { attempt += 1 }
                Spacer()
            } else {
                LoadingLabel("Leggo la conversazione…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Spacer()
                Button("Chiudi") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 560, height: 600)
        .task(id: attempt) { await load() }
    }

    private func load() async {
        failed = false
        do {
            messages = try await read(conversation)
        } catch is CancellationError {
        } catch {
            Logger.agent.error("Transcript not read: \(String(describing: error), privacy: .private)")
            failed = true
        }
    }
}

/// One message: who wrote it, then its text.
private struct MessageView: View {
    let message: CLIConversation.Message

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text(message.isFromUser ? "Tu" : "Claude")
                .font(Typography.mono(size: 10, weight: .medium))
                .textCase(.uppercase)
                .foregroundStyle(Palette.textSecondary)
            Text(verbatim: message.text)
                .font(Typography.body(size: 13))
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    CLITranscriptSheet(conversation: CLIConversation(id: "a", title: "Correggi il login", folder: nil, branch: "main",
                                                     lastModified: .now)) { _ in
        [CLIConversation.Message(isFromUser: true, text: "Il login non funziona"),
         CLIConversation.Message(isFromUser: false, text: "Guardo il controller della sessione.")]
    }
}
