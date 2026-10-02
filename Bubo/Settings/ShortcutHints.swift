import SwiftUI

/// What the recorder says under Bubo's shortcut (spec 08): the sola dettatura, and what else answers the combination.
struct ShortcutHints: View {
    let hotKeys: HotKeyCenter
    @State private var report = ShortcutConflicts.Report()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            if let dictation = hotKeys.dictationShortcut {
                Text("Tieni premuto \(dictation.displayName) per dettare nel prompt senza inviare.")
            } else if hotKeys.shortcut.dictationVariant == nil {
                Text("La combinazione contiene già ⇧: la sola dettatura è spenta.")
            }
            ForEach(report.systemShortcuts, id: \.self) { shortcut in
                Text("\(shortcut.displayName) è anche una scorciatoia di sistema: cambiala qui o in Impostazioni di Sistema › Tastiera.")
                    .foregroundStyle(Palette.textPrimary)
            }
            if !report.apps.isEmpty {
                Text("\(hotKeys.shortcut.displayName) aprirà anche \(report.apps.formatted(.list(type: .and))): cambiala qui o nell'altra app.")
                    .foregroundStyle(Palette.textPrimary)
            }
        }
        .foregroundStyle(Palette.textSecondary)
        .task(id: [hotKeys.shortcut, hotKeys.dictationShortcut]) {
            report = ShortcutConflicts.report(for: [hotKeys.shortcut] + [hotKeys.dictationShortcut].compactMap(\.self))
        }
    }
}
