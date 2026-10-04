import AppKit
import OSLog
import SwiftUI

/// Shows and hides the HUD window from anywhere, including the global shortcut.
@Observable
final class HUDPresenter {
    /// The id of the HUD `Window` scene.
    static let windowID = "hud"

    /// Captured from the first SwiftUI view that appears, since AppKit code has
    /// no environment of its own.
    @ObservationIgnored var openWindow: OpenWindowAction?

    /// Called each time something brings the HUD to the front; not when it appears at launch.
    @ObservationIgnored var didShow: (() -> Void)?

    /// Whether the HUD shows the new Sessione sheet.
    var isCreatingSession = false

    /// Whether the HUD shows the new Bozza sheet.
    var isCreatingDraft = false

    /// Whether the HUD shows the sheet of the GitHub issues (⌘I).
    var isPickingIssue = false

    /// The Sessione whose Apri PR sheet the HUD shows, opened from the menu or the Palette; `nil` for none.
    var pullRequestSession: Session?

    /// The Sessione whose foglio di Consegna the HUD shows, opened from the menu or the Sessione; `nil` for none.
    var deliverySession: Session?

    /// The Sessione the HUD brings into view once it is in front, chosen from the menu bar; the Vista that shows it
    /// sets it back to `nil`.
    var revealedSession: Session.ID?

    /// Opens the Palette with a text in its box; set by the app, since the Palette is an AppKit window.
    @ObservationIgnored var searchConversations: ((String) -> Void)?

    /// Puts Allegati in the prompt of the Domanda, for a drop in the HUD with no open Sessione in front; set by the app.
    @ObservationIgnored var attachToQuestion: ([Allegato]) -> Void = { _ in }

    /// Imports the dropped recordings and trascrizioni as Riunioni; set by the app.
    @ObservationIgnored var importMeetings: ([URL]) -> Void = { _ in }

    /// Opens the Costi window; set by the app, since it is an AppKit window.
    @ObservationIgnored var showCosts: (() -> Void)?
    /// Opens the Neuroni window; set by the app.
    @ObservationIgnored var showNeurons: (() -> Void)?
    /// Opens the Riunioni window; set by the app.
    @ObservationIgnored var showMeetings: (() -> Void)?

    /// What the sidebar of the window has chosen, shown on the right; the Cervello when the window opens.
    var selection = SidebarSelection.brain
    /// Shows the Galassia of a Sessione's Progetto, filtered on it with its comet followed; `nil` in previews.
    @ObservationIgnored var showInGalaxy: ((Session) -> Void)?

    /// What the new Sessione sheet starts from.
    private(set) var sessionDraft = SessionDraft()

    /// Brings the HUD to the front with the new Sessione sheet (⌘N), filled in from `draft`.
    func createSession(from draft: SessionDraft = SessionDraft()) {
        sessionDraft = draft
        isCreatingSession = true
        show()
    }

    /// Brings the HUD to the front on the Board, where the Bozze are, with the new Bozza sheet (⌥⌘N).
    func createDraft() {
        isCreatingDraft = true
        showDrafts()
    }

    /// Brings the HUD to the front on the Board, where the Bozze are.
    func showDrafts() {
        selection = .work
        show()
    }

    /// Brings the HUD to the front with the sheet of the open GitHub issues of a Progetto (⌘I).
    func pickIssue() {
        isPickingIssue = true
        show()
    }

    /// Brings the HUD to the front with the Apri PR sheet of `session`.
    func openPullRequest(of session: Session) {
        pullRequestSession = session
        show()
    }

    /// Brings the HUD to the front with the foglio di Consegna of `session`.
    func deliver(_ session: Session) {
        deliverySession = session
        show()
    }

    /// Starts a Sessione from a Domanda at once, without the sheet, and returns its identifier; `nil` when the sheet is
    /// needed, as with no trusted Progetto.
    @ObservationIgnored var startSession: ((SessionDraft) -> Session.ID?)?

    /// Hands the Domanda to a Sessione ("Trasforma in Sessione"): started at once with the proposed title, branch and
    /// Progetto, and shown; the sheet only when it cannot start on its own.
    func turnIntoSession(_ draft: SessionDraft) {
        if draft.continuesQuestion, let id = startSession?(draft) {
            show(session: id)
        } else {
            createSession(from: draft)
        }
    }

    /// Brings the HUD to the front on the Sessione `id`.
    func show(session id: Session.ID) {
        revealedSession = id
        selection = .session(id)
        show()
    }

    /// Brings the window to the front on the Domanda `id`, to continue it there («Apri nella finestra»).
    func show(question id: UUID) {
        selection = .question(id)
        show()
    }

    /// Whether the HUD is in front of the user: visible, key, with Bubo active.
    var isFrontmost: Bool {
        guard let window = hudWindow else { return false }
        return window.isVisible && window.isKeyWindow && NSApp.isActive
    }

    /// Brings the HUD to the front, or hides it if it is already frontmost.
    func toggle() {
        if isFrontmost {
            hudWindow?.orderOutFading()
        } else {
            show()
        }
    }

    /// Brings the HUD to the front, creating it if it was closed.
    func show() {
        didShow?()
        NSApp.activate()
        if let window = hudWindow, window.isMiniaturized {
            // The Dock's own animation brings it back.
            window.makeKeyAndOrderFront(nil)
        } else if let window = hudWindow {
            // Also while it fades out: it comes back instead of going.
            window.makeKeyAndOrderFrontFading()
        } else {
            openWindow?(id: Self.windowID)
            // Made now, drawn at the end of the turn: it fades in from there.
            if let window = hudWindow {
                window.alphaValue = 0
                window.makeKeyAndOrderFrontFading()
            }
        }
    }

    private var hudWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(Self.windowID) == true }
    }
}
