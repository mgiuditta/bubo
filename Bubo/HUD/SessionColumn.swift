import SwiftUI

/// The Colonna Vista of the HUD: one row per Sessione, newest first.
// ponytail: minimal Colonna; grouping by Attività, waits and summaries come with #75.
struct SessionColumn: View {
    let store: SessionStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xSmall) {
                ForEach(store.sessions.reversed()) { session in
                    SessionRow(session: session, store: store)
                }
            }
            .padding(Spacing.small)
        }
        .frame(width: 280)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.panel))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sessioni")
    }
}

/// A Sessione in the Colonna: title, Attività or Fase, and Progetto · branch; Riprendi after Bubo's quitting
/// interrupted it, Archivia and Cancella… in its menu.
private struct SessionRow: View {
    let session: Session
    let store: SessionStore
    /// What deleting the Sessione would lose, while its confirmation is shown.
    @State private var lostChanges: [String] = []
    @State private var isConfirmingDeletion = false

    private var isArchived: Bool { session.phase == .archiviata }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: session.title)
                    .font(Typography.body(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: Spacing.xSmall)
                Text(isArchived ? session.phase.title : session.activity.title)
                    .font(Typography.mono(size: 10, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(session.activity == .errore && !isArchived ? Palette.danger : Palette.textSecondary)
            }
            Text(verbatim: [session.project.lastPathComponent,
                            session.isOnCheckout ? String(localized: "sul checkout") : session.workspace?.branch]
                .compactMap(\.self).joined(separator: " · "))
                .font(Typography.mono(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            if let failure = session.failure, !isArchived {
                Text(verbatim: failure)
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            if let setupFailure = session.setupFailure, !isArchived {
                Text(verbatim: setupFailure)
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
            if session.isInterrupted && session.activity == .ferma && session.prompt != nil {
                Button("Riprendi") { store.resume(session.id) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, Spacing.xxSmall)
            }
        }
        .padding(Spacing.xSmall)
        .opacity(isArchived ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .contextMenu {
            if !isArchived {
                Button("Archivia") { store.archive(session.id) }
                    .disabled(session.activity == .lavora)
            }
            Button("Cancella…", role: .destructive, action: confirmDeletion)
                .disabled(session.activity == .lavora)
        }
        .accessibilityActions {
            if session.activity != .lavora {
                if !isArchived { Button("Archivia") { store.archive(session.id) } }
                Button("Cancella…", action: confirmDeletion)
            }
        }
        .confirmationDialog("Vuoi cancellare la Sessione «\(session.title)»?", isPresented: $isConfirmingDeletion) {
            Button("Cancella", role: .destructive) { store.delete(session.id) }
        } message: {
            Text(deletionMessage)
        }
    }

    private func confirmDeletion() {
        Task {
            lostChanges = await store.lostChanges(session.id)
            isConfirmingDeletion = true
        }
    }

    /// The confirmation's message: what goes with the Sessione, and the changes lost, at most 12.
    private var deletionMessage: String {
        guard let branch = session.workspace?.branch else {
            return String(localized: "La Sessione viene tolta dall'elenco. I file del Progetto non vengono toccati.")
        }
        guard !lostChanges.isEmpty else {
            return String(localized: "Verranno cancellati la copia isolata e il branch \(branch). Nessuna modifica andrà persa.")
        }
        let shown = lostChanges.prefix(12) + (lostChanges.count > 12 ? ["…"] : [])
        return String(localized: "Verranno cancellati la copia isolata e il branch \(branch). Queste modifiche andranno perse:")
            + "\n" + shown.joined(separator: "\n")
    }
}

#Preview {
    let folder = FileManager.default.temporaryDirectory
    let file = folder.appending(path: "SessionColumnPreview.json")
    var interrupted = Session(id: UUID(), title: "Correggi il login", project: folder,
                              workspace: Workspace(folder: folder, branch: "bubo/correggi-il-login"),
                              activity: .lavora,
                              setupFailure: "Lo script di setup è uscito con codice 1.\nnpm error code ENOENT")
    interrupted.prompt = "Correggi il login"
    var archived = Session(id: UUID(), title: "Aggiorna le dipendenze", project: folder, activity: .ferma)
    archived.phase = .archiviata
    try? JSONEncoder().encode([
        archived,
        interrupted,
        Session(id: UUID(), title: "Rinomina il modulo", project: folder, activity: .errore,
                failure: "fatal: a branch named 'bubo/x' already exists"),
    ]).write(to: file)
    return SessionColumn(store: SessionStore(file: file, worktrees: WorktreeManager(root: folder)) {
        throw CancellationError()
    })
    .padding()
    .background(Palette.ink)
}
