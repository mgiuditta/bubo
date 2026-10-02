import SwiftUI

/// A line about the agents of the Progetto, colored by how much it matters (design system, ADR 0004): only errors take
/// `danger`; a warning stands out by lightness and weight, information stays secondary.
struct AgentNotice: View {
    enum Kind {
        /// Something failed, such as an agent that claude does not load.
        case error
        /// Something works but deserves attention, such as two agents with the same name.
        case warning
        /// Something to know, such as a new folder.
        case information
    }

    let text: LocalizedStringKey
    let kind: Kind

    init(_ text: LocalizedStringKey, kind: Kind) {
        self.text = text
        self.kind = kind
    }

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .fontWeight(kind == .warning ? .semibold : nil)
                .foregroundStyle(kind == .information ? Palette.textSecondary : Palette.textPrimary)
        } icon: {
            // The text says it all, so VoiceOver skips the symbol.
            Image(systemName: kind == .information ? "info.circle" : "exclamationmark.triangle.fill")
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
        }
    }

    private var iconColor: Color {
        switch kind {
        case .error: Palette.danger
        case .warning: Palette.textPrimary
        case .information: Palette.textSecondary
        }
    }
}
