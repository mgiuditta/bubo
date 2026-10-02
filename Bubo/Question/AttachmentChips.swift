import SwiftUI

/// The Allegati in the prompt, one chip each, with the button that takes it out (spec 09, Trascinamento sull'Orb); or
/// the Allegati about to go to another provider, each chip saying "allegato → <fornitore>".
struct AttachmentChips: View {
    let attachments: [Allegato]
    /// The provider the Allegati would go to, named in each chip; `nil` in the prompt.
    var recipient: String?
    /// Called with the Allegato whose chip asks to take it out; no button when `nil`.
    let remove: ((Allegato) -> Void)?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.xxSmall) {
                ForEach(attachments, id: \.self) { allegato in
                    chip(for: allegato)
                }
            }
        }
        .scrollIndicators(.never)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Allegati")
        .accessibilityIdentifier("question.attachments")
    }

    private func chip(for allegato: Allegato) -> some View {
        HStack(spacing: Spacing.xxSmall) {
            Label {
                Text(verbatim: recipient.map { "\(allegato.name) → \($0)" } ?? allegato.name)
                    .foregroundStyle(Palette.textPrimary)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: Self.symbol(for: allegato.kind))
                    .foregroundStyle(Palette.textSecondary)
            }
            .help(allegato.path?.path(percentEncoded: false) ?? allegato.name)
            if let remove {
                Button("Togli \(allegato.name)", systemImage: "xmark") {
                    remove(allegato)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(Palette.textSecondary)
                .help("Togli l'allegato")
            }
        }
        .font(Typography.body(size: 12))
        .lineLimit(1)
        .frame(maxWidth: 200)
        .padding(.horizontal, Spacing.xSmall)
        .padding(.vertical, Spacing.xxSmall)
        .background(Palette.surface, in: .capsule)
        .overlay { Capsule().strokeBorder(Palette.line) }
    }

    /// The symbol of an Allegato of `kind`.
    private static func symbol(for kind: Allegato.Kind) -> String {
        switch kind {
        case .text: "text.quote"
        case .file: "doc"
        case .folder: "folder"
        case .image: "photo"
        }
    }
}

#Preview {
    AttachmentChips(attachments: [
        Allegato(fileAt: URL(filePath: "/tmp")),
        Allegato(name: "Nota", text: "Testo trascinato"),
    ]) { _ in }
    .padding()
}
