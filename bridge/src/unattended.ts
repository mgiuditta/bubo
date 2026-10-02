import type {
  Options, PermissionRequestHookInput, PermissionUpdate, PreToolUseHookInput, SDKPermissionDenial, SDKPermissionDeniedMessage,
} from "@anthropic-ai/claude-agent-sdk";
import { clean, raw } from "./permission";

// Il turno di un'Esecuzione di un'Automazione: nessuno davanti a rispondere alle Richieste di permesso (spec 19).
// Decidono il cancello di Bubo, le Regole del Progetto, quelle dell'Automazione e la modalità; il resto è negato e
// finisce nel resoconto dei dinieghi.

/** Le Regole "in questa Automazione", in forma `Tool(contenuto)`: valgono solo in questo turno. */
export type Unattended = { rules: string[] };

/** Una regola come la scrive `claude`: il nome dello strumento, e il contenuto tra parentesi se c'è. */
const rulePattern = /^[A-Za-z0-9_-]+(\(.+\))?$/s;

/** Il turno senza nessuno davanti chiesto da Bubo; `undefined` per un turno normale. Solo regole ben formate. */
export function unattendedOf(requested: unknown): Unattended | undefined {
  if (typeof requested !== "object" || requested === null) return undefined;
  const rules = (requested as { rules?: unknown }).rules;
  const list = Array.isArray(rules) ? rules : [];
  return {
    rules: list.filter((rule): rule is string => typeof rule === "string" && rule.length <= 4000 && rulePattern.test(rule)
                        && !/[\x00-\x1f\x7f]/.test(rule)),
  };
}

/**
 * Le opzioni della `query()` di un turno senza nessuno davanti: `permissionPrompts: 'none'`, così nessuna chiamata
 * resta in attesa oltre il turno, e le Regole dell'Automazione in coda ad `allowedTools`, regole di sessione
 * (`cliArg`) che non toccano mai i settings. Nessun `canUseTool`: con `'none'` non verrebbe chiamato.
 */
export function unattendedOptions(base: Pick<Options, "allowedTools">, turn: Unattended): Partial<Options> {
  return { permissionPrompts: "none", allowedTools: [...(base.allowedTools ?? []), ...turn.rules], canUseTool: undefined };
}

/** Il contenuto di una regola con le parentesi e le barre protette, come lo scrive `claude`. */
function escaped(content: string): string {
  return content.replace(/\\/g, "\\\\").replace(/\(/g, "\\(").replace(/\)/g, "\\)");
}

/**
 * Le regole `Tool(contenuto)` che `claude` propone con una Richiesta (`permission_suggestions`), così come arrivano:
 * solo `addRules` con `allow`. Modalità, cartelle, rimozioni e dinieghi non diventano mai una Regola dell'Automazione.
 */
export function suggestedRules(updates: PermissionUpdate[] | undefined): string[] {
  const rules = (updates ?? []).flatMap((update) =>
    update.type === "addRules" && update.behavior === "allow" ? update.rules : []);
  return [...new Set(rules.map((rule) => rule.ruleContent ? `${rule.toolName}(${escaped(rule.ruleContent)})` : rule.toolName))];
}

/** Un'azione negata nel turno, per il resoconto: il Livello di rischio lo dà Bubo da strumento, comando e percorso. */
export type Denial = {
  toolUseID: string;
  tool: string;
  command?: string;
  path?: string;
  url?: string;
  /** Il tipo del subagent che ha chiamato lo strumento, se non è il filo principale. */
  agent?: string;
  /** Le regole proposte da `claude` per consentire l'azione, già in forma `Tool(contenuto)`. */
  suggestions: string[];
  /** Chi ha negato: il cancello di Bubo o `claude` (regole, modalità, nessuno a cui chiedere). */
  source: "gate" | "sdk";
};

/** L'input in JSON con le chiavi ordinate: lega i `suggestions` della Richiesta, che non ha `tool_use_id`, al diniego. */
function stable(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  if (typeof value === "object" && value !== null) {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stable((value as Record<string, unknown>)[key])}`).join(",")}}`;
  }
  return JSON.stringify(value) ?? "null";
}

function keyOf(tool: string, input: unknown): string {
  return `${tool}\u0000${stable(input ?? {})}`;
}

function subjectOf(input: unknown): Pick<Denial, "command" | "path" | "url"> {
  const fields = (typeof input === "object" && input !== null ? input : {}) as Record<string, unknown>;
  return { command: raw(fields.command), path: raw(fields.file_path ?? fields.notebook_path ?? fields.path), url: raw(fields.url) };
}

/**
 * I dinieghi di un turno senza nessuno davanti, da quattro fonti: il cancello (hook `PreToolUse`), l'hook
 * `PermissionRequest` (solo i `suggestions`), `system/permission_denied` e `result.permission_denials`, la fonte
 * autorevole. Uno per `tool_use_id`; il cancello vince sull'SDK.
 */
export class Denials {
  private readonly found = new Map<string, Denial & { key?: string }>();
  private readonly suggested = new Map<string, string[]>();

  /** Il cancello di Bubo ha negato la chiamata. */
  gate(input: PreToolUseHookInput) {
    this.found.set(input.tool_use_id, {
      toolUseID: input.tool_use_id, tool: clean(input.tool_name) ?? "", ...subjectOf(input.tool_input),
      agent: clean(input.agent_type), suggestions: [], source: "gate", key: keyOf(input.tool_name, input.tool_input),
    });
  }

  /** `claude` voleva chiedere: con `'none'` nega subito, ma prima propone le regole che la consentirebbero. */
  requested(input: PermissionRequestHookInput) {
    const rules = suggestedRules(input.permission_suggestions);
    if (rules.length > 0) this.suggested.set(keyOf(input.tool_name, input.tool_input), rules);
  }

  /** `claude` ha negato senza chiedere: l'avviso arriva prima del `result`, senza l'input. */
  denied(message: SDKPermissionDeniedMessage) {
    if (this.found.has(message.tool_use_id)) return;
    this.found.set(message.tool_use_id, {
      toolUseID: message.tool_use_id, tool: clean(message.tool_name) ?? "", suggestions: [], source: "sdk",
    });
  }

  /** I dinieghi del `result`, con l'input; poi tutti i dinieghi del turno, con i loro `suggestions`. */
  result(denials: SDKPermissionDenial[] = []): Denial[] {
    for (const denial of denials) {
      const known = this.found.get(denial.tool_use_id);
      if (known?.source === "gate") continue;
      this.found.set(denial.tool_use_id, {
        ...known, toolUseID: denial.tool_use_id, tool: clean(denial.tool_name) ?? "", ...subjectOf(denial.tool_input),
        suggestions: [], source: "sdk", key: keyOf(denial.tool_name, denial.tool_input),
      });
    }
    return [...this.found.values()].map(({ key, ...denial }) => ({
      ...denial, suggestions: key ? this.suggested.get(key) ?? [] : [],
    }));
  }
}
