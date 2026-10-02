import type { Query, SDKControlListPermissionRulesResponse, SDKPermissionRuleEntry } from "@anthropic-ai/claude-agent-sdk";
import { clean } from "./permission";

// Le Regole di permesso di Claude Code che allargano la Sandbox (spec 22): le allow `Edit(…)` e `Write(…)` diventano
// percorsi scrivibili, le allow `WebFetch(domain:…)` domini ammessi. Bubo non le tocca: le mostra.

/** Una Regola che allarga la Sandbox, con la fonte come la dice la CLI (`userSettings`, `projectSettings`…). */
export type SandboxRule = { rule: string; source: string };

/** Il metodo che la CLI ha a runtime ma che `sdk.d.ts` 0.3.286 non dichiara: `sandboxRules.test.ts` lo cerca. */
type ListsPermissionRules = { listPermissionRules?: () => Promise<SDKControlListPermissionRulesResponse> };

/** Se `entry` è una allow in vigore che allarga la Sandbox. */
export function widensSandbox(entry: SDKPermissionRuleEntry): boolean {
  return entry.behavior === "allow" && entry.notInEffect !== true && /^(Edit|Write|WebFetch)\(.+\)$/s.test(entry.rule);
}

/** Le Regole di `conversation` che allargano la Sandbox; errore se la CLI non sa più elencarle. */
export async function sandboxRules(conversation: Query): Promise<SandboxRule[]> {
  const list = (conversation as unknown as ListsPermissionRules).listPermissionRules;
  if (typeof list !== "function") throw new Error("listPermissionRules non disponibile in questo SDK");
  const response = await list.call(conversation);
  const rules = response?.state?.rules;
  if (!Array.isArray(rules)) throw new Error("risposta di listPermissionRules non riconosciuta");
  return rules.filter(widensSandbox).map((entry) => ({ rule: clean(entry.rule) ?? "", source: entry.source }));
}
