import SwiftUI

/// The menu bar item: the owl, with its dot while Sessioni are in Attende te, and how many for VoiceOver.
///
/// Apart from the app's scenes, so that only it follows the Sessioni's Attività.
struct MenuBarLabel: View {
    /// The Sessioni; `nil` when they cannot be kept.
    let sessions: SessionStore?

    var body: some View {
        let waiting = sessions?.sessions.count { $0.isLive && $0.activity == .attende } ?? 0
        Label {
            Text(MenuBarGlyph.accessibilityDescription(waiting: waiting))
        } icon: {
            // Its description says the count too; the dot is drawn only when the menu bar shows it.
            Image(nsImage: MenuBarGlyph.makeImage(waiting: waiting))
        }
    }
}
