import SwiftUI

/// The main window: the Orb at the centre of the HUD rings.
struct HUDView: View {
    @Environment(HUDPresenter.self) private var hud
    @Environment(\.openWindow) private var openWindow
    /// The Domanda under the Orb.
    let questions: QuestionModel
    /// The Sessioni of the Colonna; `nil` when they cannot be kept.
    let sessions: SessionStore?
    /// The `claude` found during onboarding; `nil` while detecting, or with no onboarding.
    @State private var readiness: ClaudeReadiness?

    var body: some View {
        @Bindable var hud = hud
        HStack(alignment: .top, spacing: Spacing.large) {
            if let sessions, !sessions.sessions.isEmpty {
                SessionColumn(sessions: sessions.sessions)
                    .padding(.vertical, Spacing.medium)
            }
            main
        }
        .padding(.horizontal, Spacing.large)
        .frame(minWidth: 720, minHeight: 560)
        .background { HUDBackground() }
        .foregroundStyle(Palette.textPrimary)
        .sheet(isPresented: $hud.isCreatingSession) {
            if let sessions { NewSessionSheet(store: sessions) }
        }
        .onAppear { hud.openWindow = openWindow }
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

    private var main: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                HUDHeader()
                if let readiness, isOnboarding { ClaudePill(readiness: readiness) }
                QuotaView(quota: questions.quota)
            }
            Spacer(minLength: Spacing.large)
            OrbPlaceholder()
                .frame(maxWidth: 520, maxHeight: 520)
                .padding(Spacing.large)
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
