import SwiftUI

extension View {
    /// Scrolls `proxy` to the Sessione chosen in the menu bar, then clears the choice: the Vista shows it once.
    func revealingSession(with proxy: ScrollViewProxy) -> some View {
        modifier(RevealedSession(proxy: proxy))
    }
}

/// Brings the Sessione chosen in the menu bar into view in a Vista that scrolls.
private struct RevealedSession: ViewModifier {
    let proxy: ScrollViewProxy
    @Environment(HUDPresenter.self) private var hud

    func body(content: Content) -> some View {
        content.onChange(of: hud.revealedSession, initial: true) {
            guard let id = hud.revealedSession else { return }
            withAnimation(Motion.isReduced ? nil : Motion.standard) { proxy.scrollTo(id, anchor: .center) }
            hud.revealedSession = nil
        }
    }
}
