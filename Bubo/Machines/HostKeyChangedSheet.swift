import AppKit
import SwiftUI

/// A host whose key changed: the key `known_hosts` expects and the one received, and the command that removes the
/// old one. There is no button to go on: the user runs the command in a Terminale after checking the host.
struct HostKeyChangedSheet: View {
    let machine: Machine
    let change: HostKeyChange
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            banner
            Form {
                Section {
                    LabeledContent("Attesa") {
                        if let expected = change.expected {
                            fingerprint(expected)
                        } else {
                            Text("Non trovata in known_hosts")
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Ricevuta") {
                        fingerprint(change.received.fingerprint)
                    }
                } header: {
                    Text(verbatim: "\(machine.address) · \(change.received.type)")
                }
                Section {
                    Text(verbatim: HostKeyGate.removalCommand(for: machine))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                } header: {
                    Text("Se hai cambiato tu la chiave, nel Terminale")
                } footer: {
                    Text("Poi torna qui e verifica di nuovo: Bubo chiederà di confermare la chiave nuova.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Copia comando", action: copyCommand)
                Button("Chiudi") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 520)
    }

    private var banner: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(Palette.danger)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text("La chiave di \(machine.hostname) è cambiata")
                    .font(.headline)
                Text("Può essere un attacco. Bubo non si connette finché la chiave vecchia resta in known_hosts.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .strokeBorder(Palette.danger.opacity(0.4))
        }
        .accessibilityElement(children: .combine)
    }

    private func fingerprint(_ value: String) -> some View {
        Text(verbatim: value)
            .font(.callout.monospaced())
            .textSelection(.enabled)
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(HostKeyGate.removalCommand(for: machine), forType: .string)
    }
}
