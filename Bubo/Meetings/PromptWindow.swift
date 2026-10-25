import AppKit
import SwiftUI

/// The Suggeritore's window: floating in the top right corner over every app and Space, without taking Bubo to the
/// front, and left out of screen sharing and screenshots, so the others in the call never see it. Closing it stops
/// following Wispr Flow.
final class PromptWindow {
    private let prompter: MeetingPrompter
    private let questions: QuestionModel
    private var window: PanelBubbleWindow?

    /// Creates the window of `prompter`, which opens notes as the Domande do.
    init(prompter: MeetingPrompter, questions: QuestionModel) {
        self.prompter = prompter
        self.questions = questions
    }

    /// Shows the window, in the top right corner the first time.
    func show() {
        let window = window ?? makeWindow()
        self.window = window
        if !window.isVisible { window.orderFrontFading() }
    }

    /// Hides the window and stops following Wispr Flow; the answers stay.
    func hide() {
        prompter.close()
        window?.orderOutFading()
    }

    private func makeWindow() -> PanelBubbleWindow {
        let view = PromptView(prompter: prompter, openNote: { [weak self] link in
            self?.open(link) ?? .discarded
        }, close: { [weak self] in
            self?.hide()
        })
        let window = PanelBubbleWindow.make(content: view)
        window.onCancel = { [weak self] in self?.hide() }
        window.sharingType = .none
        window.isMovableByWindowBackground = true
        window.setAccessibilityLabel(String(localized: "Suggeritore"))
        let size = CGSize(width: PromptView.width, height: PromptView.height)
        let screen = NSScreen.main?.visibleFrame ?? CGRect(origin: .zero, size: size)
        window.setFrame(CGRect(x: screen.maxX - size.width - Spacing.l, y: screen.maxY - size.height - Spacing.l,
                               width: size.width, height: size.height), display: false)
        return window
    }

    /// Opens a cited note in Obsidian when the Secondo cervello is a vault, otherwise in the app of Markdown files.
    private func open(_ link: URL) -> OpenURLAction.Result {
        guard let citation = NoteCitation(link: link) else { return .systemAction }
        let hasObsidian = NoteDestination.obsidianLink(to: URL(filePath: "/"))
            .flatMap(NSWorkspace.shared.urlForApplication(toOpen:)) != nil
        switch questions.destination(of: citation, hasObsidian: hasObsidian) {
        case let .obsidian(obsidianLink):
            return .systemAction(obsidianLink)
        case let .quickLook(file):
            NSWorkspace.shared.open(file)
            return .handled
        case nil:
            return .discarded
        }
    }
}
