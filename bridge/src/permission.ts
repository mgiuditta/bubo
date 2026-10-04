import type { CanUseTool, HookInput, PermissionResult, PermissionUpdate } from "@anthropic-ai/claude-agent-sdk";

// La Richiesta di permesso che il ponte manda a Bubo: solo stringhe e booleani, già ripuliti.
// Bubo ne ricava il Livello di rischio da strumento, comando e percorso; il resto è testo da mostrare.
export type PermissionRequest = {
  type: "permission";
  request: string;
  tool: string;
  command?: string;
  path?: string;
  url?: string;
  host?: string;
  title?: string;
  description?: string;
  blockedPath?: string;
  mcpSource?: string;
  fromSubagent?: boolean;
  /** Il nome del subagent che chiede, da `SubagentStart`; assente per il filo principale o se non si sa. */
  agent?: string;
  defaultToNo?: boolean;
  suppressAlwaysAllowRule?: boolean;
  outsideSandbox?: boolean;
};

type Options = Parameters<CanUseTool>[2];

const textLength = 4000;

// Testo scritto da `claude`, da un server MCP o dal modello: niente sequenze ANSI né caratteri di controllo.
export function clean(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const text = value.replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "").replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "");
  return text.length > textLength ? text.slice(0, textLength - 1) + "…" : text;
}

// Comando, percorso e URL vanno a Bubo interi e senza ritocchi: approvato, gira esattamente questo input,
// quindi l'utente deve poterlo vedere tutto. Bubo lo mostra con l'escape; oltre `subjectLength` si nega.
export const subjectLength = 100_000;

export function raw(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

// Un soggetto troppo lungo per essere letto prima di approvarlo.
export function isTooLong(request: PermissionRequest): boolean {
  return [request.command, request.path, request.url, request.host].some((text) => (text?.length ?? 0) > subjectLength);
}

export function permissionRequest(request: string, toolName: string, input: Record<string, unknown>,
                                  options: Options, subagents?: Subagents): PermissionRequest {
  return {
    type: "permission",
    request,
    tool: clean(toolName) ?? "",
    command: raw(input.command),
    path: raw(input.file_path ?? input.notebook_path ?? input.path),
    url: raw(input.url),
    host: raw(input.host),
    title: clean(options.title),
    description: clean(options.description),
    blockedPath: clean(options.blockedPath),
    mcpSource: clean(options.mcpServer?.source),
    fromSubagent: options.agentID !== undefined || undefined,
    agent: subagents?.name(options.agentID),
    defaultToNo: options.defaultToNo || undefined,
    suppressAlwaysAllowRule: options.suppressAlwaysAllowRule || undefined,
  };
}

// I subagent di un turno, da `SubagentStart` (`agent_id` → `agent_type`): `canUseTool` e `permission_denied` danno solo
// l'`agent_id`, e ogni Richiesta o diniego di un subagent deve mostrarne il nome (spec 19).
export class Subagents {
  private readonly types = new Map<string, string>();

  /** L'hook `SubagentStart`: da qui in poi il suo `agent_id` ha un nome. */
  readonly hook = async (input: HookInput) => {
    if (input.hook_event_name === "SubagentStart") {
      const type = clean(input.agent_type);
      if (type) this.types.set(input.agent_id, type);
    }
    return {};
  };

  /** Il nome del subagent `id`; `undefined` per il filo principale o un subagent mai partito in questo turno. */
  name(id: string | undefined): string | undefined {
    return id === undefined ? undefined : this.types.get(id);
  }
}

// Approva solo una risposta esatta di Bubo; tutto il resto, anche una risposta storta, nega.
export function isAllowed(answer: unknown): boolean {
  return answer === "allow";
}

// Se Bubo ha approvato per il resto della Sessione ("Per questa Sessione" o "Sempre in questo Progetto").
export function isLasting(scope: unknown): boolean {
  return scope === "session";
}

// La Richiesta che la CLI fa per un host fuori dai domini della Sandbox, con `{ host }` come input. Non documentata:
// nome verificato nel binario 2.1.286, test in `violations.test.ts`. Arriva solo con `strictAllowlist: false`.
export const networkTool = "SandboxNetworkAccess";

// La regola `WebFetch(domain:host)` della sola sessione, come la propone la CLI: allarga la Sandbox a `host` anche per
// WebFetch, subito. Mai `localSettings`, dove la CLI la salverebbe da sola: Bubo non scrive i settings per la Sandbox.
// `undefined` per un host che non è un nome di dominio semplice.
export function networkRule(host: unknown): PermissionUpdate | undefined {
  if (typeof host !== "string" || !/^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$/.test(host.toLowerCase())) return undefined;
  return {
    type: "addRules",
    rules: [{ toolName: "WebFetch", ruleContent: `domain:${host.toLowerCase()}` }],
    behavior: "allow",
    destination: "session",
  };
}

// Gli strumenti che l'utente usa sulla propria scheda: un'approvazione con un tasto risponderebbe al posto suo.
// `AskUserQuestion` ha la sua scheda in Bubo (`question.ts`) e non arriva qui; gli altri si negano e Claude va avanti.
export function needsItsOwnCard(toolName: string, options: Options): boolean {
  return toolName === "AskUserQuestion" || (options as { requiresUserInteraction?: unknown }).requiresUserInteraction === true;
}

export const deniedByUser = "L'utente ha rifiutato questa azione in Bubo.";
export const deniedWithoutBubo = "Bubo non ha potuto chiedere il permesso all'utente: azione rifiutata.";
export const deniedOwnCard = "Bubo non può ancora mostrare questa domanda all'utente: continua senza, con la scelta più prudente.";

// Approvato, gira esattamente l'input che Bubo ha mostrato.
// `updatedPermissions` sono le regole di sessione che vengono con l'approvazione.
export function permissionResult(allowed: boolean, input: Record<string, unknown>, message = deniedByUser,
                                 updatedPermissions?: PermissionUpdate[]): PermissionResult {
  return allowed
    ? { behavior: "allow", updatedInput: input, decisionClassification: "user_temporary", ...(updatedPermissions ? { updatedPermissions } : {}) }
    : { behavior: "deny", message, decisionClassification: "user_reject" };
}
