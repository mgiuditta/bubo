import Observation
import SwiftUI

/// What drives every Orb on screen, and what the renderer reports back.
@Observable
final class OrbControls {
    /// The one set of controls: the Panel and, in phase 3, the HUD show the same Orb.
    static let shared = OrbControls()

    /// The Stato the Orb eases toward.
    var state: OrbState = .idle
    /// The Variante whose Forma the Orb takes; `nil` for the Blob.
    var variante: Variante?
    /// The provider whose Tinta the Orb takes; `nil` for one outside the list.
    var provider: Provider? = .anthropic
    /// The Panel's latest frame measurements; updated only in Debug builds.
    var frameReading: FrameMeter.Reading?

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
