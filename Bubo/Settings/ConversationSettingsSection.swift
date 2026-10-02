import os
import SwiftUI

/// The copy of the conversations (ADR 0006): whether the Cronologia CLI is kept too, and the space it all takes.
struct ConversationSettingsSection: View {
    @Environment(SessionStore.self) private var sessions: SessionStore?
    @AppStorage(ConversationStore.keepsCLIHistoryKey) private var keepsCLIHistory = true
    @State private var size: Int64?
    @State private var failure: String?

    var body: some View {
        Section {
            Toggle("Conserva anche le conversazioni della riga di comando", isOn: $keepsCLIHistory)
                .tint(Palette.switchTrack)
                .onChange(of: keepsCLIHistory) { _, keeps in
                    Task { await apply(keeps) }
                }
            if let failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(Palette.danger)
            }
            LabeledContent("Spazio occupato") {
                if let size {
                    Text(size, format: .byteCount(style: .file))
                }
            }
        } header: {
            Text("Conversazioni")
        } footer: {
            Text("Claude Code cancella le conversazioni dopo 30 giorni; Bubo ne conserva una copia. Quella di una Sessione se ne va quando la elimini.")
        }
        .task { readSize() }
    }

    private func apply(_ keeps: Bool) async {
        do {
            if keeps {
                _ = try await sessions?.keepCLIHistory()
            } else {
                try await sessions?.forgetCLIHistory()
            }
            failure = nil
        } catch {
            Logger.sessions.error("Cronologia CLI setting not applied: \(String(describing: error), privacy: .private)")
            failure = keeps
                ? String(localized: "Non riesco a copiare le conversazioni della riga di comando ora: ci riprovo più tardi.")
                : String(localized: "Non riesco a cancellare le copie delle conversazioni della riga di comando.")
        }
        readSize()
    }

    private func readSize() {
        size = (try? ConversationStore.defaultFile()).map(ConversationStore.size(of:))
    }
}
