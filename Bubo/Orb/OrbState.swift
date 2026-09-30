import Foundation

/// What Bubo is doing, shown by the Orb's motion and light; it never changes the Orb's Forma.
nonisolated enum OrbState: CaseIterable, Identifiable {
    case idle, listening, thinking, speaking, working

    var id: Self { self }

    /// The name of the Stato, as in the glossary.
    var title: LocalizedStringResource {
        switch self {
        case .idle: "Riposo"
        case .listening: "Ascolto"
        case .thinking: "Pensiero"
        case .speaking: "Parla"
        case .working: "Lavora"
        }
    }

    /// The motion the Orb eases toward in this Stato; values from `STATES` in `reference/bubo.html`.
    var motion: OrbMotion {
        switch self {
        case .idle: OrbMotion(amplitude: 0.07, frequency: 1.5, speed: 0.3, swirl: 0, glow: 0.9, spike: 0)
        case .listening: OrbMotion(amplitude: 0.1, frequency: 2.1, speed: 0.8, swirl: 0, glow: 1.1, spike: 0)
        case .thinking: OrbMotion(amplitude: 0.1, frequency: 3.0, speed: 1.3, swirl: 1.4, glow: 1.2, spike: 0)
        case .speaking: OrbMotion(amplitude: 0.08, frequency: 1.8, speed: 0.6, swirl: 0.1, glow: 1.25, spike: 0)
        case .working: OrbMotion(amplitude: 0.14, frequency: 3.6, speed: 1.0, swirl: 0.4, glow: 1.1, spike: 0.3)
        }
    }
}

/// The shader parameters a Stato sets: how the Orb moves and how much it glows.
nonisolated struct OrbMotion: Equatable {
    /// How far the surface ripples.
    var amplitude: Float
    /// How fine the ripples are.
    var frequency: Float
    /// How fast the ripples flow.
    var speed: Float
    /// How much the Orb twists around its vertical axis.
    var swirl: Float
    /// How bright the halo is.
    var glow: Float
    /// How spiky the surface is; the Tinta adds its own on top.
    var spike: Float

    /// Every component, for code that treats them alike.
    static var components: [WritableKeyPath<OrbMotion, Float>] {
        [\.amplitude, \.frequency, \.speed, \.swirl, \.glow, \.spike]
    }

    /// Moves every component toward `target` by `fraction` of the remaining distance.
    mutating func approach(_ target: OrbMotion, by fraction: Float) {
        for component in Self.components {
            self[keyPath: component] += (target[keyPath: component] - self[keyPath: component]) * fraction
        }
    }
}
