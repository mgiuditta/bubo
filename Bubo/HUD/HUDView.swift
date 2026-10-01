import SwiftUI

/// The main window: the Orb at the centre of the HUD rings.
struct HUDView: View {
    @Environment(HUDPresenter.self) private var hud
    @Environment(\.openWindow) private var openWindow
    /// The Domanda under the Orb.
    let questions: QuestionModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                HUDHeader()
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
        .padding(.horizontal, Spacing.large)
        .padding(.vertical, Spacing.medium)
        .frame(minWidth: 720, minHeight: 560)
        .background { HUDBackground() }
        .foregroundStyle(Palette.textPrimary)
        .onAppear { hud.openWindow = openWindow }
        // Runs after the first appearance, once the main thread is free again.
        .task { Signposts.markHUDInteractive() }
        // Without a Domanda the Quota comes from the SDK's usage method, when the HUD appears.
        .task { await questions.refreshQuota() }
    }
}

#Preview {
    HUDView(questions: QuestionModel())
        .environment(HUDPresenter())
}
