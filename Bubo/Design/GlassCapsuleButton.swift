import SwiftUI

/// A Liquid Glass capsule with an icon and a label, 32 pt high, for quiet actions such as Impostazioni.
///
/// The capsule grows with larger text instead of clipping it.
struct GlassCapsuleButton: View {
    /// The height of the capsule at the default text size.
    static let height: CGFloat = 32

    private let title: LocalizedStringKey
    private let systemImage: String
    private let action: () -> Void

    /// Creates a capsule that shows `systemImage` beside `title` and runs `action` when clicked.
    init(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.buboInterface)
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Spacing.s)
                .frame(minHeight: Self.height)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

#Preview {
    GlassCapsuleButton("Impostazioni", systemImage: "gearshape") {}
        .padding(Spacing.l)
        .background(Palette.ink)
}
