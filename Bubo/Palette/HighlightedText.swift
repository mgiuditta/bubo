import SwiftUI

/// A fragment with the searched words highlighted, like the Indice found them, and underlined with dots when only its
/// meaning was found.
struct HighlightedText: View {
    let text: String
    let words: [String]
    /// Whether only the meaning of the fragment answers the search, none of its words.
    var isFoundByMeaning = false

    var body: some View {
        Text(highlighted)
    }

    private var highlighted: AttributedString {
        var attributed = AttributedString(text)
        if isFoundByMeaning {
            attributed.underlineStyle = Text.LineStyle(pattern: .dot, color: Palette.textSecondary)
        }
        for range in MatchHighlight.ranges(in: text, matching: words) {
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].foregroundColor = Palette.textPrimary
            attributed[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        }
        return attributed
    }
}
