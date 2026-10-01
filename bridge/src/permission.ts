import type { CanUseTool, PermissionResult } from "@anthropic-ai/claude-agent-sdk";

// La Richiesta di permesso che il ponte manda a Bubo: solo stringhe e booleani, già ripuliti.
// Bubo ne ricava il Livello di rischio da strumento, comando e percorso; il resto è testo da mostrare.
export type PermissionRequest = {
  type: "permission";
  request: string;
  tool: string;
  command?: string;
  path?: string;
  url?: string;
  title?: string;
  description?: string;
  blockedPath?: string;
  mcpSource?: string;
  fromSubagent?: boolean;
  defaultToNo?: boolean;
  suppressAlwaysAllowRule?: boolean;
};

type Options = Parameters<CanUseTool>[2];

const textLength = 4000;

// Testo scritto da `claude`, da un server MCP o dal modello: niente sequenze ANSI né caratteri di controllo.
export function clean(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const text = value.replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "").replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "");
  return text.length > textLength ? text.slice(0, textLength - 1) + "…" : text;
}

export function permissionRequest(request: string, toolName: string, input: Record<string, unknown>,
                                  options: Options): PermissionRequest {
  return {
    type: "permission",
    request,
    tool: clean(toolName) ?? "",
    command: clean(input.command),
    path: clean(input.file_path ?? input.notebook_path ?? input.path),
    url: clean(input.url),
    title: clean(options.title),
    description: clean(options.description),
    blockedPath: clean(options.blockedPath),
    mcpSource: clean(options.mcpServer?.source),
    fromSubagent: options.agentID !== undefined || undefined,
    defaultToNo: options.defaultToNo || undefined,
    suppressAlwaysAllowRule: options.suppressAlwaysAllowRule || undefined,
  };
}

// Approva solo una risposta esatta di Bubo; tutto il resto, anche una risposta storta, nega.
export function isAllowed(answer: unknown): boolean {
  return answer === "allow";
}

// Le domande all'utente vivono sulla scheda dello strumento (AskUserQuestion): Bubo non le mostra ancora.
// Un'approvazione con un tasto lì risponderebbe al posto dell'utente: si nega e Claude va avanti da solo.
export function needsItsOwnCard(toolName: string, options: Options): boolean {
  return toolName === "AskUserQuestion" || (options as { requiresUserInteraction?: unknown }).requiresUserInteraction === true;
}

export const deniedByUser = "L'utente ha rifiutato questa azione in Bubo.";
export const deniedWithoutBubo = "Bubo non ha potuto chiedere il permesso all'utente: azione rifiutata.";
export const deniedOwnCard = "Bubo non può ancora mostrare questa domanda all'utente: continua senza, con la scelta più prudente.";

// Approvato, gira esattamente l'input che Bubo ha mostrato.
export function permissionResult(allowed: boolean, input: Record<string, unknown>, message = deniedByUser): PermissionResult {
  return allowed
    ? { behavior: "allow", updatedInput: input, decisionClassification: "user_temporary" }
    : { behavior: "deny", message, decisionClassification: "user_reject" };
}
