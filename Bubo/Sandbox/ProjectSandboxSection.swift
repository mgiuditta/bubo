import os
import SwiftUI

/// The Sandbox of a Progetto in its settings (spec 22): the switch, off by default; the hosts and folders the user let
/// in, removable; the preset, read only; and the Regole di Claude Code that widen it. Every change counts from the next
/// turn.
struct ProjectSandboxSection: View {
    /// The Progetto's folder.
    let project: URL
    let store: SandboxStore
    /// Reads the Regole di permesso of `claude` in a folder that widen its Sandbox.
    var readRules: (URL) async throws -> [SandboxWideningRule] = { _ in [] }
    @State private var isOn = false
    @State private var rules: [SandboxWideningRule]?
    @State private var rulesFailed = false

    var body: some View {
        let allowances = store.allowances(in: project)
        Section("Sandbox") {
            Toggle("Esegui i comandi di Claude in Sandbox", isOn: $isOn)
            Text("I comandi di Claude scrivono solo nella cartella della Sessione, nelle cartelle temporanee e nelle cache dei pacchetti, raggiungono solo i registri dei pacchetti e non leggono ~/.ssh, ~/.aws, ~/.gnupg e ~/.netrc. Un host nuovo diventa una Richiesta. Se la Sandbox non parte, la Sessione non parte. Il terminale e i server non sono in Sandbox. Vale dal prossimo turno.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .onAppear { isOn = store.isEnabled(in: project) }
        .onChange(of: isOn) { _, isOn in store.setEnabled(isOn, in: project) }

        Section("Consentiti in questo Progetto · \(allowances.domains.count + allowances.folders.count)") {
            if allowances.domains.isEmpty && allowances.folders.isEmpty {
                Text("Nessun host né cartella: li aggiungi da una Richiesta di rete o da un blocco della Sandbox.")
                    .foregroundStyle(.secondary)
            }
            ForEach(allowances.domains, id: \.self) { host in
                allowanceRow(host, kind: "Host") { store.remove(.domain(host), in: project) }
            }
            ForEach(allowances.folders, id: \.self) { folder in
                allowanceRow(folder, kind: "Cartella") { store.remove(.folder(folder), in: project) }
            }
        }

        Section("Sempre consentiti") {
            DisclosureGroup("Registri dei pacchetti e cache") {
                ForEach(SandboxPolicy.presetDomains, id: \.self) { host in
                    LabeledContent("Host") { Text(verbatim: host).font(.callout.monospaced()) }
                }
                ForEach(SandboxPolicy.presetFolders, id: \.self) { folder in
                    LabeledContent("Cartella") { Text(verbatim: "~/\(folder)").font(.callout.monospaced()) }
                }
                LabeledContent("Cartella") { Text("Temporanea e cache dell'utente") }
            }
        }

        Section("Regole di Claude Code che allargano la Sandbox") {
            if let rules {
                if rules.isEmpty {
                    Text("Nessuna Regola Edit, Write o WebFetch nelle impostazioni di Claude.")
                        .foregroundStyle(.secondary)
                }
                ForEach(rules, id: \.self) { rule in
                    LabeledContent {
                        Text(rule.sourceTitle).foregroundStyle(.secondary)
                    } label: {
                        Text(verbatim: RepoActivations.escaped(rule.rule))
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                }
            } else if rulesFailed {
                Text("Non riesco a leggere le Regole di Claude Code.")
                    .foregroundStyle(.secondary)
            } else {
                LoadingLabel("Leggo le Regole di Claude Code…")
            }
            Text("Bubo le mostra soltanto: allargano anche la Sandbox dei comandi e si cambiano nelle impostazioni di Claude. Edit e Write restano comunque nella cartella della Sessione e nelle cartelle consentite.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .task(id: project) { await loadRules() }
    }

    private func allowanceRow(_ value: String, kind: LocalizedStringResource, remove: @escaping () -> Void) -> some View {
        LabeledContent {
            Button("Togli", action: remove)
                .accessibilityLabel(Text("Togli \(RepoActivations.escaped(value))"))
        } label: {
            Text(kind)
                .foregroundStyle(.secondary)
            Text(verbatim: RepoActivations.escaped(value))
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
    }

    private func loadRules() async {
        do {
            rules = try await readRules(project)
        } catch is CancellationError {
        } catch {
            Logger.agent.error("Sandbox rules not read: \(String(describing: error), privacy: .private)")
            rulesFailed = true
        }
    }
}
