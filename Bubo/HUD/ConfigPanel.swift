import os
import SwiftUI

/// The configuration of Claude in a Progetto, as `claude` loads it: CLAUDE.md, server MCP with status and source,
/// plugins with their errors, skills (spec 04); and its Regole di permesso, read from the files (#79).
///
/// Apart from the rules, nothing is read from the files: `claude` reports it through the bridge. In a Progetto that is not trusted only
/// the user's configuration is loaded, and the panel says so instead of loading the Progetto's to show it.
struct ConfigPanel: View {
    /// The Progetto's folder.
    let project: URL
    /// Whether the Progetto runs its Sessioni's commands in the Sandbox.
    let sandbox: SandboxStore
    /// Reads the configuration `claude` loads in a folder.
    let read: (URL) async throws -> ClaudeConfiguration
    /// Reads the Regole di permesso of `claude` in a folder that widen its Sandbox.
    var readSandboxRules: (URL) async throws -> [SandboxWideningRule] = { _ in [] }
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: ClaudeConfiguration?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            if let configuration {
                ConfigurationForm(project: project, configuration: configuration, sandbox: sandbox,
                                  readSandboxRules: readSandboxRules)
            } else if failed {
                ErrorNotice("Non riesco a leggere la configurazione di Claude",
                            remedy: "Controlla che la CLI claude funzioni nel Terminale, poi riprova.",
                            actionTitle: "Riprova") { attempt += 1 }
                Spacer()
            } else {
                LoadingLabel("Leggo la configurazione di Claude…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Spacer()
                Button("Chiudi") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 560, height: 600)
        .task(id: attempt) { await load() }
    }

    private func load() async {
        failed = false
        let state = Signposts.signposter.beginInterval("Configurazione di Claude", id: Signposts.signposter.makeSignpostID())
        defer { Signposts.signposter.endInterval("Configurazione di Claude", state) }
        do {
            configuration = try await read(project)
        } catch is CancellationError {
        } catch {
            Logger.agent.error("Configuration not read: \(String(describing: error), privacy: .private)")
            failed = true
        }
    }
}

/// The sections of the panel, once `claude` reported its configuration.
private struct ConfigurationForm: View {
    let project: URL
    let configuration: ClaudeConfiguration
    let sandbox: SandboxStore
    let readSandboxRules: (URL) async throws -> [SandboxWideningRule]
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section {
                Text(verbatim: project.path)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                if !configuration.loadsProject {
                    Label("Progetto non fidato: Claude carica solo la tua configurazione, non quella del Progetto.",
                          systemImage: "lock")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Configurazione di Claude")
            }

            ProjectSandboxSection(project: project, store: sandbox, readRules: readSandboxRules)

            ProjectRulesSection(project: project)
            TeamResourcesSection(project: project)

            Section("CLAUDE.md · \(configuration.instructions.count)") {
                if configuration.instructions.isEmpty {
                    Text("Nessun CLAUDE.md caricato.")
                        .foregroundStyle(.secondary)
                }
                ForEach(configuration.instructions, id: \.path) { file in
                    LabeledContent {
                        Text(file.level)
                    } label: {
                        Text(verbatim: file.path)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Server MCP · \(configuration.mcpServers.count)") {
                if configuration.mcpServers.isEmpty {
                    Text("Nessun server MCP.")
                        .foregroundStyle(.secondary)
                }
                ForEach(configuration.mcpServers, id: \.name) { server in
                    MCPServerRow(server: server)
                }
            }

            Section("Plugin · \(configuration.plugins.count)") {
                ForEach(configuration.pluginErrors, id: \.plugin) { failure in
                    Label {
                        Text(verbatim: failure.plugin).font(.callout.monospaced())
                        Text(verbatim: failure.message).textSelection(.enabled)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.danger)
                            .accessibilityLabel("Errore")
                    }
                }
                if !configuration.pluginErrors.isEmpty {
                    Button("Sistema nella finestra Plugin") {
                        PluginsWindowRoute.shared.showProblems(of: project)
                        openWindow(id: PluginsWindow.windowID)
                    }
                }
                if configuration.plugins.isEmpty {
                    Text("Nessun plugin.")
                        .foregroundStyle(.secondary)
                }
                ForEach(configuration.plugins, id: \.name) { plugin in
                    LabeledContent {
                        Text(verbatim: plugin.version ?? "")
                    } label: {
                        Text(verbatim: plugin.name)
                    }
                }
            }

            Section("Skill · \(configuration.skills.count)") {
                ForEach(configuration.skills, id: \.self) { skill in
                    Text(verbatim: skill)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// A server MCP: name and source, its status, and what to do when it is not working.
private struct MCPServerRow: View {
    let server: ClaudeConfiguration.MCPServer

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            LabeledContent {
                Text(status)
                    .foregroundStyle(server.hasFailed || server.needsAuthentication ? Palette.danger : Color.secondary)
            } label: {
                Text(verbatim: server.name)
                if let source = server.source {
                    Text(verbatim: source)
                        .font(.callout.monospaced())
                }
            }
            if let error = server.error {
                Text(verbatim: error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            // The SDK cannot complete an OAuth login: only the CLI can.
            if server.needsAuthentication {
                Text("Per accedere, apri claude nel Terminale, scrivi /mcp e scegli \(server.name).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var status: LocalizedStringResource {
        switch server.status {
        case "connected": "Connesso"
        case "failed": "Non funziona"
        case "needs-auth": "Accesso richiesto"
        case "pending": "In connessione"
        case "disabled": "Disattivato"
        default: LocalizedStringResource(stringLiteral: server.status)
        }
    }
}

#Preview {
    ConfigPanel(project: URL(filePath: "/Users/u/Sviluppo/bubo"), sandbox: SandboxStore()) { _ in
        ClaudeConfiguration(
            skills: ["swiftui-pro", "code-review"],
            plugins: [.init(name: "figma", version: "1.2.0")],
            pluginErrors: [.init(plugin: "rotto@mercato", message: "Manca la dipendenza base@mercato")],
            mcpServers: [.init(name: "linear", status: "needs-auth", source: "claudeai", error: nil),
                         .init(name: "db", status: "failed", source: "project", error: "Connection closed")],
            instructions: [.init(path: "/Users/u/Sviluppo/bubo/CLAUDE.md", type: "Project")])
    }
}
