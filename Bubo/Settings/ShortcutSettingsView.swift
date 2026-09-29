import SwiftUI

/// The global shortcut that shows and hides the HUD.
struct ShortcutSettingsView: View {
    @Environment(HotKeyCenter.self) private var hotKeys

    var body: some View {
        Form {
            LabeledContent("Mostra e nascondi Bubo") {
                ShortcutRecorder(shortcut: hotKeys.shortcut) { hotKeys.change(to: $0) }
            }
            if let problem = hotKeys.problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }
}
