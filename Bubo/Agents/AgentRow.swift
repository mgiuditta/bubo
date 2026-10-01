import SwiftUI

/// One agent of the Agenti window: name, source, model, description and tools, then its files, with who wins a
/// name conflict and "Apri nell'editor" on each.
struct AgentRow: View {
    let entry: AgentCatalog.Entry
    /// Whether `claude` was asked which agents it loads, so a file it does not list can be pointed out.
    let isLoadedKnown: Bool
    /// The editor files open in; `nil` when there is none, and "Apri nell'editor" does not show.
    let editor: Editor?
    let project: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: entry.name)
                    .font(.headline.monospaced())
                    .textSelection(.enabled)
                Text(source)
                    .foregroundStyle(.secondary)
                Spacer()
                if let model = entry.loaded?.model ?? entry.winner?.model {
                    Text(verbatim: model)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Modello \(model)"))
                }
            }
            Text(verbatim: entry.loaded?.description ?? entry.winner?.description ?? entry.files.first?.description ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if let file = entry.winner ?? entry.files.first {
                if let tools = file.tools {
                    Text("Strumenti: \(tools.formatted(.list(type: .and, width: .narrow)))")
                        .font(.callout)
                } else {
                    Text("Tutti gli strumenti")
                        .font(.callout)
                }
            }
            status
            ForEach(entry.files, id: \.file) { file in
                fileLine(file)
            }
        }
        .padding(.vertical, Spacing.xxSmall)
    }

    /// Where the agent `claude` uses comes from.
    private var source: LocalizedStringResource {
        switch entry.source {
        case .project: "Progetto"
        case .user: "Utente"
        case let .plugin(name): "Plugin \(name)"
        case nil: "Incorporato"
        }
    }

    @ViewBuilder
    private var status: some View {
        if entry.isIgnored {
            Label("Non caricato: il Progetto non è fidato.", systemImage: "lock")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if entry.isUndecided {
            Label("Stesso nome nella stessa cartella: claude ne carica uno secondo l'ordine di lettura, senza una regola.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .symbolRenderingMode(.multicolor)
        } else if isLoadedKnown, entry.loaded == nil {
            Label("Non caricato da claude: controlla il frontmatter del file.", systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .symbolRenderingMode(.multicolor)
        }
    }

    /// A file of the agent: whether it wins, its path and "Apri nell'editor".
    private func fileLine(_ file: AgentFile) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                if entry.hasConflict && !entry.isIgnored {
                    Text(role(of: file))
                        .font(.callout.weight(.semibold))
                }
                Text(verbatim: file.file.path)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(file.file.path)
                    .textSelection(.enabled)
            }
            // The role and the path read as one: "Coperto, /…/revisore.md".
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if let editor {
                Button("Apri in \(editor.name)", systemImage: "arrow.up.forward.app") {
                    EditorLauncher.open(SourceLocation(file: file.file), in: Self.window(for: file.file, in: project),
                                        with: editor)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Apre \(file.file.lastPathComponent) in \(editor.name)")
            }
        }
    }

    /// What a file is in a name conflict.
    private func role(of file: AgentFile) -> LocalizedStringResource {
        if file == entry.winner { return "Vince" }
        if entry.isUndecided, file.folder == entry.files.first?.folder { return "Senza regola" }
        return "Coperto"
    }

    /// The folder the editor's window opens on for `file`: the Progetto when the file is inside it.
    static func window(for file: URL, in project: URL?) -> URL? {
        guard let project, file.standardizedFileURL.path.hasPrefix(project.standardizedFileURL.path + "/") else {
            return nil
        }
        return project
    }
}
