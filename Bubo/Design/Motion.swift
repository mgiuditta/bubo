import SwiftUI

/// The durations and curves of Bubo's animations: the only place that writes one.
///
/// The container moves little and fast, 150–250 ms; only the Orb breathes, in its shader.
/// `scripts/polish-check.sh` fails on an animation duration written outside `Design/`.
enum Motion {
    /// Hover and press feedback, 150 ms.
    static let quick = Animation.easeOut(duration: 0.15)
    /// Selection and state changes, 200 ms.
    static let standard = Animation.easeInOut(duration: 0.2)
    /// Panels appearing and moving, 250 ms.
    static let emphasized = Animation.spring(duration: 0.25, bounce: 0.15)
    /// The press that approves a Richiesta di permesso of level 4–5, 1 s, filling at an even pace.
    static let hold = Animation.linear(duration: 1)
    /// The camera's flight to a file or a folder of the Galassia, in seconds: the map moves, not the container.
    static let galaxyFlight: Double = 0.65
    /// A comet's move from one file of the Galassia to the next one its Sessione touches, in seconds: only on a real
    /// tool event, never at rest.
    static let galaxyComet: Double = 0.45
    /// One turn of the outer HUD ring, in seconds.
    static let outerRingPeriod: Double = 60
    /// One turn of the inner HUD ring, in seconds; it turns the other way.
    static let innerRingPeriod: Double = 90

    /// The `UserDefaults` key of Riduci movimento in Aspetto.
    static let reducesMotionKey = "reducesMotion"

    /// Whether Riduci movimento is on, in Aspetto or in the system's settings.
    static var isReduced: Bool {
        isReduced(in: .standard, system: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// Whether Riduci movimento is on, given the choice kept in `defaults` and the system's setting.
    static func isReduced(in defaults: UserDefaults, system: Bool) -> Bool {
        system || defaults.bool(forKey: reducesMotionKey)
    }
}
