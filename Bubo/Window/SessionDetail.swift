import SwiftUI

/// A Sessione opened from the Conversazioni: its card with state, Richieste and actions, its conversation, and the
/// composer of its next turn (ADR 0013).
struct SessionDetail: View {
    let session: Session
    let store: SessionStore
    @State private var text = ""
    @State private var reader: ConversationReader?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SessionRow(session: session, store: store)
                .padding([.horizontal, .top], Spacing.l)
            Divider().overlay(Palette.line).padding(.top, Spacing.m)
            Group {
                if let reader {
                    ConversationReaderView(reader: reader)
                } else {
                    ContentUnavailableView("Ancora nessuna risposta", systemImage: "text.bubble",
                                           description: Text("La conversazione compare qui al primo turno."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The terminal and the Anteprima opened from this Sessione's card: here too, not only in the home.
            PanelRow(terminals: store.terminals, previews: store.previews)
            composer
        }
        // A finished turn adds its conversation: read it again.
        .task(id: "\(session.id)-\(session.conversations.last ?? "")-\(session.activity.rawValue)") { await load() }
    }

    private var composer: some View {
        HStack(spacing: Spacing.s) {
            RecipientChip(recipient: .project(session.project))
            TextField("Scrivi alla Sessione", text: $text, prompt: Text(placeholder), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.buboBody)
                .lineLimit(1...6)
                .onSubmit(send)
                .disabled(!session.canTakeTurn)
            // While it works the turn can be stopped, and continued afterwards.
            if session.isLive && session.isRunning {
                Button("Ferma", systemImage: "stop.fill") { store.interrupt(session.id) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .help("Ferma il turno: poi puoi continuare la Sessione")
            } else {
                Button("Invia", systemImage: "arrow.up", action: send)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.canTakeTurn || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .overlay(Capsule().strokeBorder(Palette.lineStrong))
        .frame(maxWidth: Spacing.readingWidth)
        .frame(maxWidth: .infinity)
        .padding(Spacing.l)
    }

    private var placeholder: String {
        switch (session.isLive, session.activity) {
        case (false, _): String(localized: "Sessione archiviata")
        case (_, .lavora): String(localized: "Sta lavorando…")
        case (_, .attende): String(localized: "Rispondi alla Richiesta qui sopra")
        default: String(localized: "Continua la Sessione")
        }
    }

    private func send() {
        if store.send(text, to: session.id) { text = "" }
    }

    private func load() async {
        guard let result = ConversationResult(latestOf: session) else {
            reader = nil
            return
        }
        let reader = ConversationReader(result: result, words: [], resumeID: nil,
                                        read: { [store] in try await store.transcript(ofConversation: $0) },
                                        indexed: { _ in [] })
        await reader.load()
        self.reader = reader
    }
}
