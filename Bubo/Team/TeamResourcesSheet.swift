import os
import SwiftUI

/// The foglio Risorse di squadra for the Regole di permesso of `.bubo/regole.json` (ADR 0009): one row per `allow`,
/// with who last committed it, its Livello di rischio and what changed since the accepted text; Accetta · Ignora.
/// `deny` and `ask` are in Già attive, without buttons.
///
/// Every text comes from the repo: shown verbatim, escaped.
struct TeamResourcesSheet: View {
    let reader: TeamResourceReader
    @Environment(\.dismiss) private var dismiss
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Form {
                Section {
                    Text(verbatim: RepoActivations.escaped(reader.root.appending(path: TeamRules.path).path))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                } header: {
                    Text("Risorse di squadra")
                } footer: {
                    Text("Una regola allow vale per te solo dopo che la accetti. Se cambia anche di un carattere, torna da guardare.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if reader.state == .unreadable {
                    Label("Le regole di squadra non si leggono: non vale nessuna, nemmeno i deny.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.danger)
                }
                if !reader.voci.isEmpty {
                    Section("Regole allow · \(reader.voci.count)") {
                        ForEach(reader.voci) { voce in
                            TeamRuleRow(voce: voce, author: reader.authors[voce.rule]) {
                                perform("Accettata") { try reader.accept(voce) }
                            } ignore: {
                                perform("Ignorata") { try reader.ignore(voce) }
                            }
                        }
                    }
                }
                let rules = reader.rules
                if !rules.deny.isEmpty || !rules.ask.isEmpty {
                    Section {
                        ForEach(rules.deny, id: \.self) { rule in
                            activeRow(rule, title: "Nega")
                        }
                        ForEach(rules.ask, id: \.self) { rule in
                            activeRow(rule, title: "Chiede sempre")
                        }
                    } header: {
                        Text("Già attive")
                    } footer: {
                        Text("Restringono soltanto: valgono subito in tutte le Sessioni del Progetto.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            if failed {
                ErrorNotice("Non riesco a salvare la scelta",
                            remedy: "Controlla lo spazio su disco e i permessi di Application Support, poi riprova.",
                            actionTitle: "Ricarica") {
                    failed = false
                    reader.reload()
                }
            }
            HStack {
                Spacer()
                Button("Chiudi") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 560)
        .frame(maxHeight: 640)
    }

    private func activeRow(_ rule: String, title: LocalizedStringResource) -> some View {
        LabeledContent {
            Text(title)
                .foregroundStyle(.secondary)
        } label: {
            Text(verbatim: RepoActivations.escaped(rule))
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
    }

    /// Records a choice and announces `done` to VoiceOver; a failure shows the notice.
    private func perform(_ done: LocalizedStringResource, _ choice: () throws -> Void) {
        do {
            try choice()
            failed = false
            AccessibilityNotification.Announcement(String(localized: done)).post()
        } catch {
            Logger.team.error("Team rule decision not saved: \(String(describing: error), privacy: .private)")
            failed = true
        }
    }
}

/// One `allow` of the foglio: the rule, its level, who last committed it and the text it replaces, then Accetta ·
/// Ignora; a rule of level 4–5 says so instead of Accetta.
private struct TeamRuleRow: View {
    let voce: TeamResourceReader.Voce
    let author: String?
    let accept: () -> Void
    let ignore: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            details
                .accessibilityElement(children: .combine)
                .accessibilityActions {
                    if voce.isAcceptable && voce.decision != .accepted { Button("Accetta", action: accept) }
                    if voce.decision == nil { Button("Ignora", action: ignore) }
                }
            Spacer(minLength: Spacing.small)
            buttons
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text(verbatim: RepoActivations.escaped(voce.rule))
                .font(.callout.monospaced())
                .textSelection(.enabled)
            if let previous = voce.previous {
                Text("Prima: \(Text(verbatim: RepoActivations.escaped(previous)).font(.callout.monospaced()))")
                    .foregroundStyle(.secondary)
            }
            Text("Livello \(voce.risk.level.rawValue) · \(Text(voce.risk.level.title))")
                .foregroundStyle(voce.isAcceptable ? Palette.textSecondary : Palette.danger)
            if let author {
                Text("Ultimo commit di \(RepoActivations.escaped(author))")
                    .foregroundStyle(.secondary)
            } else {
                Text("Non ancora in un commit")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    @ViewBuilder
    private var buttons: some View {
        switch voce.decision {
        case .accepted:
            Label("Accettata", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Palette.success)
        case .ignored:
            Text("Ignorata")
                .foregroundStyle(.secondary)
            if voce.isAcceptable { Button("Accetta", action: accept) }
        case nil:
            if voce.isAcceptable {
                Button("Accetta", action: accept)
            } else {
                Text("Non si accetta: livello \(voce.risk.level.rawValue)")
                    .foregroundStyle(Palette.danger)
            }
            Button("Ignora", action: ignore)
        }
    }
}
