import os
import SwiftUI

/// Impostazioni › Permessi: every Regola di permesso, ovunque, per Progetto and per Automazione, each with where it
/// comes from and its Livello di rischio (#388).
///
/// Only the rules Bubo writes can be taken away, after a confirmation: a Progetto's own and an Automazione's. The
/// user's settings and the shared ones of a repo are only listed.
struct PermissionsSettingsView: View {
    @Environment(SessionStore.self) private var sessions: SessionStore?
    /// The rules on disk; `nil` until they are read.
    @State private var listing: RuleListing?
    /// Bumped after each removal, so the files are read again.
    @State private var revision = 0
    /// The rule waiting for the confirmation, with its group.
    @State private var removal: Removal?
    @State private var isConfirmingRemoval = false
    @State private var failed = false

    var body: some View {
        Form {
            if let listing {
                ForEach(listing.unreadableFiles, id: \.self) { file in
                    Label {
                        Text("Non riesco a leggere \(file.path): Claude salta le sue regole.")
                            .textSelection(.enabled)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.danger)
                            .accessibilityLabel("Errore")
                    }
                }
                if failed {
                    ErrorNotice("Non riesco a togliere la regola",
                                remedy: "Controlla .claude/settings.local.json del Progetto, poi riprova.",
                                actionTitle: "Chiudi") { failed = false }
                }
                ForEach(listing.groups) { group in
                    Section {
                        if group.items.isEmpty {
                            Text("Nessuna regola: Claude chiede ogni volta.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(group.items) { item in
                            RuleListingRow(item: item) {
                                removal = Removal(item: item, scope: group.scope)
                                isConfirmingRemoval = true
                            }
                        }
                    } header: {
                        Text(Self.title(of: group.scope))
                    } footer: {
                        if group.scope == .everywhere {
                            Text("Valgono in ogni Progetto, anche nel terminale. Bubo le legge da ~/.claude/settings.json e non cambia il file.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                LoadingLabel("Leggo le regole…")
            }
        }
        .formStyle(.grouped)
        .task(id: sources) {
            listing = await Self.list(sources)
        }
        .confirmationDialog(Text("Vuoi togliere la regola \(RepoActivations.escaped(removal?.item.rule ?? ""))?"),
                            isPresented: $isConfirmingRemoval, presenting: removal) { removal in
            Button("Togli", role: .destructive) { remove(removal) }
        } message: { removal in
            Text(Self.consequence(of: removal.scope))
        }
    }

    /// What the listing is read from: it is read again whenever one of them changes.
    private var sources: Sources {
        Sources(projects: sessions?.knownProjects ?? [],
                automations: sessions?.automations.automations.map(RuleListing.AutomationRules.init) ?? [],
                revision: revision)
    }

    private func remove(_ removal: Removal) {
        switch removal.scope {
        case let .project(root):
            do {
                try RuleStore(project: root).remove(removal.item.rule)
                failed = false
            } catch {
                Logger.sessions.error("Rule not removed: \(String(describing: error), privacy: .private)")
                failed = true
            }
            revision += 1
        case let .automation(id, _):
            // The store is observed: the listing follows by itself.
            sessions?.automations.revoke(removal.item.rule, in: id)
        case .everywhere:
            break
        }
    }

    /// The header of a group of rules.
    private static func title(of scope: RuleListing.Scope) -> String {
        switch scope {
        case .everywhere: String(localized: "Ovunque")
        case let .project(root): String(localized: "Progetto \(root.lastPathComponent)")
        case let .automation(_, name): String(localized: "Automazione \(name)")
        }
    }

    /// What changes once the rule is gone.
    private static func consequence(of scope: RuleListing.Scope) -> String {
        switch scope {
        case let .automation(_, name): String(localized: "Dalla prossima Esecuzione, l'Automazione \(name) non potrà più farlo.")
        default: String(localized: "Bubo la toglie da .claude/settings.local.json: Claude torna a chiedere, anche nel terminale.")
        }
    }

    @concurrent
    private static func list(_ sources: Sources) async -> RuleListing {
        RuleListing(projects: sources.projects, automations: sources.automations)
    }
}

/// The places Impostazioni › Permessi reads the rules from.
private struct Sources: Hashable, Sendable {
    let projects: [URL]
    let automations: [RuleListing.AutomationRules]
    let revision: Int
}

/// A rule waiting for the confirmation of its removal.
private struct Removal {
    let item: RuleListing.Item
    let scope: RuleListing.Scope
}
