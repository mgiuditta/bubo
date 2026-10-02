import SwiftUI

/// A gettone of the Palette: a filter written in the box; clicking it removes it.
struct PaletteFilterChip: View {
    let filter: PaletteFilter
    let remove: () -> Void

    var body: some View {
        Button(action: remove) {
            HStack(spacing: Spacing.xxSmall) {
                title
                Image(systemName: "xmark")
                    .imageScale(.small)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
            }
            .font(Typography.mono(size: 11, weight: .medium))
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, Spacing.xxSmall)
            .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.small))
            .overlay(RoundedRectangle(cornerRadius: CornerRadius.small).strokeBorder(Palette.lineStrong))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Filtro: \(title)"))
        .accessibilityHint(Text("Toglie il filtro"))
        .help(Text("Togli il filtro"))
    }

    private var title: Text {
        switch filter {
        case .project(let name): Text(verbatim: "@\(name)")
        case .days(let days): Text("Ultimi \(days) giorni")
        case .source(.cli): Text("Cronologia CLI")
        case .source(.session): Text("Sessioni")
        case .kind(.commands): Text("Comandi")
        case .kind(.conversations): Text("Conversazioni")
        case .kind(.secondBrain): Text("Secondo cervello")
        }
    }
}
