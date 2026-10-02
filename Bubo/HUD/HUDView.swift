import SwiftUI

/// The main window: the Orb at the centre of the HUD rings, with the Sessioni laid out in the current Vista.
struct HUDView: View {
    @Environment(HUDPresenter.self) private var hud
    @Environment(\.openWindow) private var openWindow
    /// The Vista chosen in Aspetto: choosing another there switches the HUD to it.
    @AppStorage(VistaDelleSessioni.defaultsKey) private var chosenVista = VistaDelleSessioni.colonna
    /// The Domanda under the Orb.
    let questions: QuestionModel
    /// The Sessioni; `nil` when they cannot be kept.
    let sessions: SessionStore?
    /// The first launch, until the first answer in a Sessione.
    let onboarding: OnboardingFlow
    /// What starts once the HUD is interactive.
    let launch: LaunchSequence

    var body: some View {
        @Bindable var hud = hud
        HStack(alignment: .top, spacing: Spacing.large) {
            if hud.vista == .colonna, let sessions = visibleSessions {
                SessionColumn(store: sessions)
                    .padding(.vertical, Spacing.medium)
            }
            main
        }
        .padding(.horizontal, Spacing.large)
        .frame(minWidth: 720, minHeight: 560)
        .background { HUDBackground() }
        .foregroundStyle(Palette.textPrimary)
        .sheet(isPresented: $hud.isCreatingSession) {
            if let sessions { NewSessionSheet(store: sessions, draft: hud.sessionDraft) }
        }
        .onAppear { hud.openWindow = openWindow }
        .onChange(of: chosenVista) { hud.switchVista(to: chosenVista) }
        // The new Vista's body has been laid out.
        .onChange(of: hud.vista) { hud.endVistaSwitch() }
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

    /// The Sessioni to lay out, when there is at least one.
    private var visibleSessions: SessionStore? {
        guard let sessions, !sessions.sessions.isEmpty else { return nil }
        return sessions
    }

    private var main: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                HUDHeader()
                    // Here, not next to the other sheets: one sheet modifier per view.
                    .sheet(item: Bindable(hud).pullRequestSession) { session in
                        if let sessions { PullRequestSheet(session: session, store: sessions) }
                    }
                if let readiness = onboarding.readiness, !onboarding.isCompleted { ClaudePill(readiness: readiness) }
                QuotaView(quota: questions.quota) { hud.showCosts?() }
            }
            // Here, not next to the other sheets: one sheet modifier per view.
            .sheet(isPresented: Bindable(hud).isPickingIssue) {
                if let sessions { IssuePicker(store: sessions) }
            }
            // The Risorse di squadra to look at, or that cannot be read, of each Progetto with Sessioni.
            if let sessions {
                ForEach(sessions.projects, id: \.self) { project in
                    TeamResourcesNotice(project: project)
                }
            }
            Spacer(minLength: Spacing.large)
            if hud.vista == .orbita, let sessions = visibleSessions {
                SessionOrbit(store: sessions, quota: questions.quota)
            } else if hud.vista == .board, let sessions, !sessions.sessions.isEmpty || !sessions.drafts.drafts.isEmpty {
                SessionBoard(store: sessions)
                    .padding(.bottom, Spacing.small)
            } else {
                HUDOrb()
                    .frame(maxWidth: 520, maxHeight: 520)
                    .padding(Spacing.large)
                    .overlay(alignment: .bottom) {
                        if let forecast = questions.intake.forecast { OrbCaption(forecast: forecast) }
                    }
            }
            if hud.vista == .striscia, let sessions = visibleSessions {
                SessionStrip(store: sessions)
                    .padding(.bottom, Spacing.small)
            }
            if showsOnboarding {
                OnboardingStage(flow: onboarding)
            } else {
                // The first Sessione did not answer, or a Sessione found `claude` too old: the remedy stays until
                // the first token, or until `claude` is ready.
                if (onboarding.problem != nil && !onboarding.isCompleted) || onboarding.needsRemedy {
                    FixCard(flow: onboarding, holdsSessions: sessions?.awaitingClaudeUpdate.isEmpty == false)
                        .padding(.bottom, Spacing.small)
                }
                QuestionView(model: questions)
                    .frame(maxWidth: 560)
            }
            Spacer(minLength: Spacing.large)
            if let sessions {
                PanelRow(terminals: sessions.terminals, previews: sessions.previews)
            }
        }
        .padding(.vertical, Spacing.medium)
        // Here, not next to the new Sessione's: one sheet modifier per view.
        .sheet(isPresented: Bindable(hud).isCreatingDraft) {
            if let sessions { NewDraftSheet(store: sessions) }
        }
    }
}

#Preview {
    HUDView(questions: QuestionModel(), sessions: nil, onboarding: OnboardingFlow(hasSessions: true) { _, _ in UUID() },
            launch: LaunchSequence(startBridge: {}, isOnboarding: { false }, detectClaude: {}, keepIndexFresh: {},
                                   subscribeToMetrics: {}, startConfigurationSpare: {}, keepCLIHistoryFresh: {}))
        .environment(HUDPresenter())
}
