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
    /// The voice level, from 0 to 1, that the ripple follows: heard in Ascolto, said in Parla; `nil` for a made-up one.
    var voiceLevel: Float?

    /// How long the shader clock runs forward before it runs back, in seconds. Below 4096 s a `Float` resolves the
    /// clock to half a millisecond; a clock that only grows loses it within hours and the Orb stutters, then stops.
    static let clockSpan: Double = 4096

    /// The shader clock, in seconds: it runs from 0 to `clockSpan` and back, so it never jumps.
    var time: Float {
        let phase = clock.truncatingRemainder(dividingBy: 2 * Self.clockSpan)
        return Float(phase <= Self.clockSpan ? phase : 2 * Self.clockSpan - phase)
    }
    /// The motion at the current instant.
    private(set) var motion = OrbState.idle.motion
    /// The ripple of the voice, nonzero only while listening or speaking.
    private(set) var audio: Float = 0
    /// The Tinta at the current instant.
    private(set) var tinta: Tinta

    /// Whether the motion has reached its Stato, the Tinta its target and the voice ripple zero: from here on only
    /// the shader clock moves.
    var isSettled: Bool {
        let tolerance: Float = 0.001
        let target = state.motion
        return targetTinta == tintaDestination && tintaProgress == 1 && audio < tolerance
            && OrbMotion.components.allSatisfy { abs(motion[keyPath: $0] - target[keyPath: $0]) < tolerance }
    }

    /// The wall time the clock has run, in seconds, kept in `Double` so that small steps are never lost.
    private var clock: Double = 0
    private var tintaOrigin: Tinta
    private var tintaDestination: Tinta
    private var tintaProgress: Double = 1

    /// Moves the animation forward by `elapsed` seconds of wall time.
    mutating func advance(by elapsed: Double) {
        let step = min(Self.longestStep, max(0, elapsed))
        clock += step * (reducesMotion ? Self.reducedPace : 1)
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

    /// The voice level the ripple follows: the one heard in Ascolto or said in Parla, otherwise a made-up one.
    private var voice: Float {
        guard state == .listening || state == .speaking else { return 0 }
        if let voiceLevel { return min(1, max(0, voiceLevel)) }
        let wave = (sin(time * 11) * 0.5 + 0.5) * (sin(time * 2.7 + 1) * 0.5 + 0.5)
        return max(0, wave * (state == .speaking ? 1 : 0.7) + sin(time * 23) * 0.08)
    }
}
