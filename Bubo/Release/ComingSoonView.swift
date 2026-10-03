import SwiftUI

/// «Arriverà presto»: what an unreleased area shows at its entrance, the title and one line on what it will do.
///
/// Plain text for VoiceOver, read as one element: never a disabled control.
struct ComingSoonView: View {
    let area: ReleaseArea

    var body: some View {
        VStack(spacing: Spacing.xSmall) {
            Image(systemName: area.systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(area.title)
                .font(.title2.weight(.semibold))
            Text("Arriverà presto")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(area.summary)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xLarge)
        .padding(.horizontal, Spacing.large)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ComingSoonView(area: .machines)
        .frame(width: 480)
}
