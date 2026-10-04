import SwiftUI

/// The typefaces of Bubo, bundled in `Resources/Fonts`.
///
/// New views use the brand kit roles (`Font.buboDisplay`, `buboTitle`, `buboBody`, `buboInterface`, `buboData`);
/// the functions below stay for the views drawn before it.
enum Typography {
    /// The PostScript name of the display face: Newsreader Medium.
    static let displayFaceName = "NewsreaderRoman-Medium"
    /// The tracking of titles, slightly tight.
    static let titleTracking: CGFloat = -0.2

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

extension Font {
    /// Newsreader Medium 34: the logotype, the empty home and note titles. Scales with `.largeTitle`.
    static var buboDisplay: Font { .custom(Typography.displayFaceName, size: 34, relativeTo: .largeTitle) }
    /// SF Pro semibold 22 (the macOS `.title` style). Use `buboTitleStyle()` for its tracking.
    static var buboTitle: Font { .title.weight(.semibold) }
    /// SF Pro 15 (the macOS `.title3` style): the text of a conversation.
    static var buboBody: Font { .title3 }
    /// SF Pro 13 (the macOS `.body` style): controls and labels.
    static var buboInterface: Font { .body }
    /// SF Mono 12 with tabular digits (the macOS `.callout` style): data, costs, durations, uppercase labels.
    static var buboData: Font { .system(.callout, design: .monospaced).monospacedDigit() }
}

extension View {
    /// Sets the title font with its −0.2 pt tracking.
    func buboTitleStyle() -> some View {
        font(.buboTitle).tracking(Typography.titleTracking)
    }
}
