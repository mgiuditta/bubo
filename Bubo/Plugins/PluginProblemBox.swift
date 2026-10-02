import AppKit
import SwiftUI

/// A Da sistemare box of the detail: what is wrong, one button, and the command it runs (spec 20, Dettaglio).
struct PluginProblemBox: View {
    let problem: PluginProblem
    let remedy: PluginRemedy
    let catalog: PluginCatalog
    /// Opens the Installa sheet, for a source whose command needs to be read before it runs.
    let install: () -> Void
    @State private var isWorking = false
    @State private var failure: Text?
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Label {
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    title
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                    if case let .installForProject(id, source?) = remedy {
                        Text("Prima aggiunge il marketplace \(id.marketplace) da \(source).")
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Palette.danger)
                    .accessibilityLabel(Text("Errore"))
            }
            HStack(spacing: Spacing.small) {
                Button(action: run) {
                    buttonTitle
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
                if case .disable = remedy, case let .newExecutableCode(id, _) = problem {
                    Button("Ho visto") {
                        Task { await catalog.acknowledgeNewCode(of: id) }
                    }
                    .disabled(isWorking)
                }
                if isWorking {
                    LoadingLabel("Aspetto claude…")
                } else if !remedy.commands.isEmpty {
                    Text(verbatim: commandLine)
                        .font(.caption.monospaced())
                        .foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
            if let failure {
                failure
                    .foregroundStyle(Palette.danger)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(Typography.body(size: 12))
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 8))
    }

    private var title: Text {
        switch problem {
        case .missingProjectPlugin: Text("Plugin di Progetto non installato su questo Mac")
        case let .loadFailed(_, _, message): Text(verbatim: message)
        case let .newExecutableCode(_, components):
            Text("Nuovo codice eseguibile dall'ultimo aggiornamento: \(components.map(\.name).formatted(.list(type: .and)))")
        }
    }

    private var buttonTitle: Text {
        switch remedy {
        case .installForProject: Text("Installa")
        case let .installDependency(id, _): Text("Installa \(id.name)")
        case let .enableDependency(id, _): Text("Attiva \(id.name)")
        case .disable: Text("Disattiva")
        case .copyMessage: didCopy ? Text("Copiato") : Text("Copia l'errore")
        case .acknowledge: Text("Ho visto")
        }
    }

    /// The commands as one would type them, without `--json`, which only Bubo reads.
    private var commandLine: String {
        remedy.commands.map { (["claude"] + $0.arguments.filter { $0 != "--json" }).joined(separator: " ") }
            .joined(separator: " && ")
    }

    private func run() {
        if case let .copyMessage(message) = remedy {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message, forType: .string)
            didCopy = true
            return
        }
        failure = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let result = try await catalog.fix(with: remedy)
                if result.succeeded, case let .newExecutableCode(id, _) = problem {
                    // Turned off or seen: either way the person has looked at it.
                    await catalog.acknowledgeNewCode(of: id)
                } else if result.needsCommandConfirmation {
                    install()
                } else if !result.succeeded {
                    failure = Text(marketplaceFailure: result)
                }
            } catch is CancellationError {
                return
            } catch {
                failure = Text(marketplaceError: error)
            }
        }
    }
}
