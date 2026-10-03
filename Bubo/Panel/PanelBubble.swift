import Foundation

/// How the bubble appears: it grows from the Orb, or only fades with Riduci movimento.
nonisolated enum PanelBubbleAppearance: Sendable, Equatable {
    case grow, fade

    /// Returns the appearance for the user's Riduci movimento setting.
    static func appearance(reducesMotion: Bool) -> PanelBubbleAppearance {
        reducesMotion ? .fade : .grow
    }
}

/// The bubble of the Panel: the Domanda's prompt, its streaming answer and the subtitles of the Sintesi parlata, beside
/// the Orb, without activating Bubo.
@Observable
final class PanelBubble {
    /// Where the keyboard goes when the bubble opens.
    enum Focus {
        /// To the prompt, as when the user asks to type.
        case prompt
        /// Nowhere: the bubble only shows an answer or a subtitle, and the app in front keeps the keyboard.
        case none
    }

    /// Whether the bubble is on screen, beside a visible Panel.
    private(set) var isOpen = false
    /// Why something asked from outside Bubo did not happen, such as "Nuova Sessione" on a Progetto that is gone;
    /// it goes when the bubble closes.
    private(set) var notice: String?
    /// Whether the prompt field has the keyboard; the app stays inactive either way.
    private(set) var takesKeyboard = false
    /// The side of the Panel the bubble opens on.
    var side = PanelBubbleSide.above
    /// The bubble's greatest height, in points, past which it scrolls: half the visible frame, at both Panel sizes.
    var maxHeight: CGFloat?
    /// How the bubble appears, read from Riduci movimento at each opening.
    private(set) var appearance = PanelBubbleAppearance.grow
    /// Whether the bubble last closed into the HUD, growing, rather than back into the Orb.
    private(set) var closesExpanding = false
    /// Whether the Domanda ended while the bubble was closed beside a visible Panel, and nobody has looked since; the
    /// status pill says so.
    private(set) var hasUnseenOutcome = false

    /// Whether an answer or a Sintesi parlata was under way the last time ``follow(isAnswering:isSpeaking:panelIsVisible:)``
    /// looked.
    @ObservationIgnored private var wasActive = false
    /// Whether an answer was under way the last time ``follow(isAnswering:isSpeaking:panelIsVisible:)`` looked.
    @ObservationIgnored private var wasAnswering = false

    /// Opens the bubble, giving the keyboard to the prompt when `focus` is `.prompt`.
    func open(focus: Focus, reducesMotion: Bool = Motion.isReduced) {
        if !isOpen {
            appearance = .appearance(reducesMotion: reducesMotion)
            closesExpanding = false
        }
        isOpen = true
        hasUnseenOutcome = false
        if focus == .prompt { takesKeyboard = true }
    }

    /// Opens the bubble with `notice`, leaving the keyboard to the app in front.
    func show(notice: String, reducesMotion: Bool = Motion.isReduced) {
        self.notice = notice
        open(focus: .none, reducesMotion: reducesMotion)
    }

    /// Closes the bubble growing, as the Domanda goes on in the HUD.
    func closeIntoHUD() {
        guard isOpen else { return }
        closesExpanding = true
        close()
    }

    /// Closes the bubble; an answer on its way keeps going.
    func close() {
        notice = nil
        isOpen = false
        takesKeyboard = false
    }

    /// Takes note that the prompt lost the keyboard, closing the bubble if `closes`.
    func loseKeyboard(closes: Bool) {
        takesKeyboard = false
        if closes { close() }
    }

    /// Follows the Domanda: an answer or a Sintesi parlata that starts while the Panel is visible opens the bubble
    /// without taking the keyboard, as with "Chiedi a Bubo" or push-to-talk; an answer that ends with the bubble closed
    /// beside a visible Panel is unseen until the bubble opens.
    func follow(isAnswering: Bool, isSpeaking: Bool, panelIsVisible: Bool) {
        let isActive = isAnswering || isSpeaking
        if isActive, !wasActive, panelIsVisible { open(focus: .none) }
        if isAnswering, !wasAnswering { hasUnseenOutcome = false }
        if wasAnswering, !isAnswering, !isOpen, panelIsVisible { hasUnseenOutcome = true }
        wasActive = isActive
        wasAnswering = isAnswering
    }

    /// Takes note that the user saw the Domanda elsewhere, as in the HUD.
    func markOutcomeSeen() {
        hasUnseenOutcome = false
    }

    /// Returns whether losing the keyboard closes the bubble: only with nothing typed, nothing attached, nothing
    /// answered, nothing on its way.
    nonisolated static func closesOnLosingKeyboard(prompt: String, answer: String, isAnswering: Bool,
                                                   hasAttachments: Bool = false) -> Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasAttachments && answer.isEmpty
            && !isAnswering
    }

    /// Returns what VoiceOver announces when an answer ends: once, never chunk by chunk.
    nonisolated static func announcement(wasAnswering: Bool, isAnswering: Bool, answer: String) -> String? {
        guard wasAnswering, !isAnswering, !answer.isEmpty else { return nil }
        return String(localized: "Risposta pronta")
    }
}
