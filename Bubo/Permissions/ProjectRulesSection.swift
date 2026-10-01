import os
import SwiftUI

/// The Regole di permesso that allow actions in a Progetto, each with where it comes from (#79).
///
/// The Progetto's own rules are changed or revoked with one click each, in the same file the CLI reads; the shared ones
/// and the user's are only listed, since they belong to the repo and to every Progetto.
struct ProjectRulesSection: View {
    /// The Progetto's folder.
    let project: URL
    @State private var entries: [RuleStore.Entry] = []
    @State private var unreadable: [URL] = []
    /// The rule being changed, and its new text.
    @State private var editing: String?
    @State private var draft = ""
    @State private var failed = false

    private var store: RuleStore { RuleStore(project: project) }

    var body: some View {
        Section("Regole di permesso · \(entries.count)") {
            ForEach(unreadable, id: \.self) { file in
                Label {
                    Text("Non riesco a leggere \(file.path): Claude salta le sue regole.")
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.danger)
                        .accessibilityLabel("Errore")
                }
            }
            if entries.isEmpty {
                Text("Nessuna regola: Claude chiede ogni volta.")
                    .foregroundStyle(.secondary)
            }
            ForEach(entries.indices, id: \.self) { index in
                row(entries[index])
            }
            if failed {
                ErrorNotice("Non riesco a cambiare la regola", remedy: "Controlla \(store.file.path), poi riprova.",
                            actionTitle: "Ricarica") {
                    failed = false
                    reload()
                }
            }
        }
        .onAppear(perform: reload)
    }

    @ViewBuilder
    private func row(_ entry: RuleStore.Entry) -> some View {
        if entry.origin == .local, editing == entry.rule {
            HStack {
                TextField("Regola", text: $draft)
                    .font(.callout.monospaced())
                    .onSubmit { change(entry.rule) }
                Button("Annulla") { editing = nil }
                Button("Salva") { change(entry.rule) }
                    .disabled(!ProjectRule.isWellFormed(draft.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        } else {
            LabeledContent {
                HStack {
                    Text(Self.title(of: entry.origin))
                        .foregroundStyle(.secondary)
                    if entry.origin == .local {
                        Button("Modifica") {
                            draft = entry.rule
                            editing = entry.rule
                        }
                        Button("Revoca") { perform { try store.remove(entry.rule) } }
                    }
                }
            } label: {
                Text(verbatim: RepoActivations.escaped(entry.rule))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    /// Where a rule comes from, in a word or two.
    private static func title(of origin: RuleStore.Origin) -> LocalizedStringResource {
        switch origin {
        case .local: "Progetto"
        case .project: "Progetto, condivisa"
        case .user: "Utente"
        }
    }

    private func change(_ rule: String) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ProjectRule.isWellFormed(text) else { return }
        perform { try store.replace(rule, with: text) }
        editing = nil
    }

    private func perform(_ edit: () throws -> Void) {
        do {
            try edit()
            failed = false
        } catch {
            Logger.sessions.error("Rule not changed: \(String(describing: error), privacy: .private)")
            failed = true
        }
        reload()
    }

    private func reload() {
        entries = store.entries
        unreadable = store.unreadableFiles
    }
}
