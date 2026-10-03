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
    /// The microphone's level in Ascolto or the voice's in Parla, from 0 to 1; `nil` for a made-up one.
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

    /// Whether the Orb has already greeted as the owl since launch.
    @ObservationIgnored private var hasGreeted = false

    /// Greets once per launch: the Orb turns into the owl of the Segno, then goes back to the Blob on its own.
    ///
    /// Later calls change nothing, and so does a call while the Orb already shows a Variante.
    /// - Parameter reducesMotion: Whether the owl fades in instead of morphing.
    func greet(reducesMotion: Bool = Motion.isReduced) {
        guard !hasGreeted, variante == nil else { return }
        hasGreeted = true
        variante = Gufo.variante
        orbiteReturn?.cancel()
        orbiteReturn = Task {
            try? await Task.sleep(for: .seconds(Gufo.returnDelay(reducesMotion: reducesMotion)))
            guard !Task.isCancelled, variante == Gufo.variante else { return }
            variante = nil
        }
    }

    /// Turns the Blob into the owl while the pointer is on the Orb, and back to the Blob when it leaves.
    ///
    /// A Variante at work and the Orbite stay as they are; the Regia del Morph keeps the owl at least 1.5 s.
    /// - Parameter isPointerInside: Whether the pointer has just entered the Orb, or just left it.
    func hover(isPointerInside: Bool) {
        if isPointerInside {
            guard variante == nil || variante == Gufo.variante else { return }
            orbiteReturn?.cancel()
            variante = Gufo.variante
        } else if variante == Gufo.variante {
            orbiteReturn?.cancel()
            variante = nil
        }
    }

    /// The wait before the Orb goes back from the Orbite, or the owl, to the Blob.
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
