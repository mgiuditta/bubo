import SwiftUI

/// The main window: the Orb at the centre of the HUD rings, with the Sessioni laid out in the current Vista.
struct HUDView: View {
    @Environment(HUDPresenter.self) private var hud
    @Environment(DeliveriesController.self) private var deliveries
    @Environment(\.openWindow) private var openWindow
    /// The Domanda under the Orb.
    let questions: QuestionModel
    /// The Sessioni; `nil` when they cannot be kept.
    let sessions: SessionStore?
    /// The first launch, until the first answer in a Sessione.
    let onboarding: OnboardingFlow
    /// What starts once the HUD is interactive.
    let launch: LaunchSequence
    /// The Riunioni, recorded from the right column.
    let meetings: MeetingRecorder
    /// The Neuroni of the current Secondo cervello; `nil` without one.
    let neurons: () -> NeuronModel?
    /// The height of the first launch's scroll view: its content is at least as tall, to stay centred.
    @State private var onboardingHeight: CGFloat = 0

    var body: some View {
        @Bindable var hud = hud
        NavigationSplitView {
            MainSidebar(selection: $hud.selection, questions: questions, sessions: sessions)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            detail(for: hud.selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Behind the right column only: under the whole split view it shows around the sidebar's glass as a
                // second edge.
                .background { HUDBackground() }
        }
        .frame(minWidth: 900, minHeight: 560)
        .onChange(of: hud.selection) { previous, selection in
            // Back home from an older Domanda: the home asks a new one, it does not continue the hidden one.
            if selection == .brain, case let .conversation(id) = previous, id.hasPrefix("q-"), !questions.isAnswering {
                questions.startNewQuestion()
            }
        }
        .background {
            Color.clear
                // Here, not next to the other sheets: one sheet modifier per view.
                // Not while the foglio di Consegna is up: that one shows a Biglietto added from it.
                .sheet(item: hud.deliverySession == nil ? Bindable(deliveries).pendingImport : .constant(nil)) { pending in
                    TicketImportSheet(pending: pending, deliveries: deliveries)
                }
            // A Consegna opened: "Consegna ricevuta", or "Non si apre".
            Color.clear
                .sheet(item: Bindable(deliveries).receipt) { receipt in
                    switch receipt.state {
                    case let .received(opened):
                        if let sessions {
                            DeliveryReceivedSheet(opened: opened, deliveries: deliveries, store: sessions)
                        }
                    case let .failed(failure):
                        DeliveryErrorSheet(failure: failure, machine: deliveries.machine) {
                            deliveries.dismissReceipt()
                        }
                    }
                }
            // The sheets below open from the Board, a Sessione's card, the menus and the Palette: on the whole window,
            // so they show whatever the sidebar has selected.
            Color.clear
                .sheet(item: $hud.pullRequestSession) { session in
                    if let sessions { PullRequestSheet(session: session, store: sessions) }
                }
            Color.clear
                .sheet(item: $hud.deliverySession) { session in
                    DeliverySheet(flow: .live(for: session, deliveries: deliveries))
                }
            Color.clear
                .sheet(isPresented: $hud.isPickingIssue) {
                    if let sessions { IssuePicker(store: sessions) }
                }
            Color.clear
                .sheet(isPresented: $hud.isCreatingDraft) {
                    if let sessions { NewDraftSheet(store: sessions) }
                }
        }
        // A drop with no Sessione in front: recordings and trascrizioni become Riunioni, the rest a new Domanda with the
        // Allegati (regola "Sessione davanti").
        .dropDestination(for: URL.self) { urls, _ in
            if MeetingImportFile.isMeetingDrop(urls) {
                hud.importMeetings(urls)
                return true
            }
            let attachments = HUDDropDestination.attachments(from: urls)
            questions.attach(attachments)
            return !attachments.isEmpty
        }
        .foregroundStyle(Palette.textPrimary)
        .sheet(isPresented: $hud.isCreatingSession) {
            if let sessions { NewSessionSheet(store: sessions, draft: hud.sessionDraft) }
        }
        .onAppear { hud.openWindow = openWindow }
        // Runs after the first appearance, once the main thread is free again: launch is over.
        .task {
            let launching = launch.start()
            guard !onboarding.isCompleted else { return }
            async let recents = Self.recentProjects()
            // The sequence finds `claude` during onboarding, after the bridge.
            await launching.value
            onboarding.show(await recents)
        }
        // Each time `claude` needs a remedy: during the onboarding, or when a Sessione finds it too old (spec 27).
        .task(id: onboarding.needsRemedy) { await watchClaude() }
        // Back from the Terminal: the login there leaves no other trace Bubo is allowed to read.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await onboarding.recheck() }
        }
        // Signed in from a remedy: the login rewrites `~/.claude.json`, and the first question asks again.
        .task(id: onboarding.isAwaitingSignIn) {
            guard onboarding.isAwaitingSignIn else { return }
            for await _ in InstallWatcher().changes() {
                await onboarding.recheck()
                if !onboarding.isAwaitingSignIn { return }
            }
        }
        // Last, so the sheets above get it too: selection is lightness, not the system blue (design system).
        .tint(Palette.accent)
        // Only dark, sheets included, whatever the system's appearance (design system, ADR 0004).
        .preferredColorScheme(.dark)
    }

    /// The Orb of the home, with the Dedica or the forecast under it.
    private var orb: some View {
        HUDOrb()
            .overlay(alignment: .bottom) {
                if OrbControls.shared.isShowingDedica {
                    Text(Dedica.message)
                        .font(Typography.body(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                } else if let forecast = questions.intake.forecast {
                    OrbCaption(forecast: forecast)
                }
            }
    }

    /// Whether the HUD shows the first launch in place of the Domanda: until the first Sessione starts.
    private var showsOnboarding: Bool {
        !onboarding.isCompleted && sessions?.sessions.isEmpty == true
    }

    /// Checks `claude` again at each installation or login seen by FSEvents, until it is ready.
    private func watchClaude() async {
        guard onboarding.needsRemedy else { return }
        for await _ in InstallWatcher().changes() {
            await onboarding.recheck()
            if !onboarding.needsRemedy { return }
        }
    }

    /// The recent Progetti, read off the main thread.
    @concurrent nonisolated private static func recentProjects() async -> [RecentProject] {
        RecentProjects.load()
    }

    /// What the right column shows for `selection`.
    @ViewBuilder
    private func detail(for selection: SidebarSelection) -> some View {
        switch selection {
        case .brain:
            main.padding(.horizontal, Spacing.l)
        case .neurons:
            if let model = neurons() {
                NeuronView(model: model, questions: questions)
                    // A new Secondo cervello is a new map, not the old one's state.
                    .id(ObjectIdentifier(model))
            } else {
                ContentUnavailableView("Nessun Secondo cervello", systemImage: "point.3.connected.trianglepath.dotted",
                                       description: Text("Scegli la cartella delle tue note nelle Impostazioni, poi apri i Neuroni."))
            }
        case .meetings:
            MeetingView(recorder: meetings)
        case .conversation(let id):
            ConversationDetail(id: id, questions: questions, sessions: sessions)
        case .project(let project):
            if let sessions {
                ProjectSessions(project: project, store: sessions, selection: Bindable(hud).selection)
            }
        case .work:
            if let sessions {
                SessionBoard(store: sessions)
                    .padding(Spacing.l)
            }
        }
    }

    /// What still stands between the user and an answer, over the Domanda: the remedy for `claude`, the first
    /// Richiesta di permesso.
    @ViewBuilder
    private var remedies: some View {
        // The first Sessione did not answer, or a Sessione found `claude` too old: the remedy stays until
        // the first token, or until `claude` is ready.
        if (onboarding.problem != nil && !onboarding.isCompleted) || onboarding.needsRemedy {
            FixCard(flow: onboarding, holdsSessions: sessions?.awaitingClaudeUpdate.isEmpty == false)
                .padding(.bottom, Spacing.small)
        }
        // The first Richiesta di permesso of the onboarding is answered here, not only in its Sessione.
        if let sessions, let id = onboarding.sessionAwaitingFirstPermission,
           let session = sessions.sessions.first(where: { $0.id == id }),
           let pending = sessions.permissions.queues[id]?.first {
            FirstPermissionCard(flow: onboarding, store: sessions, session: session, pending: pending)
                .id(pending.id)
                .padding(.bottom, Spacing.small)
        }
    }

    /// The Motore principale of the onboarding, as Bubo found it.
    @ViewBuilder
    private var enginePill: some View {
        switch onboarding.primaryEngine {
        case .claude:
            if let readiness = onboarding.readiness { EnginePill(claude: readiness) }
        case .copilot:
            if let readiness = onboarding.copilotReadiness { EnginePill(copilot: readiness) }
        }
    }

    private var main: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                HUDHeader()
                if !onboarding.isCompleted && onboarding.isEngineChosen { enginePill }
                // Without `claude` there is no Quota: the Spesa of Copilot in its place (#729).
                if questions.isClaudeMissing, let spent = questions.copilotSpesa {
                    CopilotSpendView(spent: spent) { hud.showCosts?() }
                } else {
                    QuotaView(quota: questions.quota) { hud.showCosts?() }
                }
            }
            // The Risorse di squadra to look at, or that cannot be read, of each Progetto with Sessioni.
            if let sessions {
                ForEach(sessions.projects, id: \.self) { project in
                    TeamResourcesNotice(project: project)
                }
            }
            if !showsOnboarding && questions.hasConversation {
                // A Domanda under way is a chat, with the Orb over it, as every Conversazione (ADR 0013).
                remedies
                QuestionDetail(question: nil, model: questions)
            } else if showsOnboarding {
                // A short window scrolls the first launch, so the buttons under the steps stay reachable; a tall one
                // keeps it centred.
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: Spacing.large)
                        // Smaller during the first launch: the steps, the Progetti and the input bar come under it.
                        orb
                            .frame(width: 200, height: 200)
                            .padding(Spacing.small)
                        OnboardingStage(flow: onboarding)
                        Spacer(minLength: Spacing.large)
                    }
                    .frame(maxWidth: .infinity, minHeight: onboardingHeight)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { onboardingHeight = $0 }
            } else {
                Spacer(minLength: Spacing.large)
                orb
                    .frame(maxWidth: 360, maxHeight: 360)
                    .padding(Spacing.l)
                // The empty home invites to ask the Secondo cervello (ADR 0013).
                if questions.turns.isEmpty && questions.answer.isEmpty {
                    HomeHeader(questions: questions)
                        .padding(.bottom, Spacing.m)
                }
                remedies
                QuestionView(model: questions)
                    .frame(maxWidth: 560)
                    // Apart from the Sessione's card above: the prompt is the Domanda's, not the Sessione's.
                    .padding(.top, Spacing.medium)
                Spacer(minLength: Spacing.large)
            }
            if let sessions {
                PanelRow(terminals: sessions.terminals, previews: sessions.previews)
            }
        }
        .padding(.vertical, Spacing.medium)
        // The empty home becomes a chat at the first prompt, and back at «Nuova Domanda»: a fade, not a jump.
        .animation(Motion.standard, value: questions.hasConversation)
    }
}

#Preview {
    HUDView(questions: QuestionModel(), sessions: nil, onboarding: OnboardingFlow(hasSessions: true) { _, _ in UUID() },
            launch: LaunchSequence(startBridge: {}, isOnboarding: { false }, detectEngines: {}, keepIndexFresh: {},
                                   subscribeToMetrics: {}, startConfigurationSpare: {}, keepCLIHistoryFresh: {}),
            meetings: MeetingRecorder(secondBrain: SecondBrain(index: nil), engines: [], store: nil), neurons: { nil })
        .environment(HUDPresenter())
        .environment(DeliveriesController.live())
}
