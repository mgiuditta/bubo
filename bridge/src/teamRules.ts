import type { Options } from "@anthropic-ai/claude-agent-sdk";

// Le Risorse di squadra in vigore nel Progetto (ADR 0009), calcolate in Swift da `.bubo/regole.json` e dalle
// accettazioni: le `allow` sono già solo quelle accettate, `deny` e `ask` valgono subito.
export type TeamRules = { allow: string[]; deny: string[]; ask: string[] };

function strings(value: unknown): string[] {
  return Array.isArray(value) && value.every((rule) => typeof rule === "string") ? value : [];
}

export function teamRules(requested: unknown): TeamRules {
  const object = typeof requested === "object" && requested !== null ? requested as Record<string, unknown> : {};
  return { allow: strings(object.allow), deny: strings(object.deny), ask: strings(object.ask) };
}

// Regole di sessione della `query()`: `allow` come `allowedTools` (destinazione `cliArg`), `deny` come
// `disallowedTools`; `ask` non ha un'opzione sua e passa dalle impostazioni di flag (`--settings`).
export function teamRuleOptions(rules: TeamRules, allowed: string[]): Pick<Options, "allowedTools" | "disallowedTools" | "settings"> {
  return {
    allowedTools: [...allowed, ...rules.allow],
    ...(rules.deny.length > 0 ? { disallowedTools: rules.deny } : {}),
    ...(rules.ask.length > 0 ? { settings: { permissions: { ask: rules.ask } } } : {}),
  };
}
