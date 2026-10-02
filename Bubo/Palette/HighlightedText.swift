import SwiftUI

/// A fragment with the searched words highlighted, like the Indice found them.
struct HighlightedText: View {
    let text: String
    let words: [String]

    var body: some View {
        Text(highlighted)
    }

    private var highlighted: AttributedString {
        var attributed = AttributedString(text)
        for range in MatchHighlight.ranges(in: text, matching: words) {
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].foregroundColor = Palette.textPrimary
            attributed[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        }
        return attributed
    }
}
