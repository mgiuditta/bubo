import type { HookCallback, HookInput, McpServerStatus, PreToolUseHookInput, SandboxSettings } from "@anthropic-ai/claude-agent-sdk";
import { lstatSync, readlinkSync, realpathSync } from "node:fs";
import { dirname, isAbsolute, join, resolve, sep } from "node:path";

// Il cancello di Bubo prima di ogni strumento (spec 22): la sandbox di Claude Code chiude solo Bash, mentre Edit,
// Write e NotebookEdit girano nel processo `claude`, e la Modalità autonoma approva da sola fino a dove il classificatore
// vuole. Qui si nega o si chiede; mai si approva: il resto lo decidono Regole, modalità e Richieste di permesso.

/** Gli strumenti incorporati che scrivono file. */
const writingTools = new Set(["Edit", "Write", "MultiEdit", "NotebookEdit"]);
/** Le modalità che approvano senza chiedere: lì i livelli 4–5 e i Server MCP locali passano dal cancello. */
const autonomousModes = new Set(["auto", "bypassPermissions"]);

/** Cosa chiede il cancello per il Livello di rischio: gli stessi campi di una Richiesta di permesso. */
export type RiskQuestion = { tool: string; command?: string; path?: string; url?: string; mcpSource?: string };

export type Gate = {
  /** La cartella della Sessione: il worktree, o la cartella del Progetto fuori da git. */
  cwd: string;
  /** La Sandbox della Sessione, se accesa. */
  sandbox?: SandboxSettings;
  /** Se Bubo dà a questa chiamata il livello 4 o 5. Senza risposta, sì. */
  isDangerous: (question: RiskQuestion) => Promise<boolean>;
  /** Se il Server MCP `name` gira sul Mac (stdio). Se non si sa, sì. */
  isLocalServer: (name: string) => Promise<boolean>;
  /**
   * Nessuno davanti (un'Esecuzione di un'Automazione): il cancello nega dove chiederebbe, perché nessuno risponde, e
   * chiede il livello a Bubo in ogni modalità, anche dove una `allow` scritta a mano lascerebbe passare la chiamata.
   */
  isUnattended?: boolean;
};

export type Verdict = { decision: "deny" | "ask"; reason: string };

/** La riga che vedono l'utente e l'agente quando il cancello nega una scrittura. */
export function blockedWrite(path: string): string {
  return `Bloccato dalla sandbox: scrittura in ${path}`;
}

/** Il motivo della Richiesta di un comando che vuole uscire dalla sandbox. */
export const outsideSandbox = "Il comando chiede di girare fuori dalla sandbox.";

/** Se l'input di un Bash chiede di uscire dalla sandbox. */
export function isOutsideSandbox(toolName: string, input: unknown): boolean {
  return toolName === "Bash" && (input as { dangerouslyDisableSandbox?: unknown } | null)?.dangerouslyDisableSandbox === true;
}

/**
 * Il percorso reale di `path`, symlink compresi, anche se il file non esiste ancora: la parte che esiste si risolve
 * sul disco, il resto si aggiunge com'è. `undefined` quando non si può dire dove finirebbe una scrittura (un symlink
 * che punta nel vuoto, un ciclo): il cancello allora nega.
 */
export function realPath(path: string, cwd: string): string | undefined {
  // Senza normalizzare: `link/..` sale dalla destinazione del symlink, come fa il disco.
  const absolute = isAbsolute(path) ? path : `${cwd}${sep}${path}`;
  let current = realpathSync("/");
  let isMissing = false;
  let links = 0;
  const parts = absolute.split(sep).filter((part) => part !== "" && part !== ".");
  while (parts.length > 0) {
    const part = parts.shift()!;
    if (part === "..") {
      current = dirname(current);
      continue;
    }
    const next = join(current, part);
    if (isMissing) {
      current = next;
      continue;
    }
    let isLink: boolean;
    try {
      isLink = lstatSync(next).isSymbolicLink();
    } catch {
      isMissing = true;
      current = next;
      continue;
    }
    if (!isLink) {
      current = next;
      continue;
    }
    try {
      current = realpathSync(next);
    } catch {
      // Un symlink che punta a un file che non c'è: si segue a mano, perché scriverci crea il file di destinazione.
      if (++links > 40) return undefined;
      const target = readlinkSync(next);
      const absoluteTarget = isAbsolute(target) ? target : join(current, target);
      parts.unshift(...absoluteTarget.split(sep).filter((p) => p !== "" && p !== "."));
      current = realpathSync("/");
    }
  }
  return current;
}

/** Le cartelle dove una Sessione con la Sandbox accesa scrive: la sua, e quelle della Sandbox, già risolte. */
export function writableFolders(cwd: string, sandbox: SandboxSettings): string[] {
  const allowed = (sandbox.filesystem as { allowWrite?: unknown } | undefined)?.allowWrite;
  const folders = [cwd, ...(Array.isArray(allowed) ? allowed.filter((p): p is string => typeof p === "string" && isAbsolute(p)) : [])];
  return folders.map((folder) => realPath(folder, cwd)).filter((folder): folder is string => folder !== undefined);
}

/** Se `path`, già risolto, è dentro una di `folders`. */
export function isInside(path: string, folders: string[]): boolean {
  return folders.some((folder) => path === folder || path.startsWith(folder === "/" ? "/" : folder + sep));
}

/** Il nome del Server MCP di uno strumento `mcp__<server>__<strumento>`. */
function serverName(input: { tool_name: string; mcp_server?: { name: string } }): string | undefined {
  return input.mcp_server?.name ?? /^mcp__(.+?)__/.exec(input.tool_name)?.[1];
}

/** Il motivo di un diniego senza nessuno davanti, dove con qualcuno il cancello avrebbe chiesto. */
export function unattendedReason(reason: string): string {
  return `Nessuno può approvare in un'Esecuzione dell'Automazione: azione negata. ${reason}`;
}

/** Cosa fa il cancello con una chiamata: negarla, chiedere, o `undefined` per lasciarla al flusso normale. */
export async function verdict(input: HookInput, gate: Gate): Promise<Verdict | undefined> {
  const found = await attendedVerdict(input, gate);
  if (!found || !gate.isUnattended || found.decision === "deny") return found;
  return { decision: "deny", reason: unattendedReason(found.reason) };
}

async function attendedVerdict(input: HookInput, gate: Gate): Promise<Verdict | undefined> {
  if (input.hook_event_name !== "PreToolUse") return undefined;
  const tool = input.tool_name;
  const toolInput = (typeof input.tool_input === "object" && input.tool_input !== null ? input.tool_input : {}) as Record<string, unknown>;
  const isAutonomous = autonomousModes.has(input.permission_mode ?? "");
  const { sandbox } = gate;
  if (sandbox && writingTools.has(tool)) {
    const path = toolInput.file_path ?? toolInput.notebook_path;
    if (typeof path !== "string") return { decision: "deny", reason: blockedWrite("un percorso mancante") };
    // Come lo apre il disco, e come lo normalizza chi risolve `..` sul testo prima di aprirlo: dentro in entrambi i casi.
    const folders = writableFolders(gate.cwd, sandbox);
    const reals = [realPath(path, gate.cwd), realPath(resolve(gate.cwd, path), gate.cwd)];
    if (reals.some((real) => real === undefined || !isInside(real, folders))) {
      return { decision: "deny", reason: blockedWrite(path) };
    }
  }
  if (sandbox && isOutsideSandbox(tool, toolInput)) return { decision: "ask", reason: outsideSandbox };
  if (sandbox && isAutonomous && tool.startsWith("mcp__") && input.mcp_server?.source !== "sdk") {
    const name = serverName(input);
    if (name === undefined || await gate.isLocalServer(name)) {
      return { decision: "ask", reason: "Con la Sandbox accesa, gli strumenti dei Server MCP locali chiedono sempre." };
    }
  }
  if (sandbox || isAutonomous || gate.isUnattended) {
    const question: RiskQuestion = {
      tool,
      command: typeof toolInput.command === "string" ? toolInput.command : undefined,
      path: [toolInput.file_path, toolInput.notebook_path, toolInput.path].find((p): p is string => typeof p === "string"),
      url: typeof toolInput.url === "string" ? toolInput.url : undefined,
      mcpSource: input.mcp_server?.source,
    };
    if (await gate.isDangerous(question)) return { decision: "ask", reason: "Livello di rischio 4 o 5: chiede comunque." };
  }
  return undefined;
}

/**
 * Il cancello come hook `PreToolUse`. Un errore nel cancello nega: mai una chiamata che passa perché si è rotto.
 * `denied` sa di ogni chiamata negata, per il resoconto di un'Esecuzione.
 */
export function sandboxGate(gate: Gate, denied: (input: PreToolUseHookInput, reason: string) => void = () => {}): HookCallback {
  return async (input) => {
    let found: Verdict | undefined;
    try {
      found = await verdict(input, gate);
    } catch (error) {
      found = { decision: "deny", reason: `Il cancello di Bubo non ha potuto controllare la chiamata: ${error instanceof Error ? error.message : error}` };
    }
    if (!found) return {};
    if (found.decision === "deny" && input.hook_event_name === "PreToolUse") denied(input, found.reason);
    return { hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: found.decision, permissionDecisionReason: found.reason } };
  };
}

/** Se lo stato di un Server MCP dice che gira sul Mac: stdio, o senza configurazione nota. */
export function isLocal(status: McpServerStatus | undefined): boolean {
  const type = (status?.config as { type?: unknown } | undefined)?.type;
  if (status?.config === undefined) return true;
  return type === undefined || type === "stdio";
}
