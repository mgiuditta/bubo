import AppKit
import QuickLook
import SwiftUI

/// The Domanda's answer as it streams, scrolling to its end, with the reason line once it is complete: the same in the
/// HUD and in the Panel's bubble.
struct QuestionAnswer: View {
    let model: QuestionModel
    /// Opens "Rifai con…".
    let pickRetry: () -> Void
    /// The answer's tallest height before it scrolls on its own; `nil` lets it grow, for a container that scrolls.
    var maxAnswerHeight: CGFloat? = 220
    /// The cited note shown in Quick Look.
    @State private var previewedNote: URL?
    /// The cited note last clicked that is not in the Secondo cervello.
    @State private var missingNote: NoteCitation?

    var body: some View {
        answerScroll {
            // The notes cited as `[[nota]]` become links that open them; a Secondo cervello block never shows raw.
            Text(NoteCitation.linking(SecondBrainProposal.prose(of: model.answer)))
                .font(Typography.body(size: 14))
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel("Risposta di Claude")
        .accessibilityIdentifier("question.answer")
        .environment(\.openURL, OpenURLAction(handler: open))
        .quickLookPreview($previewedNote)
        if let missingNote {
            Text("«\(missingNote.title)» non è nel Secondo cervello.")
                .font(Typography.body(size: 13))
                .foregroundStyle(Palette.textSecondary)
                .accessibilityIdentifier("question.missingNote")
        }
        // Under every answer, once it is complete or stopped: who answered it, why, and at what cost.
        if !model.isAnswering, let routedAnswer = model.routedAnswer {
            HStack(spacing: Spacing.xSmall) {
                RouterLine(answer: routedAnswer)
                // ⌘↑ only with the prompt empty: while typing it stays the text field's "go to the start".
                Button("Rifai più forte", systemImage: "arrow.up", action: model.retryStronger)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.textSecondary)
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(model.strongerRoute == nil || !model.prompt.isEmpty)
                    .help("Rifai con un modello o uno sforzo più forte (⌘↑)")
                    .accessibilityIdentifier("question.retryStronger")
                Button("Rifai con…", systemImage: "arrow.triangle.swap") { pickRetry() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.textSecondary)
                    .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                    .disabled(model.retryAlternatives.isEmpty && model.excludedEndpoints.isEmpty
                              || !model.prompt.isEmpty)
                    .help("Rifai con un altro modello (⌘⇧↑)")
                    .accessibilityIdentifier("question.retryWith")
            }
        }
    }

    /// The answer in its own scroll view up to `maxAnswerHeight`, or as it is inside a container that scrolls.
    @ViewBuilder
    private func answerScroll(@ViewBuilder content: () -> some View) -> some View {
        if let maxAnswerHeight {
            ScrollView(content: content)
                .frame(maxHeight: maxAnswerHeight)
                .defaultScrollAnchor(.bottom)
        } else {
            content()
        }
    }

    /// Opens a note cited in the answer in Obsidian or Quick Look; any other link goes to the system.
    private func open(_ link: URL) -> OpenURLAction.Result {
        guard let citation = NoteCitation(link: link) else { return .systemAction }
        let hasObsidian = NoteDestination.obsidianLink(to: URL(filePath: "/"))
            .flatMap(NSWorkspace.shared.urlForApplication(toOpen:)) != nil
        missingNote = nil
        switch model.destination(of: citation, hasObsidian: hasObsidian) {
        case let .obsidian(obsidianLink):
            return .systemAction(obsidianLink)
        case let .quickLook(file):
            previewedNote = file
        case nil:
            missingNote = citation
        }
        return .handled
    }
}
