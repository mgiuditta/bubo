import SwiftUI

/// An open issue in ⌘I: number, title, labels, when it changed, and the Sessione it already has on the Progetto.
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
            if let session = matchedSession {
                Text(matchNote(for: session))
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

    private var matchedSession: Session? {
        switch match {
        case .none: nil
        case let .open(session), let .closed(session): session
        }
    }

    private func matchNote(for session: Session) -> LocalizedStringResource {
        if case .open = match { return "Già in una Sessione: ↩ la apre" }
        return session.phase == .fusa ? "Ha una Sessione fusa" : "Ha una Sessione archiviata"
    }
}
