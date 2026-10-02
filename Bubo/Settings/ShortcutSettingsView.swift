import SwiftUI

/// The global shortcut that shows and hides the HUD, held down dictates, and plus ⇧ only dictates (spec 08).
struct ShortcutSettingsView: View {
    @Environment(HotKeyCenter.self) private var hotKeys

    var body: some View {
        Form {
            LabeledContent("Mostra e nascondi Bubo") {
                ShortcutRecorder(shortcut: hotKeys.shortcut) { hotKeys.change(to: $0) }
            }
            ShortcutHints(hotKeys: hotKeys)
                .font(.callout)
            if let problem = hotKeys.problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(Palette.danger)
            }
        }
        .formStyle(.grouped)
    }
}
