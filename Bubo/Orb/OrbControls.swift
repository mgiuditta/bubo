import Observation

/// What drives every Orb on screen, and what the renderer reports back.
@Observable
final class OrbControls {
    /// The one set of controls: the Panel and, in phase 3, the HUD show the same Orb.
    static let shared = OrbControls()

    /// The Stato the Orb eases toward.
    var state: OrbState = .idle
    /// The Panel's latest frame measurements; updated only in Debug builds.
    var frameReading: FrameMeter.Reading?
}
