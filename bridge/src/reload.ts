import type { SDKControlReloadPluginsResponse } from "@anthropic-ai/claude-agent-sdk";

// Ricarica plugin di un turno in corso (#212). La prima volta si chiede di fermarsi se il ricaricamento invalida la
// cache del prompt (`held`); "Ricarica comunque" richiama senza l'opzione, e il ricaricamento si applica sempre.
export function reloadOptions(force: unknown): { holdOnCacheImpact: true } | undefined {
  return force === true ? undefined : { holdOnCacheImpact: true };
}

// Che cosa cambierebbe applicando un ricaricamento fermato; i nomi dei server vengono dai plugin, quindi solo stringhe.
export type CacheImpact = { added: string[]; removed: string[]; lsp?: string };

// L'esito per Bubo: i comandi che il turno ha ora (o avrebbe tenuto, se `held`), e l'impatto sulla cache.
export type PluginReload = { commands: string[]; held: boolean; cacheImpact?: CacheImpact };

export function pluginReload(response: SDKControlReloadPluginsResponse): PluginReload {
  const impact = response.held === true ? response.cache_impact : undefined;
  const names = (list: unknown) => Array.isArray(list) ? list.filter((name): name is string => typeof name === "string") : [];
  return {
    commands: response.commands.map((command) => command.name),
    held: response.held === true,
    ...(impact && {
      cacheImpact: {
        added: names(impact.mcp_servers_added),
        removed: names(impact.mcp_servers_removed),
        ...(impact.lsp_tool_change && { lsp: impact.lsp_tool_change }),
      },
    }),
  };
}
