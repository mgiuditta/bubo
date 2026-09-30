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
    /// One turn of the outer HUD ring, in seconds.
    static let outerRingPeriod: Double = 60
    /// One turn of the inner HUD ring, in seconds; it turns the other way.
    static let innerRingPeriod: Double = 90
}
