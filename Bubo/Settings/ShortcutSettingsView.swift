import SwiftUI

/// The global shortcut that shows and hides the HUD, held down dictates, and plus ⇧ only dictates (spec 08); and the one
/// of «Chiedi nel Panel» (#635); and the one of «Allega finestra» (#485).
struct ShortcutSettingsView: View {
    @Environment(HotKeyCenter.self) private var hotKeys

    var body: some View {
        Form {
            LabeledContent("Mostra Bubo · tieni premuto per parlare") {
                ShortcutRecorder(shortcut: hotKeys.shortcut) { hotKeys.change(to: $0) }
            }
            LabeledContent("Chiedi nel Panel") {
                ShortcutRecorder(shortcut: hotKeys.askShortcut) { hotKeys.changeAsk(to: $0) }
            }
            LabeledContent("Allega finestra") {
                ShortcutRecorder(shortcut: hotKeys.attachWindowShortcut) { hotKeys.changeAttachWindow(to: $0) }
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
