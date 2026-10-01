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
    /// The `claude` found during onboarding; `nil` while detecting, or with no onboarding.
    @State private var readiness: ClaudeReadiness?

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
        // Runs after the first appearance, once the main thread is free again.
        .task {
            Signposts.markHUDInteractive()
            guard isOnboarding else { return }
            readiness = await Signposts.measure(.claudeDetection) { await ClaudeReadiness.detect() }
        }
        // Without a Domanda the Quota comes from the SDK's usage method, when the HUD appears.
        .task { await questions.refreshQuota() }
    }

    /// Onboarding lasts until there is a Sessione; after it, no `claude` starts at launch (spec 26).
    // ponytail: until OnboardingFlow (#202) keeps the onboarding's own mark.
    private var isOnboarding: Bool {
        sessions?.sessions.isEmpty ?? true
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
                if let readiness, isOnboarding { ClaudePill(readiness: readiness) }
                QuotaView(quota: questions.quota)
            }
            Spacer(minLength: Spacing.large)
            if hud.vista == .orbita, let sessions = visibleSessions {
                SessionOrbit(store: sessions, quota: questions.quota)
            } else if hud.vista == .board, let sessions = visibleSessions {
                SessionBoard(store: sessions)
                    .padding(.bottom, Spacing.small)
            } else {
                OrbPlaceholder()
                    .frame(maxWidth: 520, maxHeight: 520)
                    .padding(Spacing.large)
            }
            if hud.vista == .striscia, let sessions = visibleSessions {
                SessionStrip(store: sessions)
                    .padding(.bottom, Spacing.small)
            }
            QuestionView(model: questions)
                .frame(maxWidth: 560)
            Spacer(minLength: Spacing.large)
        }
        .padding(.vertical, Spacing.medium)
    }
}

#Preview {
    HUDView(questions: QuestionModel(), sessions: nil)
        .environment(HUDPresenter())
}
