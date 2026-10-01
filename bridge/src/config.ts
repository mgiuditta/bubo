// La configurazione di Claude come la carica `claude`: Bubo la mostra, non la legge mai dai file.
import type { McpServerStatus, SDKSystemMessage } from "@anthropic-ai/claude-agent-sdk";

export type Instructions = { path: string; type: string };

export type Configuration = {
  skills: string[];
  plugins: { name: string; version?: string }[];
  pluginErrors: { plugin: string; message: string }[];
  mcpServers: { name: string; status: string; source?: string; error?: string }[];
  instructions: Instructions[];
};

/**
 * Da `init`, `mcpServerStatus()` e dai CLAUDE.md caricati (`getContextUsage().memoryFiles` e hook
 * `InstructionsLoaded`, senza doppioni). Lo stato dei server MCP viene da `mcpServerStatus()`, più
 * recente di `init`; un server che vi manca resta con lo stato di `init`.
 */
export function configuration(init: SDKSystemMessage, servers: McpServerStatus[], instructions: Instructions[]): Configuration {
  const status = new Map(servers.map((server) => [server.name, server]));
  const seen = new Set<string>();
  return {
    skills: init.skills,
    plugins: init.plugins.map(({ name, version }) => ({ name, ...(version && { version }) })),
    pluginErrors: (init.plugin_errors ?? []).map(({ plugin, message }) => ({ plugin, message })),
    mcpServers: init.mcp_servers.map(({ name, status: initial, source }) => {
      const current = status.get(name);
      const origin = current?.source ?? current?.scope ?? source;
      return {
        name,
        status: current?.status ?? initial,
        ...(origin && { source: origin }),
        ...(current?.error && { error: current.error }),
      };
    }),
    instructions: instructions.filter(({ path }) => !seen.has(path) && seen.add(path)),
  };
}
