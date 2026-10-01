import type { SettingSource } from "@anthropic-ai/claude-agent-sdk";

const known: SettingSource[] = ["user", "project", "local"];

// Le fonti le calcola TrustGate in Swift (#266). Mai il default dell'SDK: senza un elenco valido,
// solo le impostazioni dell'utente, quindi niente hook, env o .mcp.json del repo.
export function settingSources(requested: unknown): SettingSource[] {
  const valid = Array.isArray(requested) && requested.length > 0
    && requested.every((source) => known.includes(source));
  return valid ? requested : ["user"];
}
