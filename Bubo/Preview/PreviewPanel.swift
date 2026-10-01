import SwiftUI
import WebKit

/// The Anteprima of a Sessione: the page at the chosen width, reload, console and Web Inspector. A glass panel next
/// to the terminal in the HUD, or the whole of its own window once detached (spec 15).
struct PreviewPanel: View {
    let store: PreviewStore
    /// Whether the panel fills the detached window instead of sitting in the HUD.
    var isInWindow = false

    var body: some View {
        if let preview = store.shown {
            PreviewPageView(store: store, preview: preview, isInWindow: isInWindow)
        }
    }
}

/// The bar, the page and the console of one Anteprima.
private struct PreviewPageView: View {
    let store: PreviewStore
    @Bindable var preview: PreviewPage
    let isInWindow: Bool
    @State private var showsConsole = false
    /// The system's appearance, which the page reads as `prefers-color-scheme`: the HUD around it is always dark.
    @State private var systemColorScheme = ColorScheme(NSApp.effectiveAppearance)

    var body: some View {
        VStack(spacing: 0) {
            bar
            Divider()
                .overlay(Palette.line)
            page
            if showsConsole {
                Divider()
                    .overlay(Palette.line)
                PreviewConsole(lines: preview.console)
                    .frame(height: 120)
            }
        }
        .foregroundStyle(Palette.textPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Anteprima"))
    }

    @ViewBuilder private var page: some View {
        if preview.untrustedURL != nil {
            ContentUnavailableView {
                Label("Certificato non attendibile", systemImage: "lock.trianglebadge.exclamationmark")
            } description: {
                Text("Bubo non si fida di questo certificato e non apre la pagina. Puoi aprirla nel browser.")
            } actions: {
                Button("Apri nel browser", action: preview.openUntrustedInBrowser)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            WebView(preview.page)
                // The page is the user's, not Bubo's: it follows the system, not the HUD's forced dark.
                .environment(\.colorScheme, systemColorScheme)
                .onReceive(NSApp.publisher(for: \.effectiveAppearance)) { systemColorScheme = ColorScheme($0) }
                .frame(maxWidth: preview.width.points ?? .infinity)
                .frame(maxWidth: .infinity)
                .padding(Spacing.xxSmall)
        }
    }

    private var bar: some View {
        HStack(spacing: Spacing.xxSmall) {
            if !isInWindow {
                Text(verbatim: store.title)
                    .font(Typography.body(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .padding(.trailing, Spacing.xSmall)
            }
            if let url = preview.page.url {
                Text(verbatim: url.absoluteString)
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: Spacing.xSmall)
            if preview.isDrivenByAgent {
                // What the agent does happens in this same page, in plain sight.
                Text("L'agente usa l'anteprima")
                    .font(Typography.body(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Picker("Larghezza", selection: $preview.width) {
                ForEach(PreviewWidth.allCases) { width in
                    Label {
                        Text(width.title)
                    } icon: {
                        Image(systemName: width.systemImage)
                    }
                    .tag(width)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Larghezza della pagina, con lo user agent del dispositivo")
            Button("Ricarica", systemImage: "arrow.clockwise", action: preview.reload)
                .help("Ricarica la pagina dal server")
            Toggle(isOn: $showsConsole) {
                Label("Console", systemImage: "text.alignleft")
            }
            .toggleStyle(.button)
            .help("Mostra i messaggi della console della pagina")
            if isInWindow {
                Button("Riporta nell'HUD", systemImage: "rectangle.bottomhalf.inset.filled") {
                    store.setDetached(false)
                }
                .help("Riporta l'anteprima nell'HUD")
            } else {
                Button("Stacca in una finestra", systemImage: "macwindow.on.rectangle") {
                    store.setDetached(true)
                }
                .help("Sposta l'anteprima in una finestra sua")
                Button("Nascondi l'anteprima", systemImage: "chevron.down", action: store.hide)
                    .help("Nasconde l'anteprima; la pagina resta aperta")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, Spacing.small)
        // Room for the window's buttons when the bar sits under its transparent title bar.
        .padding(.top, isInWindow ? 28 : Spacing.xSmall)
        .padding(.bottom, Spacing.xSmall)
    }
}

private extension ColorScheme {
    /// The color scheme closest to `appearance`.
    init(_ appearance: NSAppearance) {
        self = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }
}
