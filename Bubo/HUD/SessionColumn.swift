import os
import SwiftUI

/// The Colonna Vista of the HUD: the open Sessioni grouped by Attività, Attende te first and the longest wait on top,
/// the others newest first; then the archived ones, then the Cronologia CLI apart. One search filters them all.
struct SessionColumn: View {
    let store: SessionStore
    @Environment(HUDPresenter.self) private var hud
    @State private var search = ""
    /// The Cronologia CLI read so far: the most recent, or all of it once a search asked for it.
    @State private var history: [CLIConversation] = []
    @State private var isHistoryComplete = false
    /// The conversation shown read only.
    @State private var reading: CLIConversation?

    private var query: String { search.trimmingCharacters(in: .whitespaces) }

    private var sessions: [Session] {
        store.sessions.reversed().filter { session in
            query.isEmpty || [session.title, session.project.path, session.workspace?.branch]
                .contains { $0?.localizedStandardContains(query) == true }
        }
    }

    /// The groups shown, in order, without the empty ones.
    private var groups: [(title: LocalizedStringResource, sessions: [Session])] {
        let open = Session.grouped(sessions.filter { $0.phase == .aperta })
            .map { (title: $0.activity.title, sessions: $0.sessions) }
        let archived = sessions.filter { $0.phase == .archiviata }
        return archived.isEmpty ? open : open + [(title: "Archiviate", sessions: archived)]
    }

    private var conversations: [CLIConversation] {
        query.isEmpty ? history : history.filter { $0.matches(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Cerca", text: $search, prompt: Text("Cerca nelle Sessioni e nella Cronologia CLI"))
                .textFieldStyle(.roundedBorder)
                .padding([.horizontal, .top], Spacing.small)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xSmall) {
                    ForEach(groups, id: \.title.key) { group in
                        GroupHeader(title: Text("\(Text(group.title)) · \(group.sessions.count)"))
                        ForEach(group.sessions) { session in
                            SessionRow(session: session, store: store)
                        }
                    }
                    if !conversations.isEmpty {
                        GroupHeader(title: Text("Cronologia CLI"))
                        ForEach(conversations) { conversation in
                            CLIConversationRow(conversation: conversation) {
                                hud.createSession(from: SessionDraft(conversation: conversation))
                            } read: {
                                reading = conversation
                            }
                        }
                    }
                }
                .padding(Spacing.small)
            }
        }
        .frame(width: 280)
        .task { await loadHistory(isComplete: false) }
        // The first page is enough to look; a search looks in all of it, read once.
        .task(id: query.isEmpty) {
            guard !query.isEmpty, !isHistoryComplete else { return }
            await loadHistory(isComplete: true)
        }
        .sheet(item: $reading) { conversation in
            CLITranscriptSheet(conversation: conversation, read: store.transcript(of:))
        }
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.panel))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sessioni")
    }

    /// Reads the Cronologia CLI; when it cannot, the Colonna shows only the Sessioni.
    private func loadHistory(isComplete: Bool) async {
        do {
            let read = try await store.history(isComplete: isComplete)
            // The first page arriving after all of it would hide the rest.
            guard isComplete || !isHistoryComplete else { return }
            history = read
            isHistoryComplete = isComplete
        } catch is CancellationError {
        } catch {
            Logger.sessions.error("Cronologia CLI not read: \(String(describing: error), privacy: .private)")
        }
    }
}

/// The title of a group in the Colonna.
private struct GroupHeader: View {
    let title: Text

    var body: some View {
        title
            .font(Typography.mono(size: 10, weight: .medium))
            .textCase(.uppercase)
            .foregroundStyle(Palette.textSecondary)
            .padding([.horizontal, .top], Spacing.xSmall)
            .accessibilityAddTraits(.isHeader)
    }
}

/// How long a Sessione has been in its Attività, minute by minute; in Lume when it waits for the user.
private struct ActivityWait: View {
    let since: Date
    let isWaitingForUser: Bool

    var body: some View {
        TimelineView(.everyMinute) { context in
            let elapsed = Duration.seconds(max(0, context.date.timeIntervalSince(since)))
            if elapsed < .seconds(60) {
                label(Text("adesso"), spoken: Text("adesso"))
            } else {
                let wide = elapsed.formatted(Self.style(width: .wide))
                label(Text(verbatim: elapsed.formatted(Self.style(width: .abbreviated))),
                      spoken: isWaitingForUser ? Text("Attende da \(wide)") : Text(verbatim: wide))
            }
        }
    }

    private static func style(width: Duration.UnitsFormatStyle.UnitWidth) -> Duration.UnitsFormatStyle {
        .units(allowed: [.days, .hours, .minutes], width: width, maximumUnitCount: 2)
    }

    private func label(_ text: Text, spoken: Text) -> some View {
        text
            .font(Typography.mono(size: 10, weight: .medium))
            .foregroundStyle(isWaitingForUser ? Palette.attention : Palette.textSecondary)
            .lineLimit(1)
            .accessibilityLabel(spoken)
    }
}

/// A Cronologia CLI conversation in the Colonna: title, when, folder · branch; Riprendi opens a new Sessione
/// that continues it as a fork, Leggi shows it.
private struct CLIConversationRow: View {
    let conversation: CLIConversation
    let resume: () -> Void
    let read: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: conversation.title)
                    .font(Typography.body(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: Spacing.xSmall)
                Text(conversation.lastModified, format: .relative(presentation: .named))
                    .font(Typography.mono(size: 10, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Text(verbatim: [conversation.folder?.lastPathComponent, conversation.branch]
                .compactMap(\.self).joined(separator: " · "))
                .font(Typography.mono(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            HStack {
                Button("Riprendi", action: resume)
                Button("Leggi", action: read)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, Spacing.xxSmall)
        }
        .padding(Spacing.xSmall)
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("Riprendi", action: resume)
            Button("Leggi", action: read)
        }
        .accessibilityActions {
            Button("Riprendi", action: resume)
            Button("Leggi", action: read)
        }
    }
}

/// A Sessione in the Colonna: title, how long it has been in its Attività, the one-line summary, and
/// Progetto · branch · Fase; Riprendi after Bubo's quitting interrupted it, Archivia, Cancella… and the configuration
/// of Claude in its Progetto in its menu.
private struct SessionRow: View {
    let session: Session
    let store: SessionStore
    /// What deleting the Sessione would lose, while its confirmation is shown.
    @State private var lostChanges: [String] = []
    @State private var isConfirmingDeletion = false
    @State private var isShowingConfiguration = false

    private var isArchived: Bool { session.phase == .archiviata }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(verbatim: session.title)
                    .font(Typography.body(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: Spacing.xSmall)
                if let since = session.activitySince {
                    ActivityWait(since: since, isWaitingForUser: session.activity == .attende && !isArchived)
                }
            }
            if let summary = session.summary {
                Text(verbatim: summary)
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Text(verbatim: [session.project.lastPathComponent,
                            session.isOnCheckout ? String(localized: "sul checkout") : session.workspace?.branch,
                            String(localized: session.phase.title)]
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
            Button("Configurazione di Claude…") { isShowingConfiguration = true }
            if !isArchived {
                Button("Archivia") { store.archive(session.id) }
                    .disabled(session.isRunning)
            }
            Button("Cancella…", role: .destructive, action: confirmDeletion)
                .disabled(session.isRunning)
        }
        .accessibilityActions {
            Button("Configurazione di Claude…") { isShowingConfiguration = true }
            if !session.isRunning {
                if !isArchived { Button("Archivia") { store.archive(session.id) } }
                Button("Cancella…", action: confirmDeletion)
            }
        }
        .sheet(isPresented: $isShowingConfiguration) {
            ConfigPanel(project: session.project, read: store.configuration(of:))
        }
        .confirmationDialog("Vuoi cancellare la Sessione «\(session.title)»?", isPresented: $isConfirmingDeletion) {
            Button("Cancella", role: .destructive) { store.delete(session.id) }
        } message: {
            Text(deletionMessage)
        }
    }

    /// The dot before the title: Lume only for Attende te, danger for Errore, faint once it stops.
    private var dotColor: Color {
        switch session.activity {
        case .attende: Palette.attention
        case .errore: Palette.danger
        case .lavora: Palette.textPrimary
        case .ferma: Palette.textFaint
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
                              activity: .lavora, activitySince: .now.addingTimeInterval(-600),
                              summary: "Ho corretto il redirect dopo il login; mancano i test.",
                              setupFailure: "Lo script di setup è uscito con codice 1.\nnpm error code ENOENT")
    interrupted.prompt = "Correggi il login"
    var archived = Session(id: UUID(), title: "Aggiorna le dipendenze", project: folder, activity: .ferma,
                           activitySince: .now.addingTimeInterval(-7_200))
    archived.phase = .archiviata
    try? JSONEncoder().encode([
        archived,
        interrupted,
        Session(id: UUID(), title: "Pulizia branch vecchi", project: folder,
                workspace: Workspace(folder: folder, branch: "bubo/pulizia-branch-vecchi"), activity: .attende,
                activitySince: .now.addingTimeInterval(-240), summary: "Vuole cancellare 14 branch remoti già fusi."),
        Session(id: UUID(), title: "Rinomina il modulo", project: folder, activity: .errore,
                activitySince: .now.addingTimeInterval(-1_200), failure: "fatal: a branch named 'bubo/x' already exists"),
    ]).write(to: file)
    return SessionColumn(store: SessionStore(file: file, worktrees: WorktreeManager(root: folder)) {
        throw CancellationError()
    })
    .environment(HUDPresenter())
    .padding()
    .background(Palette.ink)
}
