import SwiftUI

/// The Colonna Vista of the HUD: one row per Sessione, newest first.
// ponytail: minimal Colonna; grouping by Attività, waits and summaries come with #75.
struct SessionColumn: View {
    let sessions: [Session]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xSmall) {
                ForEach(sessions.reversed()) { session in
                    SessionRow(session: session)
                }
            }
            .padding(Spacing.small)
        }
        .frame(width: 280)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.panel))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sessioni")
    }
}

/// A Sessione in the Colonna: title, Attività, and Progetto · branch.
private struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: session.title)
                    .font(Typography.body(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: Spacing.xSmall)
                Text(session.activity.title)
                    .font(Typography.mono(size: 10, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(session.activity == .errore ? Palette.danger : Palette.textSecondary)
            }
            Text(verbatim: [session.project.lastPathComponent, session.workspace?.branch].compactMap(\.self)
                .joined(separator: " · "))
                .font(Typography.mono(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            if let failure = session.failure {
                Text(verbatim: failure)
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            if let setupFailure = session.setupFailure {
                Text(verbatim: setupFailure)
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
        }
        .padding(Spacing.xSmall)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SessionColumn(sessions: [
        Session(id: UUID(), title: "Correggi il login", project: URL(filePath: "/Users/u/bubo"),
                workspace: Workspace(folder: URL(filePath: "/tmp/w"), branch: "bubo/correggi-il-login"),
                setupFailure: "Lo script di setup è uscito con codice 1.\nnpm error code ENOENT"),
        Session(id: UUID(), title: "Aggiorna le dipendenze", project: URL(filePath: "/Users/u/bubo"), activity: .errore,
                failure: "fatal: a branch named 'bubo/x' already exists"),
    ])
    .padding()
    .background(Palette.ink)
}
