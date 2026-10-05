// Le Sessioni su `copilot` (ADR 0012): il Copilot SDK lancia il `copilot` dell'utente, con il suo login, sul worktree
// che crea Bubo. Verso Bubo gli stessi messaggi neutri delle Sessioni Claude: testo, stato, Richieste di permesso, fine.
import type { SessionMessage, SessionStoreEntry } from "@anthropic-ai/claude-agent-sdk";
import { CopilotClient, RuntimeConnection, type CopilotSession, type PermissionRequest as CopilotRequest,
  type PermissionRequestResult, type ResumeSessionConfig, type SessionConfig, type SessionEvent } from "@github/copilot-sdk";
import { randomUUID } from "node:crypto";
import { dirname } from "node:path";
import { unattendedReason, type RiskQuestion } from "./gate";
import { deniedByUser, deniedWithoutBubo, isTooLong, raw, clean, type PermissionRequest } from "./permission";
import { summary, writtenLines, type Edit, type Progress, type Read } from "./activity";
import { CopilotUsage } from "./copilot-question";
import { dates, messages, transcriptLimit, type Message } from "./history";
import type { ConversationStore } from "./store";
import type { Denial } from "./unattended";
import type { TurnUsage } from "./usage";

type ReasoningEffort = NonNullable<SessionConfig["reasoningEffort"]>;

export type CopilotEvent =
  | { type: "text"; id: string; text: string }
  | { type: "done"; id: string }
  | ({ type: "usage"; id: string } & TurnUsage)
  | { type: "error"; id: string; message: string }
  | (Progress & { id: string })
  | (Edit & { id: string })
  | (Read & { id: string })
  | { type: "ran"; id: string }
  | (PermissionRequest & { id: string })
  | { type: "permissionWithdrawn"; id: string; request: string }
  | (Denial & { type: "denial"; id: string });

export type CopilotTurn = {
  id: string;
  prompt: string;
  cwd: string;
  /** Il `copilot` dell'utente, assoluto. */
  copilot: string;
  model?: string;
  effort?: ReasoningEffort;
  /** La conversazione che Bubo conserva (ADR 0006): è anche l'id della sessione di `copilot`. */
  keep?: string;
  /** Riprende `keep` con `resumeSession`, invece di aprirla. */
  resume?: boolean;
  /** `auto` nella Modalità autonoma: si approva da sé e chiede solo sui livelli 4–5, come una Sessione Claude. */
  permissionMode?: "auto" | "default";
  /** Il turno di un'Esecuzione, senza nessuno davanti: nessuna Richiesta arriva a Bubo, il resto è negato (#728). */
  unattended?: boolean;
};

/** Se Bubo dà il livello 4 o 5 a una chiamata del turno `id`; senza risposta, sì. */
export type IsDangerous = (id: string, question: RiskQuestion, signal: AbortSignal) => Promise<boolean>;

// La copia delle conversazioni Copilot nello store di Bubo, separata da quelle di Claude da questo Progetto.
export const copilotProject = "copilot";

type Copy = Pick<ConversationStore, "append" | "load">;

// Un messaggio di una conversazione Copilot nello stesso formato delle voci di Claude: `messages` di history.ts lo legge
// come le altre, e l'Indice non vede differenze.
export function copiedEntry(role: "user" | "assistant", text: string, uuid: string = randomUUID(),
                            timestamp = new Date().toISOString()): SessionStoreEntry {
  return { type: role, uuid, timestamp, message: { role, content: text } };
}

// I messaggi di una conversazione Copilot copiata, come quelli di `transcript` per Claude.
export function copiedMessages(entries: SessionStoreEntry[], limit = transcriptLimit): Message[] {
  return messages(entries as unknown as SessionMessage[], dates(entries), limit);
}

// Se `copilot` non ha più la sessione, il turno riparte dalla copia di Bubo: la conversazione fin qui, poi il prompt.
export function withEarlier(earlier: Message[], prompt: string): string {
  if (!earlier.length) return prompt;
  const lines = earlier.map((message) => `${message.role === "user" ? "Utente" : "Assistente"}: ${message.text}`);
  return `La conversazione fin qui:\n\n${lines.join("\n\n")}\n\nOra: ${prompt}`;
}

// Le variabili che farebbero usare a `copilot` un token al posto del login dell'utente (ADR 0012): mai al figlio.
const tokens = ["GH_TOKEN", "GITHUB_TOKEN", "COPILOT_GITHUB_TOKEN"];

export function copilotEnvironment(base: Record<string, string | undefined>): Record<string, string> {
  return Object.fromEntries(Object.entries(base).filter((entry): entry is [string, string] =>
    entry[1] !== undefined && !tokens.includes(entry[0])));
}

const efforts: readonly ReasoningEffort[] = ["low", "medium", "high", "xhigh", "max"];

export function reasoningEffortOf(value: unknown): ReasoningEffort | undefined {
  return efforts.find((effort) => effort === value);
}

// La Richiesta di `copilot` come quella di Claude: il nome dello strumento di Claude dove c'è, perché Bubo ne ricavi
// lo stesso Livello di rischio da strumento, comando e percorso. Gli altri tipi arrivano con il loro nome.
export function permissionRequest(request: string, asked: CopilotRequest): PermissionRequest {
  const shown: PermissionRequest = { type: "permission", request, tool: clean(asked.kind) ?? "" };
  switch (asked.kind) {
    case "shell": return { ...shown, tool: "Bash", command: raw(asked.fullCommandText), description: clean(asked.intention) };
    case "write": return { ...shown, tool: "Edit", path: raw(asked.fileName), description: clean(asked.intention) };
    case "read": return { ...shown, tool: "Read", path: raw(asked.path), description: clean(asked.intention) };
    case "url": return { ...shown, tool: "WebFetch", url: raw(asked.url), description: clean(asked.intention) };
    case "mcp": return { ...shown, tool: `mcp__${clean(asked.serverName)}__${clean(asked.toolName)}`, description: clean(asked.toolTitle) };
    default: return shown;
  }
}

// Le letture e le scritture dagli strumenti di `copilot`, come quelle di Claude: `view` legge; `create` ed `edit`
// scrivono `file_text` e `new_str`; `str_replace_editor` fa l'uno o l'altro secondo `command`.
export function toolActivity(tool: string, args: unknown): Edit | Read | undefined {
  const input = (args ?? {}) as { command?: unknown; path?: unknown; file_text?: unknown; new_str?: unknown };
  if (typeof input.path !== "string") return undefined;
  const command = tool === "str_replace_editor" ? input.command : tool;
  if (command === "view") return { type: "read", files: [input.path] };
  const text = command === "create" ? input.file_text
    : command === "edit" || command === "str_replace" || command === "insert" ? input.new_str
    : undefined;
  return typeof text === "string" ? { type: "edit", file: input.path, lines: writtenLines(text) } : undefined;
}

// Gli strumenti di `copilot` che lanciano un comando: alla fine Bubo cerca le porte nuove (spec 15).
const shells = new Set(["bash", "powershell"]);

// Approvato una volta: "Per questa Sessione" lo ricorda Bubo, che risponde da sé alle Richieste uguali.
export function decision(allowed: boolean, message = deniedByUser): PermissionRequestResult {
  return allowed ? { kind: "approve-once", approvedInteractively: true } : { kind: "reject", feedback: message };
}

// Approvato dalla Modalità autonoma, senza chiedere: livelli 1–3.
export const approvedByMode: PermissionRequestResult = { kind: "approve-once" };

// La Modalità autonoma approva da sé solo i tipi che Bubo sa classificare, e mai contro la policy dell'organizzazione
// o per uscire dalla sandbox di `copilot`: estensioni, hook, variabili d'ambiente e il resto chiedono sempre.
const classifiedKinds = new Set(["shell", "write", "read", "url", "mcp"]);
export function mayApproveByMode(asked: CopilotRequest): boolean {
  const flags = asked as { managedApprovalRequired?: boolean; requestSandboxBypass?: boolean };
  return classifiedKinds.has(asked.kind) && !flags.managedApprovalRequired && !flags.requestSandboxBypass;
}

// Quanto aspetta Ferma la fine del turno dopo `abort`, prima di chiudere `copilot`: l'obiettivo è 2 s.
const abortGrace = 1_500;

// I turni Copilot in corso, uno per `id`, con le Richieste in attesa della risposta di Bubo.
export class CopilotTurns {
  private readonly running = new Map<string, { stop(): void }>();
  private readonly permissions = new Map<string, (allowed: boolean) => void>();

  constructor(private readonly send: (event: CopilotEvent) => void,
              private readonly environment: Record<string, string>,
              private readonly copy?: Copy,
              private readonly isDangerous: IsDangerous = async () => true) {}

  has(id: string): boolean {
    return this.running.has(id);
  }

  /** Risponde alla Richiesta `request`; `false` se non è di un turno Copilot. */
  answer(request: string, allowed: boolean): boolean {
    const resolve = this.permissions.get(request);
    if (!resolve) return false;
    this.permissions.delete(request);
    resolve(allowed);
    return true;
  }

  /** Ferma: `abort` del turno `id`, poi `copilot` chiuso se non finisce in tempo. */
  cancel(id: string): boolean {
    const turn = this.running.get(id);
    turn?.stop();
    return turn !== undefined;
  }

  async run(turn: CopilotTurn): Promise<void> {
    const { id } = turn;
    const stopped = new AbortController();
    let session: CopilotSession | undefined;
    const client = new CopilotClient({
      connection: RuntimeConnection.forStdio({ path: turn.copilot, env: withFolderFirst(this.environment, turn.copilot) }),
      useLoggedInUser: true,
      workingDirectory: turn.cwd,
    });
    const finished = Promise.withResolvers<"done" | "stopped" | { error: string }>();
    // Anche i token dei subagenti: li paga l'utente. Bubo ne fa la Spesa stimata (#542).
    const usage = new CopilotUsage();
    this.running.set(id, {
      stop: () => {
        if (stopped.signal.aborted) return;
        stopped.abort();
        finished.resolve("stopped");
        void session?.abort().catch(() => {});
      },
    });
    try {
      const config: ResumeSessionConfig = {
        clientName: "bubo",
        workingDirectory: turn.cwd,
        model: turn.model,
        reasoningEffort: turn.effort,
        streaming: true,
        onPermissionRequest: (asked) => this.ask(id, asked, stopped.signal, turn.permissionMode === "auto",
                                                turn.unattended === true),
      };
      let prompt = turn.prompt;
      const { keep } = turn;
      const resumed = keep && turn.resume ? await client.resumeSession(keep, config).catch(() => undefined) : undefined;
      if (keep && turn.resume && !resumed) prompt = withEarlier(await this.earlier(keep), prompt);
      session = resumed ?? await client.createSession({ ...config, sessionId: keep });
      if (stopped.signal.aborted) return;
      const record = (entry: SessionStoreEntry) => {
        if (keep) void this.copy?.append({ projectKey: copilotProject, sessionId: keep }, [entry]).catch(() => {});
      };
      record(copiedEntry("user", turn.prompt));
      const commands = new Set<string>();
      session.on((event: SessionEvent) => {
        if (event.type === "assistant.message") {
          // Solo il filo principale: i subagenti hanno `parentToolCallId`.
          if (!event.data.parentToolCallId && event.data.content.trim()) {
            record(copiedEntry("assistant", event.data.content, event.id, event.timestamp));
            const line = summary(event.data.content);
            if (line) this.send({ ...line, id });
          }
        } else if (event.type === "tool.execution_start") {
          const activity = toolActivity(event.data.toolName, event.data.arguments);
          if (activity) this.send({ ...activity, id });
          if (shells.has(event.data.toolName)) commands.add(event.data.toolCallId);
        } else if (event.type === "tool.execution_complete") {
          if (commands.delete(event.data.toolCallId)) this.send({ type: "ran", id });
        } else if (event.type === "assistant.message_delta") {
          if (event.data.deltaContent) this.send({ type: "text", id, text: event.data.deltaContent });
        } else if (event.type === "assistant.usage") {
          usage.add(event.data);
        } else if (event.type === "session.idle") {
          finished.resolve("done");
        } else if (event.type === "session.error") {
          finished.resolve({ error: clean(event.data.message) ?? event.data.errorType });
        }
      });
      this.send({ type: "state", id, state: "running" });
      await session.send({ prompt });
      const end = await finished.promise;
      const tokens = usage.turn();
      if (tokens) this.send({ type: "usage", id, ...tokens, complete: end === "done" });
      if (end === "done") {
        this.send({ type: "state", id, state: "idle" });
        this.send({ type: "done", id });
      } else if (end !== "stopped") {
        this.send({ type: "error", id, message: end.error });
      }
    } catch (error) {
      if (!stopped.signal.aborted) this.send({ type: "error", id, message: error instanceof Error ? error.message : String(error) });
    } finally {
      stopped.abort();
      this.running.delete(id);
      await close(client, session);
    }
  }

  // La conversazione `keep` come l'ha copiata Bubo.
  private async earlier(keep: string): Promise<Message[]> {
    const entries = await this.copy?.load({ projectKey: copilotProject, sessionId: keep }).catch(() => null);
    return entries ? copiedMessages(entries) : [];
  }

  // `onPermissionRequest` del turno `id`: chiude sempre su "no", come `canUseTool` delle Sessioni Claude. Nella Modalità
  // autonoma passa prima dal cancello: approva da sé, e chiede a Bubo solo sui livelli 4–5. Senza nessuno davanti
  // (`isUnattended`) non chiede mai: quello che la modalità non approva da sé è negato, e finisce nel resoconto.
  private async ask(id: string, asked: CopilotRequest, signal: AbortSignal, isAutonomous: boolean,
                    isUnattended = false): Promise<PermissionRequestResult> {
    if (signal.aborted) return decision(false, deniedWithoutBubo);
    const request = randomUUID();
    const shown = permissionRequest(request, asked);
    if (isTooLong(shown)) return decision(false, deniedWithoutBubo);
    const { tool, command, path, url } = shown;
    let isDangerous = false;
    if (isAutonomous && mayApproveByMode(asked)) {
      isDangerous = await this.isDangerous(id, { tool, command, path, url }, signal).catch(() => true);
      if (signal.aborted) return decision(false, deniedWithoutBubo);
      if (!isDangerous) return approvedByMode;
    }
    if (isUnattended) {
      this.send({ type: "denial", id, toolUseID: request, tool, command, path, url, suggestions: [], source: "gate" });
      return decision(false, unattendedReason(isDangerous ? "Livello di rischio 4 o 5." : "Serve un'approvazione."));
    }
    let reached = true;
    const allowed = await new Promise<boolean>((resolve) => {
      this.permissions.set(request, resolve);
      signal.addEventListener("abort", () => {
        resolve(false);
        if (this.permissions.delete(request)) this.send({ type: "permissionWithdrawn", id, request });
      }, { once: true });
      try {
        this.send({ ...shown, id });
      } catch {
        reached = false;
        resolve(false);
      }
    });
    this.permissions.delete(request);
    return decision(allowed, reached ? deniedByUser : deniedWithoutBubo);
  }
}

// La cartella di `copilot` prima nel PATH, come in `ChildEnvironment.makeForCopilot`: un'installazione npm vi trova `node`.
export function withFolderFirst(environment: Record<string, string>, copilot: string): Record<string, string> {
  const path = [dirname(copilot), ...(environment.PATH?.split(":") ?? [])].filter(Boolean).join(":");
  return { ...environment, PATH: path };
}

// La sessione si stacca e `copilot` si chiude; se non risponde entro `abortGrace`, si chiude a forza.
export async function close(client: CopilotClient, session?: CopilotSession) {
  const graceful = (async () => {
    await session?.disconnect().catch(() => {});
    await client.stop();
  })();
  const timeout = new Promise<"late">((resolve) => setTimeout(() => resolve("late"), abortGrace).unref());
  if (await Promise.race([graceful.then(() => "closed" as const), timeout]) === "late") await client.forceStop();
}
