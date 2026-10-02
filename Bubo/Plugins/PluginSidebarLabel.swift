import SwiftUI

/// A row of the Plugin window's sidebar, with its count when it has one.
///
/// The selected row is on the moon-colored accent, so its text turns to ink. The count is a number in the text
/// color, never Lume: Lume is only for what waits for the user (design system).
struct PluginSidebarLabel: View {
    private let title: Text
    private let systemImage: String
    private let count: Int?
    /// What VoiceOver says for the count.
    private let countLabel: Text?
    /// Whether the row has the dot of the versions newer than the installed ones.
    private let hasUpdates: Bool
    @Environment(\.backgroundProminence) private var prominence

    /// Creates a row titled `title`, with `count` at its end when it is not `nil`, read by VoiceOver as
    /// `countLabel`.
    init(_ title: LocalizedStringKey, systemImage: String, count: Int? = nil, countLabel: Text? = nil) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.count = count
        self.countLabel = countLabel
        self.hasUpdates = false
    }

    /// Creates a row titled with a name that is not translated, such as a Marketplace's, with a dot when it has
    /// updates.
    init(verbatim title: String, systemImage: String, hasUpdates: Bool = false) {
        self.title = Text(verbatim: title)
        self.systemImage = systemImage
        self.count = nil
        self.countLabel = nil
        self.hasUpdates = hasUpdates
    }

    var body: some View {
        HStack {
            Label { title } icon: { Image(systemName: systemImage) }
            Spacer(minLength: 0)
            if let count {
                Text(count, format: .number)
                    .font(Typography.mono(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .accessibilityLabel(countLabel ?? Text("\(count) da sistemare"))
            }
            if hasUpdates {
                Circle()
                    .frame(width: 6, height: 6)
                    .accessibilityElement()
                    .accessibilityLabel(Text("Aggiornamenti disponibili"))
            }
        }
        .foregroundStyle(prominence == .increased ? Palette.ink : Palette.textPrimary)
    }
}
