import SwiftUI

/// The semantic colors of Bubo, in the Notte direction of `docs/design-system.md` (ADR 0004).
///
/// The container is achromatic: views say "selected" or "important" with lightness, weight and borders, never with a
/// hue. Color belongs to the Orb's Tinta and to three semantic roles (`attention`, `success`, `danger`). Views use
/// roles, never raw hues, so a new visual direction changes only this file.
enum Palette {
    /// The cold graphite behind everything.
    static let ink = Color(hex: 0x0A0B0D)
    /// The fill of glass panels.
    static let surface = Color(hex: 0xE8ECF2, opacity: 0.035)
    /// Hairline borders.
    static let line = Color(hex: 0xE2E8F0, opacity: 0.09)
    /// Borders of focused or selected elements, and the HUD rings.
    static let lineStrong = Color(hex: 0xE2E8F0, opacity: 0.24)
    /// Primary text, moon colored.
    static let textPrimary = Color(hex: 0xECEEF1)
    /// Secondary text and labels; at least 4.5:1 on `ink`.
    static let textSecondary = Color(hex: 0x8E939B)
    /// Hints and disabled text; never text to read.
    static let textFaint = Color(hex: 0x5A5F66)
    /// The lit side of the brand mark (design system, Marchio); never text.
    static let markLight = Color(hex: 0xF6F7F9)
    /// The shadow side of the brand mark (design system, Marchio); never text.
    static let markDark = Color(hex: 0x1C1F24)
    /// The on-state track of switches: the system knob is white, so a moon-colored track would hide it.
    static let switchTrack = textSecondary
    /// Selection: the filled primary button and the active item, expressed with lightness. Text on it is `ink`.
    static let accent = textPrimary
    /// Lume, the one signal: only what waits for the user, such as Attende te and permission requests.
    static let attention = Color(hex: 0xD6F26B)
    /// Additions and passed checks.
    static let success = Color(hex: 0x7FC8A0)
    /// Errors, removals, destructive actions, and Livello di rischio 4–5.
    static let danger = Color(hex: 0xF2555A)
}
