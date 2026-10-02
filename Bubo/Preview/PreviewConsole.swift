import SwiftUI

/// The last lines of the page's console, the newest at the bottom; errors and warnings marked by an icon, not only by
/// colour.
struct PreviewConsole: View {
    let lines: [ConsoleLine]

    var body: some View {
        if lines.isEmpty {
            Text("Nessun messaggio nella console")
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(lines) { line in
                        ConsoleLineRow(line: line)
                    }
                }
                .padding(.horizontal, Spacing.small)
                .padding(.vertical, Spacing.xxSmall)
            }
            .defaultScrollAnchor(.bottom)
            .accessibilityLabel(Text("Console"))
        }
    }
}

/// One line of the console, with its level.
private struct ConsoleLineRow: View {
    let line: ConsoleLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xxSmall) {
            switch line.level {
            case .error:
                Image(systemName: "xmark.octagon")
                    .foregroundStyle(Palette.danger)
                    .accessibilityLabel(Text("Errore"))
            case .warning:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityLabel(Text("Avviso"))
            case .log:
                EmptyView()
            }
            Text(verbatim: line.text)
                .font(Typography.mono(size: 11))
                .foregroundStyle(line.level == .log ? Palette.textSecondary : Palette.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
