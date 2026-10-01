import SwiftUI

/// The visore: the file in read-only with its line numbers and syntax, at the line it was opened on, and "Apri
/// nell'editor" when an editor is installed (spec 15).
struct CodeViewer: View {
    let store: CodeViewerStore
    @AppStorage(EditorLauncher.defaultsKey) private var chosenEditor = ""
    @State private var editor: Editor?

    var body: some View {
        VStack(spacing: 0) {
            bar
            Divider()
                .overlay(Palette.line)
            content
        }
        .foregroundStyle(Palette.textPrimary)
        .background(Palette.ink)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Visore"))
        .task(id: chosenEditor) {
            editor = EditorLauncher.preferred(chosen: chosenEditor)
        }
    }

    @ViewBuilder private var content: some View {
        switch store.content {
        case .loading:
            LoadingLabel("Apro il file…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .unreadable(reason):
            ContentUnavailableView {
                Label {
                    Text(verbatim: reason)
                } icon: {
                    Image(systemName: "doc.questionmark")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .lines(lines):
            CodeLinesView(lines: lines, target: store.location?.line ?? 1)
        }
    }

    private var bar: some View {
        HStack(spacing: Spacing.xSmall) {
            Text(verbatim: store.path)
                .font(Typography.mono(size: 11))
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
            if let line = store.location?.line {
                Text("riga \(line)")
                    .font(Typography.body(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize()
            }
            Spacer(minLength: Spacing.xSmall)
            if let editor, let location = store.location {
                Button("Apri in \(editor.name)", systemImage: "arrow.up.forward.app") {
                    EditorLauncher.open(location, in: store.folder, with: editor)
                }
                .help("Apre il file in \(editor.name) alla riga \(location.line)")
                .fixedSize()
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, Spacing.small)
        // Room for the window's buttons: the bar sits under its transparent title bar.
        .padding(.top, 28)
        .padding(.bottom, Spacing.xSmall)
    }
}
