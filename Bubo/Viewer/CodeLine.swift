import SwiftUI

/// A line of the visore and its highlighted stretches.
nonisolated struct CodeLine: Equatable, Sendable {
    var text: String
    var spans: [SyntaxHighlighter.Span]
}

extension CodeLine {
    /// The line with its keywords, strings, numbers and comments coloured, built only when the row shows.
    var attributed: AttributedString {
        var attributed = AttributedString()
        var index = text.startIndex
        for span in spans {
            attributed += AttributedString(text[index..<span.range.lowerBound])
            var piece = AttributedString(text[span.range])
            piece.foregroundColor = Self.color(of: span.kind)
            if span.kind == .keyword { piece.inlinePresentationIntent = .stronglyEmphasized }
            attributed += piece
            index = span.range.upperBound
        }
        attributed += AttributedString(text[index...])
        return attributed
    }

    /// Keywords stand out by weight, not hue: the container is achromatic (ADR 0004).
    private static func color(of kind: SyntaxHighlighter.Kind) -> Color {
        switch kind {
        case .keyword, .number: Palette.textPrimary
        case .string: Palette.success
        case .comment: Palette.textSecondary
        }
    }
}
