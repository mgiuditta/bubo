import SwiftUI
import Testing
@testable import Bubo

/// The Notte palette keeps every text color readable: WCAG AA, 4.5:1 for text and 3:1 for non-text marks.
struct PaletteContrastTests {
    /// The backgrounds text sits on: the graphite, and a glass panel over it.
    private static let backgrounds: [(String, Color)] = [
        ("ink", Palette.ink),
        ("surface", Palette.surface),
    ]

    /// The colors of text to read.
    private static let textColors: [(String, Color)] = [
        ("textPrimary", Palette.textPrimary),
        ("textSecondary", Palette.textSecondary),
        ("attention", Palette.attention),
        ("success", Palette.success),
        ("danger", Palette.danger),
    ]

    /// The relative luminance of `color` drawn over `ink`, as WCAG defines it.
    ///
    /// Blends the gamma-encoded components, as the window server composites them, then linearizes.
    private static func luminance(of color: Color) -> Double {
        let environment = EnvironmentValues()
        let top = color.resolve(in: environment)
        let bottom = Palette.ink.resolve(in: environment)
        let alpha = top.opacity
        func linear(_ over: Float, _ under: Float) -> Double {
            let encoded = Double(over * alpha + under * (1 - alpha))
            return encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(top.red, bottom.red) + 0.7152 * linear(top.green, bottom.green)
            + 0.0722 * linear(top.blue, bottom.blue)
    }

    /// The WCAG contrast ratio between `foreground` and `background`, both drawn over `ink`.
    private static func contrast(_ foreground: Color, on background: Color) -> Double {
        let (first, second) = (luminance(of: foreground), luminance(of: background))
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    @Test func textIsReadableOnEveryBackground() {
        for (textName, text) in Self.textColors {
            for (backgroundName, background) in Self.backgrounds {
                #expect(Self.contrast(text, on: background) >= 4.5, "\(textName) on \(backgroundName)")
            }
        }
    }

    @Test func textOnTheAccentIsReadable() {
        #expect(Self.contrast(Palette.ink, on: Palette.accent) >= 4.5)
    }

    @Test func faintTextStillReadsAsAMark() {
        #expect(Self.contrast(Palette.textFaint, on: Palette.ink) >= 3)
    }
}
