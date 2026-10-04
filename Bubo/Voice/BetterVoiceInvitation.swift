import SwiftUI

/// The line under the prompt after Bubo spoke with a basic-quality voice: the app cannot download a better one, so it
/// says where the user can.
struct BetterVoiceInvitation: View {
    /// Hides the line for good.
    let dismiss: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Image(systemName: "speaker.wave.2")
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text("Bubo parla con una voce di base")
                    .font(Typography.body(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("Per una voce più naturale scaricane una migliorata in Impostazioni di Sistema › Accessibilità › Lettura e voce › Voce di sistema.")
                    .font(Typography.body(size: 13))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: Spacing.small)
            Button("Apri Impostazioni") { openURL(Self.accessibilitySettingsURL) }
            Button("Chiudi", action: dismiss)
        }
        .padding(Spacing.small)
        .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.large).strokeBorder(Palette.line)
        }
        .accessibilityElement(children: .contain)
    }

    private static let accessibilitySettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension")!
}
