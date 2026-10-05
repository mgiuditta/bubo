import os
import SwiftUI

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

struct SessionRow: View {
    @Environment(HUDPresenter.self) private var hud
    @Environment(SessionSummarizer.self) private var summarizer: SessionSummarizer?
    @Environment(DeliveriesController.self) private var deliveries: DeliveriesController?
    /// Says whether Bubo runs without `claude`, when the parts only Claude has are hidden (#729).
    @Environment(QuestionModel.self) private var questions: QuestionModel?
    let session: Session
    let store: SessionStore
    /// Whether the row is a card on the Board: `+n −m` in place of the cost, which stays in the Sessione.
    var isOnBoard = false
    /// The lines added and removed, read for the Board's card.
    @State private var lineCounts: (added: Int, removed: Int)?
    /// What deleting the Sessione would lose, while its confirmation is shown.
    @State private var lostChanges: [String] = []
    @State private var isConfirmingDeletion = false
    @State private var isShowingConfiguration = false
    @State private var isShowingMemory = false
    @State private var isReviewing = false
    /// What stops in the terminal at Archivia, while its confirmation is shown.
    @State private var archiveNotice = ""
    @State private var isConfirmingArchive = false
    /// The servers of the Sessione's `.claude/launch.json`, for Avvia server.
    @State private var launchServers: [LaunchConfig] = []
    /// Whether a drag from Finder or a browser is over the row.
    @State private var isDropTargeted = false
    @AppStorage(ReleaseArea.hidesUnreleasedKey) private var hidesUnreleased = false

    private var isArchived: Bool { !session.isLive }

    /// Whether the Esecuzione asked for the Modalità autonoma but `claude` chose another mode.
    private var isAutonomyUnavailable: Bool {
        session.automation != nil && session.permissionMode == .autonomous
            && session.effectiveMode.map { $0 != PermissionMode.autonomous.rawValue } == true
    }

    /// Gives what is dropped on the row to the Sessione when it is open, or else to a new Domanda; returns whether
    /// anything could be attached.
    private func drop(_ urls: [URL]) -> Bool {
        let attachments = HUDDropDestination.attachments(from: urls)
        guard !attachments.isEmpty else { return false }
        switch HUDDropDestination(sessionInFront: session) {
        case let .session(id):
            store.attach(attachments, to: id)
            let names = attachments.map(\.name).formatted(.list(type: .and))
            AccessibilityNotification.Announcement(String(localized: "Allegati a «\(session.title)»: \(names)")).post()
        case .question:
            hud.attachToQuestion(attachments)
        }
        return true
    }

    /// Whether the Sessione can go to another Macchina: live, with a conversation of the agent (spec 24), in a build
    /// with the Consegne.
    private var canDeliver: Bool {
        ReleaseArea.deliveries.isAvailable(hidesUnreleased: hidesUnreleased)
            && !isArchived && !session.conversations.isEmpty && session.workspace != nil
    }

    /// Whether the Sessione can have the Sandbox: this build has it, and the Sessione runs on Claude.
    private var hasSandbox: Bool {
        ReleaseArea.sandbox.isAvailable(hidesUnreleased: hidesUnreleased) && !isOnCopilot && !isClaudeMissing
    }
    /// Whether Bubo runs without `claude`: the parts only Claude has are hidden, also for a Sessione on Claude (#729).
    private var isClaudeMissing: Bool { questions?.isClaudeMissing == true }
    /// Whether the Sessione runs on Copilot, without the parts that exist only with Claude (ADR 0012).
    private var isOnCopilot: Bool { session.engine == .copilot }

    /// Whether the Sessione has changes git can show: in its own worktree, or on the checkout of a repo.
    private var canReview: Bool { !isArchived && (session.workspace?.branch != nil || session.isOnCheckout) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            details
                .confirmationDialog("Vuoi archiviare la Sessione «\(session.title)»?",
                                    isPresented: $isConfirmingArchive) {
                    Button("Archivia") { store.archive(session.id) }
                } message: {
                    Text(verbatim: archiveNotice)
                }
            // Dropped on the Sessione in the HUD: they go with its next turn.
            if !session.attachments.isEmpty, !isArchived {
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text("Allegati al prossimo turno")
                        .font(Typography.body(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                    AttachmentChips(attachments: session.attachments) { allegato in
                        store.detach(allegato, from: session.id)
                    }
                }
                .padding([.horizontal, .bottom], Spacing.xSmall)
            }
            // Outside the combined element, so each switch stays a control of its own.
            if !isArchived, session.allowsAutonomy {
                AutonomyToggle(isAutonomous: session.isAutonomous,
                               isSandboxed: store.sandbox.isEnabled(in: session.project),
                               offersSandbox: hasSandbox) { isOn in
                    store.setAutonomous(isOn, in: session.id)
                } setSandboxed: { isOn in
                    store.sandbox.setEnabled(isOn, in: session.project)
                }
                .padding([.horizontal, .bottom], Spacing.xSmall)
            }
            // Outside the combined element, so Correggi and Aggiorna PR stay buttons of their own.
            if session.phase == .inRevisione {
                PullRequestBadge(session: session, store: store)
                    .controlSize(.small)
                    .padding([.horizontal, .bottom], Spacing.xSmall)
            }
            // Outside the combined element, so Apri and Annulla stay buttons of their own.
            if !session.memoryLines.isEmpty, !isArchived {
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    ForEach(session.memoryLines.reversed()) { line in
                        MemoryLineRow(line: line, isInTurn: store.isInTurn(session.project)) {
                            try store.undo(line.id, in: session.id)
                        }
                    }
                }
                .padding([.horizontal, .bottom], Spacing.xSmall)
            }
            // Outside the combined element, so each option and answer stays a control of its own.
            // The keys go to it only when no Richiesta nor other Sessione's questions wait: one key never answers two.
            if let question = store.questions[session.id]?.first, !isArchived {
                AgentQuestionView(question: question,
                                  hasKeyboard: store.permissions.first == nil && store.questions.count == 1) { replies in
                    store.answer(question.id, in: session.id, with: replies)
                }
                .id(question.id)
                .padding([.horizontal, .bottom], Spacing.xSmall)
            }
            // Outside the combined element, so each answer stays a button of its own.
            if let queue = store.permissions.queues[session.id], let pending = queue.first, !isArchived {
                PermissionRequestView(pending: pending, project: session.project, queued: queue.count - 1,
                                      hasKeyboard: store.permissions.first?.id == pending.id) { answer in
                    store.answer(pending.id, in: session.id, with: answer)
                } allowInProject: {
                    try store.allowInProject(pending.id, in: session.id)
                } allowDomainInProject: {
                    store.allowDomainInProject(pending.id, in: session.id)
                }
                .padding([.horizontal, .bottom], Spacing.xSmall)
            }
            // Outside the combined element too, so each Consenti stays a button of its own.
            if let blocks = store.sandboxBlocks[session.id], !blocks.isEmpty, !isArchived {
                SandboxBlockList(blocks: blocks, project: session.project, sandbox: store.sandbox)
                    .padding([.horizontal, .bottom], Spacing.xSmall)
            }
            // Outside the combined element too, so each Consenti stays a button of its own.
            if let mark = session.automation, !isArchived, !session.denials.isEmpty || isAutonomyUnavailable {
                DenialReport(denials: session.denials, isAutonomyUnavailable: isAutonomyUnavailable,
                             rules: store.automations[mark.automation]?.rules) { denial in
                    for rule in denial.suggestions { store.automations.allow(rule, in: mark.automation) }
                }
                .padding([.horizontal, .bottom], Spacing.xSmall)
            }
        }
        // The regola "Sessione davanti": files and addresses dropped on an open Sessione are its Allegati.
        .dropDestination(for: URL.self) { urls, _ in
            drop(urls)
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: CornerRadius.medium).strokeBorder(Palette.lineStrong)
                    .allowsHitTesting(false)
            }
        }
        // Read again each time the Sessione changes Attività: the agent may have written the file.
        .task(id: session.terminalFolder == nil ? nil : session.activitySince) {
            launchServers = session.terminalFolder.map(LaunchConfig.read(in:)) ?? []
        }
        .sheet(isPresented: $isShowingConfiguration) {
            ConfigPanel(project: session.project, sandbox: store.sandbox, read: store.configuration(of:),
                        readSandboxRules: store.sandboxRules(of:)) { [project = session.project] server in
                try await store.logIn(toMCPServer: server, in: project)
            }
        }
        .sheet(isPresented: $isShowingMemory) {
            MemoryPanel(project: session.project,
                        isInTurn: store.isInTurn(session.project),
                        read: store.configuration(of:))
        }
        .sheet(isPresented: $isReviewing) {
            ReviewSheet(sessionID: session.id, store: store)
        }
        .confirmationDialog("Vuoi cancellare la Sessione «\(session.title)»?", isPresented: $isConfirmingDeletion) {
            Button("Cancella", role: .destructive) { store.delete(session.id) }
        } message: {
            Text(deletionMessage)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                Circle()
                    .fill(session.activity.color)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(Text(session.activity.title))
                Text(verbatim: session.title)
                    .font(Typography.body(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: Spacing.xSmall)
                if let since = session.activitySince {
                    ActivityWait(since: since, isWaitingForUser: session.activity == .attende && !isArchived)
                }
            }
            if let mark = session.automation {
                Text("Automazione · \(mark.name) · \(mark.startedAt.formatted(date: .omitted, time: .shortened))")
                    .font(Typography.mono(size: 10, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            if let summary = session.summary {
                Text(verbatim: summary)
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Text(verbatim: [session.issue?.label, session.pullRequest?.label, session.project.lastPathComponent,
                            session.isOnCheckout ? String(localized: "sul checkout") : session.workspace?.branch,
                            String(localized: session.phase.title)]
                .compactMap(\.self).joined(separator: " · "))
                .font(Typography.mono(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            // Always in sight: which engine and model the next turn runs on (ADR 0012). VoiceOver reads it as the value.
            Text(verbatim: session.choice.name)
                .font(Typography.mono(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .accessibilityHidden(true)
            // Without `claude` there is nothing to miss: the notice is only for who has both (#729).
            if !isArchived && isOnCopilot {
                if !isClaudeMissing {
                    CopilotUnavailableNotice()
                        .padding(.top, Spacing.xxSmall)
                }
            } else if !isArchived && hasSandbox {
                SandboxIndicator(state: SandboxState(isEnabled: store.sandbox.isEnabled(in: session.project),
                                                     currentTurn: store.sandboxedTurns[session.id])) {
                    isShowingConfiguration = true
                }
            }
            if !isOnBoard {
                SessionCostTotal(total: store.ledger.total(of: session.id),
                                 lastTurn: store.ledger.lastTurn(of: session.id)?.usage,
                                 copilotPricesOf: session.engine == .copilot ? CopilotPriceTable.bundled?.date : nil)
            } else if let lineCounts, lineCounts.added + lineCounts.removed > 0 {
                HStack(spacing: Spacing.xSmall) {
                    Text(verbatim: "+\(lineCounts.added)").foregroundStyle(Palette.success)
                    Text(verbatim: "−\(lineCounts.removed)").foregroundStyle(Palette.danger)
                }
                .font(Typography.mono(size: 11))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(lineCounts.added) righe aggiunte, \(lineCounts.removed) tolte"))
            }
            if !isArchived, let server = store.servers.servers[session.id]?.first {
                let isDrivenByAgent = store.previews.pages[session.id]?.isDrivenByAgent == true
                // The Anteprima opens only from here or with ⌘⇧P, never on its own.
                Button(action: openPreview) {
                    if isDrivenByAgent {
                        Text("L'agente usa l'anteprima")
                            .font(Typography.body(size: 11))
                            .foregroundStyle(Palette.textPrimary)
                    } else {
                        Text(verbatim: "localhost:\(String(server.port))")
                            .font(Typography.mono(size: 11))
                            .foregroundStyle(Palette.textPrimary)
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Server in ascolto su localhost:\(String(server.port))"))
                .accessibilityValue(isDrivenByAgent ? Text("L'agente usa l'anteprima") : Text(verbatim: ""))
                .help("Apre l'anteprima del server")
            } else if !isArchived, session.terminalFolder != nil, let server = launchServers.first {
                if launchServers.count == 1 {
                    Button("Avvia server") { launch(server) }
                        .controlSize(.small)
                        .help(Text(verbatim: server.commandLine ?? ""))
                } else {
                    Menu("Avvia server") {
                        ForEach(launchServers, id: \.name) { server in
                            Button(server.name) { launch(server) }
                        }
                    }
                    .fixedSize()
                    .controlSize(.small)
                }
            }
            if let state = store.pluginReloader.state(of: session.id) {
                PluginReloadButton(state: state) {
                    Task { await store.pluginReloader.reloadPlugins(in: session.id) }
                }
            }
            if store.footprints.heavySessions.contains(session.id) {
                HeavySessionBanner(restart: store.canRestartTurn(session.id) ? { store.restartTurn(session.id) } : nil)
            }
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
            if let scope = session.budgetStop, session.activity == .ferma, !isArchived {
                // On Claude a spent Budget means the API key, so the subscription is a way; Copilot has none (#542).
                BudgetStopNotice(scope: scope, detail: "La Sessione si è fermata: riparte solo con una tua scelta.",
                                 retry: { store.resumeAfterBudget(session.id) },
                                 continueOnce: { store.resumeAfterBudget(session.id, ignoringBudget: true) },
                                 switchToSubscription: session.engine == .copilot
                                     ? nil : { store.resumeWithSubscription(session.id) })
                    .controlSize(.small)
                    .padding(.top, Spacing.xxSmall)
            }
            if session.unstartedPrompt != nil && session.activity == .errore && !isArchived {
                Button("Riprova") { store.retry(session.id) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, Spacing.xxSmall)
            }
            if session.isInterrupted && session.activity == .ferma && session.prompt != nil {
                Button("Riprendi") { store.resume(session.id) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, Spacing.xxSmall)
            }
            if let summarizer, let notice = summarizer.notices[session.id] {
                SummaryNoticeRow(notice: notice, summarizer: summarizer)
                    .padding(.top, Spacing.xxSmall)
            }
            if let deliveries, let notice = deliveries.deliveredNotices[session.id] {
                DeliveredNoticeRow(notice: notice) { deliveries.dismissDeliveryNotice(of: session.id) }
                    .padding(.top, Spacing.xxSmall)
            }
        }
        .padding(Spacing.xSmall)
        .opacity(isArchived ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: session.choice.name))
        .task(id: session.engine) {
            if session.engine == .copilot { await store.loadCopilotModels() }
        }
        // Read again each time the Sessione changes Attività: a turn that ends has new lines.
        .task(id: isOnBoard && canReview ? session.activitySince : nil) {
            guard isOnBoard, canReview else { return }
            lineCounts = await store.lineCounts(of: session.id)
        }
        .contextMenu {
            if canReview { Button("Rivedi le modifiche…") { isReviewing = true } }
            if session.terminalFolder != nil { Button("Apri il terminale", action: openTerminal) }
            if !isArchived, let showInGalaxy = hud.showInGalaxy {
                Button("Mostra nella Galassia") { showInGalaxy(session) }
            }
            if !isArchived {
                SessionModelMenu(choice: session.choice, copilotModels: store.copilotModels) {
                    store.setChoice($0, in: session.id)
                }
            }
            if canDeliver {
                Button("Consegna…") { hud.deliver(session) }
                    .disabled(session.activity == .lavora)
            }
            // Both are read by `claude`: a Sessione on Copilot never calls it (ADR 0012).
            if !isOnCopilot && !isClaudeMissing {
                Button("Configurazione di Claude…") { isShowingConfiguration = true }
                Button("Memoria del Progetto…") { isShowingMemory = true }
            }
            if summarizer != nil {
                Button("Riassumi ora", action: summarize)
                    .disabled(session.isRunning)
            }
            if !isArchived {
                Button("Archivia", action: archive)
                    .disabled(session.isRunning)
            }
            Button("Cancella…", role: .destructive, action: confirmDeletion)
                .disabled(session.isRunning)
        }
        .accessibilityActions {
            if store.footprints.heavySessions.contains(session.id) && store.canRestartTurn(session.id) {
                Button("Riavvia") { store.restartTurn(session.id) }
            }
            if canReview { Button("Rivedi le modifiche…") { isReviewing = true } }
            if session.terminalFolder != nil { Button("Apri il terminale", action: openTerminal) }
            if !isArchived, let showInGalaxy = hud.showInGalaxy {
                Button("Mostra nella Galassia") { showInGalaxy(session) }
            }
            if canDeliver && session.activity != .lavora { Button("Consegna…") { hud.deliver(session) } }
            // Both are read by `claude`: a Sessione on Copilot never calls it (ADR 0012).
            if !isOnCopilot && !isClaudeMissing {
                Button("Configurazione di Claude…") { isShowingConfiguration = true }
                Button("Memoria del Progetto…") { isShowingMemory = true }
            }
            if !session.isRunning {
                if summarizer != nil { Button("Riassumi ora", action: summarize) }
                if !isArchived { Button("Archivia", action: archive) }
                Button("Cancella…", action: confirmDeletion)
            }
        }
    }

    /// Riassumi ora: the Riassunto di Sessione in the Secondo cervello, whatever the Fase.
    private func summarize() {
        guard let summarizer else { return }
        Task { await summarizer.summarize(session.id) }
    }

    /// Archivia, after a confirmation when something runs in the Sessione's terminal.
    private func archive() {
        if let notice = store.terminalNotice(of: session.id) {
            archiveNotice = notice
            isConfirmingArchive = true
        } else {
            store.archive(session.id)
        }
    }

    /// Avvia server: the command of `server` in a new scheda of the Sessione's terminal.
    private func launch(_ server: LaunchConfig) {
        store.terminals.launch(server, in: session)
        if !store.terminals.isDetached { hud.show() }
    }

    private func openPreview() {
        store.showPreview(of: session)
        if !store.previews.isDetached { hud.show() }
    }

    private func openTerminal() {
        store.terminals.show(session)
        if !store.terminals.isDetached { hud.show() }
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

extension Session.Activity {
    /// The dot of a Sessione: Lume only for Attende te, danger for Errore, faint once it stops.
    var color: Color {
        switch self {
        case .attende: Palette.attention
        case .errore: Palette.danger
        case .lavora: Palette.textPrimary
        case .ferma: Palette.textFaint
        }
    }
}
