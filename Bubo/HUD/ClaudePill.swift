import SwiftUI

/// The pill at the top of the HUD during onboarding: the `claude` that will answer, and how it is paid for.
struct ClaudePill: View {
    let readiness: ClaudeReadiness

    var body: some View {
        label
            .font(Typography.mono(size: 11))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, Spacing.xxSmall)
            .overlay(Capsule().strokeBorder(Palette.line))
    }

    private var label: Text {
        switch readiness {
        case let .ready(version, method): Text(verbatim: "claude \(version) · \(method)")
        case .missing: Text("claude non trovata")
        case let .signedOut(version): Text("claude \(version) · senza accesso")
        case let .outdated(version): Text("claude \(version) · da aggiornare")
        }
    }
}

#Preview {
    VStack {
        ClaudePill(readiness: .ready(version: "2.1.286", method: "Max"))
        ClaudePill(readiness: .missing)
        ClaudePill(readiness: .signedOut(version: "2.1.286"))
        ClaudePill(readiness: .outdated(version: "2.0.9"))
    }
    .padding()
    .background(Palette.ink)
}
