import SwiftUI

/// The three typefaces of Bubo, bundled in `Resources/Fonts`.
enum Typography {
    /// The wide, light display face for the brand and large titles.
    static func display(size: CGFloat) -> Font {
        .custom("Unbounded", size: size).weight(.light)
    }

    /// The text face.
    static func body(size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
        .custom("Manrope", size: size).weight(weight)
    }

    /// The monospaced face for data and labels.
    static func mono(size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
        .custom("JetBrains Mono", size: size).weight(weight)
    }
}
