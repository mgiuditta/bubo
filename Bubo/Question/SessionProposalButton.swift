import SwiftUI

/// The Sessione the Allegati of the Domanda propose, as a button that opens the new Sessione in the HUD (spec 09):
/// nothing when they propose none.
struct SessionProposalButton: View {
    let model: QuestionModel
    let hud: HUDPresenter

    var body: some View {
        if let proposal = model.sessionProposal {
            Button(Self.title(of: proposal), systemImage: "arrow.triangle.branch") {
                hud.turnIntoSession(model.turnIntoSession(accepting: proposal))
            }
            .buttonStyle(.plain)
            .font(Typography.body(size: 12))
            .foregroundStyle(Palette.textSecondary)
            .help(proposal.project.path(percentEncoded: false))
            .accessibilityIdentifier("question.sessionProposal")
        }
    }

    /// What the button says for `proposal`.
    private static func title(of proposal: SessionProposal) -> String {
        switch proposal {
        case let .session(project):
            String(localized: "Trasforma in Sessione su \(project.lastPathComponent)",
                   comment: "Button: turns the Domanda into a Sessione on the Progetto its files belong to")
        case .newProject:
            String(localized: "Apri come Progetto e crea Sessione",
                   comment: "Button: the dropped folder is a git repo with no Sessioni yet")
        }
    }
}
