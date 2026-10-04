import SwiftUI

/// The MCP servers `claude` loads in the Progetto, as last seen, each with its status; the ones waiting for a login
/// with Accedi and Controlla (spec 20, Server MCP and Da sistemare).
struct MCPServerList: View {
    let servers: [ClaudeConfiguration.MCPServer]
    let catalog: PluginCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            ForEach(servers, id: \.name) { server in
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                        Text(verbatim: server.name)
                            .font(Typography.body(size: 13, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)
                        if let source = server.source {
                            Text(verbatim: source)
                                .font(Typography.mono(size: 11))
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Text(server.statusTitle)
                            .foregroundStyle(server.hasFailed || server.needsAuthentication ? Palette.danger : Palette.textSecondary)
                    }
                    if let error = server.error {
                        Text(verbatim: error)
                            .foregroundStyle(Palette.textSecondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if server.needsAuthentication {
                        MCPLoginBox(server: server.name,
                                    command: MCPLogin.commandLine(for: server.name, in: catalog.followedProject)) {
                            try await catalog.logIn(to: server.name)
                        } check: {
                            await catalog.checkServers()
                        }
                    }
                }
                .font(Typography.body(size: 12))
                .padding(Spacing.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: .rect(cornerRadius: 8))
            }
        }
    }
}
