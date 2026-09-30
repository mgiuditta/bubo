import SwiftUI

/// The main window: the Orb at the centre of the HUD rings.
struct HUDView: View {
    @Environment(HUDPresenter.self) private var hud
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            HUDHeader()
            Spacer(minLength: Spacing.large)
            OrbPlaceholder()
                .frame(maxWidth: 520, maxHeight: 520)
                .padding(Spacing.large)
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
    }
}

#Preview {
    HUDView()
        .environment(HUDPresenter())
}
