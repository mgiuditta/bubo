import SwiftUI

/// The "Scorciatoia" step of the first launch (spec 08): it appears only when something else answers Bubo's shortcut,
/// with the recorder to change it there, and stays until the onboarding ends.
struct ShortcutStep: View {
    let hotKeys: HotKeyCenter
    /// Whether something answered the shortcut when the onboarding appeared.
    @State private var isShown = false

    var body: some View {
        if isShown {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                LabeledContent("Scorciatoia di Bubo") {
                    ShortcutRecorder(shortcut: hotKeys.shortcut) { hotKeys.change(to: $0) }
                }
                .foregroundStyle(Palette.textPrimary)
                ShortcutHints(hotKeys: hotKeys)
                if let problem = hotKeys.problem {
                    Text(problem)
                        .foregroundStyle(Palette.danger)
                }
            }
            .font(Typography.body(size: 13))
            .padding(Spacing.small)
            .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
            .frame(maxWidth: 560, alignment: .leading)
        } else {
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .task {
                    let shortcuts = [hotKeys.shortcut] + [hotKeys.dictationShortcut].compactMap(\.self)
                    isShown = !ShortcutConflicts.report(for: shortcuts).isEmpty
                }
        }
    }
}
