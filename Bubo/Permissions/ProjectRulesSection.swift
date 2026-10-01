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
    /// The rule waiting for the confirmation of Condividi con la squadra.
    @State private var sharing: String?
    @State private var isConfirmingShare = false
    @State private var sharingFailed = false

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
            if sharingFailed {
                ErrorNotice("Non riesco a scrivere .bubo/regole.json",
                            remedy: "Controlla che il file si legga e che .bubo sia una cartella del Progetto, poi riprova.",
                            actionTitle: "Chiudi") { sharingFailed = false }
            }
        }
        .onAppear(perform: reload)
        .confirmationDialog("Vuoi condividere la regola con la squadra?", isPresented: $isConfirmingShare,
                            presenting: sharing) { rule in
            Button("Aggiungi a .bubo/regole.json") { share(rule) }
        } message: { rule in
            Text("Bubo aggiunge \(RepoActivations.escaped(rule)) a .bubo/regole.json del Progetto. Il commit lo fai tu; chi usa il repo la vede da accettare.")
        }
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
                        Button("Condividi con la squadra…") {
                            sharing = entry.rule
                            isConfirmingShare = true
                        }
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

    /// Condividi con la squadra: writes `rule` in `.bubo/regole.json`, where it shows in the diff.
    private func share(_ rule: String) {
        do {
            try TeamResourceWriter(project: project).share(rule)
            sharingFailed = false
        } catch {
            Logger.team.error("Rule not shared: \(String(describing: error), privacy: .private)")
            sharingFailed = true
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
