import SwiftUI

/// The durations and curves of Bubo's animations.
enum Motion {
    /// Hover and press feedback.
    static let quick = Animation.easeOut(duration: 0.2)
    /// Selection and state changes.
    static let standard = Animation.easeInOut(duration: 0.3)
    /// Panels appearing and moving.
    static let emphasized = Animation.spring(duration: 0.5, bounce: 0.15)
    /// One turn of the outer HUD ring, in seconds.
    static let outerRingPeriod: Double = 60
    /// One turn of the inner HUD ring, in seconds; it turns the other way.
    static let innerRingPeriod: Double = 90
}
