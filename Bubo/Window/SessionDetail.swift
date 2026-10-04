import SwiftUI

/// A Sessione opened from the Conversazioni: its card with state, Richieste and actions, its conversation, and the
/// composer of its next turn (ADR 0013).
struct SessionDetail: View {
    let session: Session
    let store: SessionStore
    @State private var text = ""
    @State private var reader: ConversationReader?
    /// What the user sent from here for the turn in progress, shown until the turn's conversation is read.
    @State private var sent: String?
    @Environment(HUDPresenter.self) private var hud

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Where the Sessione is, and the way back to its Progetto: the sidebar only marks the Sessione.
            Button(session.project.lastPathComponent, systemImage: "chevron.backward") {
                hud.selection = .project(session.project)
            }
            .buttonStyle(.plain)
            .font(.buboBody)
            .foregroundStyle(Palette.textSecondary)
            .help("Torna alle Sessioni del Progetto")
            .accessibilityLabel("Torna a \(session.project.lastPathComponent)")
            .padding([.horizontal, .top], Spacing.l)
            SessionRow(session: session, store: store)
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.s)
            Divider().overlay(Palette.line).padding(.top, Spacing.m)
            Group {
                let lines = reader?.lines ?? []
                if lines.isEmpty && pendingPrompt == nil {
                    ContentUnavailableView("Ancora nessuna risposta", systemImage: "text.bubble",
                                           description: Text("La conversazione compare qui al primo turno."))
                } else {
                    SessionTranscript(lines: lines, pendingPrompt: pendingPrompt)
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

    /// The user's message of the turn in progress: what was sent from here, else the turn's own prompt.
    private var pendingPrompt: String? {
        guard session.activity == .lavora else { return nil }
        return sent ?? session.turnPrompt
    }

    private func send() {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.send(text, to: session.id) {
            sent = prompt
            text = ""
        }
    }

    private func load() async {
        // The turn ended: its message is in the conversation read below.
        if session.activity != .lavora { sent = nil }
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
