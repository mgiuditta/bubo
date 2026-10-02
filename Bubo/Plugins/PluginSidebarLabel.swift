import SwiftUI

/// A row of the Plugin window's sidebar, with its count when it has one.
///
/// The selected row is on the moon-colored accent, so its text turns to ink. The count is a number in the text
/// color, never Lume: Lume is only for what waits for the user (design system).
struct PluginSidebarLabel: View {
    private let title: Text
    private let systemImage: String
    private let count: Int?
    @Environment(\.backgroundProminence) private var prominence

    /// Creates a row titled `title`, with `count` at its end when it is not `nil`.
    init(_ title: LocalizedStringKey, systemImage: String, count: Int? = nil) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.count = count
    }

    /// Creates a row titled with a name that is not translated, such as a Marketplace's.
    init(verbatim title: String, systemImage: String) {
        self.title = Text(verbatim: title)
        self.systemImage = systemImage
        self.count = nil
    }

    var body: some View {
        HStack {
            Label { title } icon: { Image(systemName: systemImage) }
            Spacer(minLength: 0)
            if let count {
                Text(count, format: .number)
                    .font(Typography.mono(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .accessibilityLabel(Text("\(count) da sistemare"))
            }
        }
        .foregroundStyle(prominence == .increased ? Palette.ink : Palette.textPrimary)
    }
}
