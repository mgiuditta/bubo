import SwiftUI

/// The first Richiesta di permesso of the first Sessione, at the centre of the HUD under a line on what the answers do.
/// Once answered, the next Richieste stay in their Sessione.
struct FirstPermissionCard: View {
    let flow: OnboardingFlow
    let store: SessionStore
    let session: Session
    let pending: RequestCenter.Pending

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            // Levels 4–5 offer only No and the held Solo ora.
            Group {
                if pending.needsHold {
                    Text("Azione rischiosa. Tieni premuto «Solo ora» per consentirla, «No» per bloccarla.")
                } else {
                    Text("Claude chiede il permesso prima di agire. «Solo ora» vale per questa azione, «Per questa Sessione» fino alla sua fine, «Sempre in questo Progetto» salva una regola. Con «No» Claude cerca un'altra strada.")
                }
            }
                .font(Typography.body(size: 13))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.permissionExplanation")
            PermissionRequestView(pending: pending, project: session.project,
                                  queued: (store.permissions.queues[session.id]?.count ?? 1) - 1,
                                  hasKeyboard: store.permissions.first?.id == pending.id) { answer in
                store.answer(pending.id, in: session.id, with: answer)
                flow.answerFirstPermission()
            } allowInProject: {
                try store.allowInProject(pending.id, in: session.id)
                flow.answerFirstPermission()
            } allowDomainInProject: {
                store.allowDomainInProject(pending.id, in: session.id)
                flow.answerFirstPermission()
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        // VoiceOver hears it even though the focus stays where it was.
        .onAppear {
            AccessibilityNotification.Announcement(String(localized: "Claude chiede il permesso per: \(pending.request.title ?? pending.request.tool)")).post()
        }
    }
}
