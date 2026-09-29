import SwiftUI

/// The semantic colors of Bubo, taken from `reference/bubo.html`.
///
/// Views use roles (`accent`, `surface`, `attention`), never raw hues, so a new
/// visual direction changes only this file.
enum Palette {
    /// The warm graphite behind everything.
    static let ink = Color(hex: 0x0C0A09)
    /// The fill of glass panels.
    static let surface = Color(hex: 0xFFECE0, opacity: 0.035)
    /// Hairline borders.
    static let line = Color(hex: 0xFFCEB4, opacity: 0.11)
    /// Borders of focused or selected elements.
    static let lineStrong = Color(hex: 0xFFBE96, opacity: 0.28)
    /// Primary text.
    static let textPrimary = Color(hex: 0xF4EBE4)
    /// Secondary text and labels.
    static let textSecondary = Color(hex: 0x9B8A80)
    /// Disabled text and hints.
    static let textFaint = Color(hex: 0x5F524B)
    /// The brand accent.
    static let accent = Color(hex: 0xD97757)
    /// The highlight of the accent, for glows and selected states.
    static let accentStrong = Color(hex: 0xFFB089)
    /// Whatever needs the user now, such as a Session waiting for them.
    static let attention = accentStrong
    /// Healthy, running, or added.
    static let success = Color(hex: 0x8FD1A8)
    /// Errors, removals, and destructive actions.
    static let danger = Color(hex: 0xE0685A)
}
