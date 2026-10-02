import Observation
import SwiftUI

/// What drives every Orb on screen, and what the renderer reports back.
@Observable
final class OrbControls {
    /// The one set of controls: the Panel and, in phase 3, the HUD show the same Orb.
    static let shared = OrbControls()

    /// The Stato of the Sessioni, or the one chosen by hand in the debug windows.
    var state: OrbState = .idle
    /// The Stato of the Domanda under way, which wins over `state` while it lasts; `nil` when no Domanda is under way.
    var questionState: OrbState?
    /// The Variante whose Forma the Orb takes; `nil` for the Blob.
    var variante: Variante?
    /// The provider whose Tinta the Orb takes; `nil` for one outside the list.
    var provider: Provider? = .anthropic
    /// The microphone's level in Ascolto, from 0 to 1; `nil` when nothing is heard, and the Orb makes one up.
    var voiceLevel: Float?
    /// The Panel's latest frame measurements; updated only in Debug builds.
    var frameReading: FrameMeter.Reading?

    /// The Stato the Orb eases toward: the Domanda's while one is under way, otherwise the Sessioni's.
    var displayedState: OrbState { questionState ?? state }
    /// Gives the Orb the Variante `nome` that an agent at work chose; a name outside the Catalogo changes nothing.
    ///
    /// The Regia del Morph keeps every Variante at least 1.5 s and fades instead of morphing with Reduce Motion on.
    /// The Orbite plays to its end.
    func showWork(_ nome: String, in catalogo: Catalogo? = .bundled) {
        guard variante != Orbite.variante, let chosen = catalogo?.variante(named: nome) else { return }
        variante = chosen
    }

    /// The wait before the Orb goes back from the Orbite to the Blob.
    @ObservationIgnored private var orbiteReturn: Task<Void, Never>?

    /// Plays the Orbite: the Orb turns into the orbital diagram, then goes back to the Blob on its own.
    ///
    /// - Parameter reducesMotion: Whether the diagram fades in and stays still instead of morphing and moving.
    func playOrbite(reducesMotion: Bool = Motion.isReduced) {
        variante = Orbite.variante
        AccessibilityNotification.Announcement(String(localized: "Orbite")).post()
        orbiteReturn?.cancel()
        orbiteReturn = Task {
            try? await Task.sleep(for: .seconds(Orbite.returnDelay(reducesMotion: reducesMotion)))
            guard !Task.isCancelled, variante == Orbite.variante else { return }
            variante = nil
        }
    }
}
