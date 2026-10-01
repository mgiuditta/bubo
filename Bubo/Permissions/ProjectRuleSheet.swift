import os
import SwiftUI

/// Sempre in questo Progetto (#79): the rule exactly as it will be written, the file it goes in and what it covers,
/// before anything is saved.
///
/// In a Progetto that is not trusted the trust dialog comes first: `claude` would not read the rule there.
struct ProjectRuleSheet: View {
    let rule: ProjectRule
    /// The Progetto's folder.
    let project: URL
    /// Saves the rule and allows the call.
    let save: () throws -> Void
    var gate = TrustGate()
    @Environment(\.dismiss) private var dismiss
    @State private var isAskingTrust = false
    @State private var failed = false

    private var file: URL { RuleStore(project: project).file }

    var body: some View {
        if isAskingTrust {
            TrustSheet(folder: project, activations: RepoActivations(folder: project), start: { isTrusted in
                // The trust dialog closes the sheet; a failure leaves the Richiesta waiting, to answer again.
                if isTrusted { try? commit() }
            }, gate: gate)
        } else {
            form
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Form {
                Section {
                    LabeledContent("Regola") {
                        Text(verbatim: RepoActivations.escaped(rule.text))
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("File") {
                        Text(verbatim: file.path)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Consente") {
                        Text(coverage)
                    }
                } header: {
                    Text("Sempre in questo Progetto")
                } footer: {
                    Text("Vale in tutte le Sessioni del Progetto, anche nelle copie isolate, e in claude dal Terminale. La revochi da Configurazione di Claude.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            if failed {
                ErrorNotice("Non riesco a salvare la regola", remedy: "Controlla \(file.path), poi riprova.",
                            actionTitle: "Riprova", action: confirm)
            }
            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                // No default shortcut: Return must never save a lasting permission by accident.
                Button("Salva regola", action: confirm)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 520)
    }

    /// The calls the rule allows, from now on.
    private var coverage: LocalizedStringKey {
        switch rule.scope {
        case .command: "Solo questo comando, scritto esattamente così."
        case let .site(host): "Ogni pagina di \(host)."
        case let .tool(name): "Ogni chiamata allo strumento \(name)."
        }
    }

    private func confirm() {
        guard gate.isTrusted(project) else {
            isAskingTrust = true
            return
        }
        do {
            try commit()
            dismiss()
        } catch {
            failed = true
        }
    }

    private func commit() throws {
        do {
            try save()
        } catch {
            Logger.sessions.error("Rule not saved: \(String(describing: error), privacy: .private)")
            throw error
        }
    }
}

#Preview {
    ProjectRuleSheet(rule: ProjectRule(PermissionRequest(id: "1", tool: "Bash", command: "npm test"))!,
                     project: URL(filePath: "/Users/u/Sviluppo/repo"), save: {})
}
