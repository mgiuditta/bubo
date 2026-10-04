import SwiftUI

/// A Regola di permesso in Impostazioni › Permessi: the rule, the file it comes from, its Livello di rischio, and
/// Togli… when Bubo wrote it.
struct RuleListingRow: View {
    let item: RuleListing.Item
    /// Asks to confirm the removal.
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(verbatim: RepoActivations.escaped(item.rule))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                // Danger is the icon's color, never the text's: red callout text falls short of 4.5:1. The level's
                // title already says it in words.
                HStack(spacing: Spacing.xxSmall) {
                    if item.level.isDangerous {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.danger)
                            .accessibilityHidden(true)
                    }
                    Text("\(Self.origin(of: item.origin)) · Livello \(item.level.rawValue) · \(Text(item.level.title))")
                        .foregroundStyle(Color.secondary)
                }
                .font(.callout)
            }
            Spacer()
            if item.isRemovable {
                Button("Togli…", action: remove)
            }
        }
    }

    /// The file or the place the rule comes from; file paths are never translated.
    private static func origin(of origin: RuleListing.Origin) -> Text {
        switch origin {
        case .userSettings: Text(verbatim: "~/.claude/settings.json")
        case .localSettings: Text(verbatim: ".claude/settings.local.json")
        case .sharedSettings: Text(".claude/settings.json, nel repo")
        case .automation: Text("Solo in questa Automazione")
        }
    }
}
