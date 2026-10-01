import SwiftUI

/// An open issue in ⌘I: number, title, labels, when it changed, and the Bozza or Sessione it already has on the
/// Progetto.
struct IssueRow: View {
    let issue: GitHubIssue
    let match: IssueLink.Match

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                Text(verbatim: "#\(issue.number)")
                    .font(Typography.mono(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                Text(verbatim: issue.title)
                    .lineLimit(2)
                Spacer(minLength: Spacing.xSmall)
                Text(issue.updatedAt, format: .relative(presentation: .named))
                    .font(Typography.mono(size: 10))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            if let matchNote {
                Text(matchNote)
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            if !issue.labels.isEmpty {
                Text(verbatim: issue.labels.map(\.name).joined(separator: " · "))
                    .font(Typography.mono(size: 10))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, Spacing.xxSmall)
        .accessibilityElement(children: .combine)
    }

    private var matchNote: LocalizedStringResource? {
        switch match {
        // Statements, not a switch expression: the String Catalog takes only the first branch of one.
        case .none: return nil
        case .draft: return LocalizedStringResource("Già in una Bozza: ↩ la apre")
        case .open: return LocalizedStringResource("Già in una Sessione: ↩ la apre")
        case let .closed(session):
            if session.phase == .fusa { return LocalizedStringResource("Ha una Sessione fusa") }
            return LocalizedStringResource("Ha una Sessione archiviata")
        }
    }
}
