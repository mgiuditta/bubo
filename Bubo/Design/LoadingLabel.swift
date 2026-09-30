import SwiftUI

/// The only spinner in Bubo: it says what it waits for once the wait passes one second.
///
/// `scripts/polish-check.sh` fails on a `ProgressView` anywhere else, so no spinner
/// ever spins for long without text.
struct LoadingLabel: View {
    /// How long the spinner may spin alone before the title appears.
    static let titleDelay: Duration = .seconds(1)

    private let title: LocalizedStringKey
    @State private var showsTitle = false

    /// Creates a spinner for a wait described by `title`, such as "Carico le Sessioni…".
    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: Spacing.xSmall) {
            ProgressView()
                .controlSize(.small)
            if showsTitle {
                Text(title)
                    .font(Typography.body(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .transition(.opacity)
            }
        }
        .animation(Motion.quick, value: showsTitle)
        // VoiceOver hears the title at once, without waiting for it to appear.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .task {
            try? await Task.sleep(for: Self.titleDelay)
            guard !Task.isCancelled else { return }
            showsTitle = true
        }
    }
}

