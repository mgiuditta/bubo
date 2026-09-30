import Foundation

/// The Orb's motion over time: it always eases toward the current Stato, never jumps.
///
/// Time is an input, so the renderer drives it frame by frame and tests drive it by hand.
/// The easing is `frame()` of `reference/bubo.html`.
nonisolated struct OrbAnimation {
    /// The longest step the clock takes, so a resume after a pause does not jump.
    static let longestStep: Double = 0.05
    /// How fast the motion closes the gap to the Stato, per second.
    static let stateRate: Double = 3
    /// How fast the voice ripple follows the voice, per second.
    static let audioRate: Double = 12
    /// The clock's pace with Reduce Motion on.
    static let reducedPace: Double = 0.35
    /// How long the Orb takes to turn to a new Tinta, in seconds.
    static let tintaDuration: Double = 1.2
    /// How long the Tinta cross-fades with Reduce Motion on, in seconds.
    static let reducedTintaDuration: Double = 0.4

    /// Creates an animation at rest, already in `tinta`.
    init(tinta: Tinta = .neutral) {
        self.tinta = tinta
        targetTinta = tinta
        tintaOrigin = tinta
        tintaDestination = tinta
    }

    /// The Stato the motion eases toward.
    var state: OrbState = .idle
    /// The Tinta the Orb turns to; a change starts a new turn from wherever the Tinta is now.
    var targetTinta: Tinta
    /// Whether the Orb's own motion is slowed down.
    var reducesMotion = false

    /// The shader clock, in seconds.
    private(set) var time: Float = 0
    /// The motion at the current instant.
    private(set) var motion = OrbState.idle.motion
    /// The ripple of the voice, nonzero only while listening or speaking.
    private(set) var audio: Float = 0
    /// The Tinta at the current instant.
    private(set) var tinta: Tinta

    private var tintaOrigin: Tinta
    private var tintaDestination: Tinta
    private var tintaProgress: Double = 1

    /// Moves the animation forward by `elapsed` seconds of wall time.
    mutating func advance(by elapsed: Double) {
        let step = min(Self.longestStep, max(0, elapsed))
        time += Float(step * (reducesMotion ? Self.reducedPace : 1))
        motion.approach(state.motion, by: Float(min(1, step * Self.stateRate)))
        audio += (voice - audio) * Float(min(1, step * Self.audioRate))
        advanceTinta(by: step)
    }

    /// Turns the Tinta toward `targetTinta` along a smoothstep.
    private mutating func advanceTinta(by step: Double) {
        if targetTinta != tintaDestination {
            tintaOrigin = tinta
            tintaDestination = targetTinta
            tintaProgress = 0
        }
        let duration = reducesMotion ? Self.reducedTintaDuration : Self.tintaDuration
        tintaProgress = min(1, tintaProgress + step / duration)
        let eased = Float(tintaProgress * tintaProgress * (3 - 2 * tintaProgress))
        tinta = tintaOrigin.mixed(with: tintaDestination, by: eased)
    }

    /// A made-up voice level, until the real one arrives with voice input.
    private var voice: Float {
        guard state == .listening || state == .speaking else { return 0 }
        let wave = (sin(time * 11) * 0.5 + 0.5) * (sin(time * 2.7 + 1) * 0.5 + 0.5)
        return max(0, wave * (state == .speaking ? 1 : 0.7) + sin(time * 23) * 0.08)
    }
}
