// Le Domande via Copilot (ADR 0011, ADR 0014): il Copilot SDK lancia il `copilot` dell'utente, con il suo login, come
// nel terminale: i suoi strumenti e la sua configurazione, in Modalità autonoma con lo stesso cancello livelli 4–5 delle
// Domande Claude; con il Secondo cervello anche `cerca` e `ricorda` di Bubo (#678), mai le cartelle escluse. Verso Bubo
// i messaggi neutri del ponte: testo in streaming, Richieste di permesso, token (`usage`), chi ha risposto, fine.
import { CopilotClient, defineTool, RuntimeConnection, type CopilotSession, type ModelInfo,
  type PermissionRequest as CopilotRequest, type PermissionRequestResult, type SessionConfig, type SessionHooks,
  type SessionEvent, type Tool } from "@github/copilot-sdk";
import { homedir } from "node:os";
import { dirname, relative, resolve } from "node:path";
import { z } from "zod";
import { close, CopilotPermissions, decision, withFolderFirst, type CopilotPermissionEvent } from "./copilot";
import { isInside, realPath } from "./gate";
import { clean, deniedWithoutBubo } from "./permission";
import type { AnsweredBy } from "./router";
import { hiddenPathDenial, rememberCall, rememberTool, searchCall, searchTool, type BuboToolCall } from "./tools";
import type { TurnUsage } from "./usage";

type ReasoningEffort = NonNullable<SessionConfig["reasoningEffort"]>;
type PreToolUseHandler = NonNullable<SessionHooks["onPreToolUse"]>;

/** Un modello che il piano Copilot dell'utente offre, solo con quello che serve al router. */
export type CopilotModel = {
  id: string;
  name: string;
  /** Il moltiplicatore dei crediti rispetto alla tariffa base, se `copilot` lo dice. */
  multiplier?: number;
  supportedEfforts?: ReasoningEffort[];
  defaultEffort?: ReasoningEffort;
};

export type CopilotQuestionEvent =
  | { type: "text"; id: string; text: string }
  | { type: "done"; id: string }
  | { type: "error"; id: string; message: string }
  | ({ type: "usage"; id: string } & TurnUsage)
  | ({ type: "answeredBy"; id: string } & AnsweredBy)
  | { type: "copilotModels"; id: string; models: CopilotModel[] }
  | CopilotPermissionEvent;

export type CopilotQuestion = {
  id: string;
  prompt: string;
  /** Il `copilot` dell'utente, assoluto. */
  copilot: string;
  /** Dove gira la Domanda, come per Claude: il Secondo cervello, o una cartella vuota di Bubo. */
  cwd: string;
  model?: string;
  effort?: ReasoningEffort;
  /** Profilo e Regole del Secondo cervello, con il consenso dell'utente: in coda al prompt di sistema, con `cerca` e
   * `ricorda`. Senza, nessuna nota e nessuno strumento di Bubo. */
  brain?: string;
  /** Le cartelle escluse del Secondo cervello, assolute: nessuno strumento di `copilot` le tocca. */
  hidden?: string[];
  /** Se l'utente si fida di `cwd` (#266): solo allora `copilot` carica la configurazione e le istruzioni che vi trova,
   * hook, server MCP ed estensioni compresi, come `claude` le impostazioni di Progetto. */
  trusted?: boolean;
};

/** Manda a Bubo una chiamata a `cerca` o `ricorda` e aspetta il testo con cui risponde (`found`). */
export type AskBubo = (call: BuboToolCall) => Promise<string>;

/** Quanto ha aspettato una Domanda: dal comando di Bubo al primo testo, e dall'invio del prompt al primo testo. */
export type FirstToken = { sinceAsked: number; sinceSent: number };

// Gli strumenti di `copilot` con il nome di quelli di Claude che le cartelle escluse fermano: chi scrive come `Write`,
// chi cerca come `Grep` e `Glob` (non attraversano una cartella esclusa). Gli altri, se hanno un percorso, come `Read`.
const guardedAs: Record<string, string> = {
  view: "Read", grep: "Grep", rg: "Grep", glob: "Glob",
  create: "Write", edit: "Write", str_replace_editor: "Write", str_replace: "Write", insert: "Write",
};

// Gli strumenti di `copilot` che lanciano un comando: il loro testo non nomina una cartella esclusa.
const shellTools = new Set(["bash", "powershell"]);

const insideHidden = "Questa cartella è esclusa dal Secondo cervello: Bubo non la legge.";
const acrossHidden = "Il comando o la ricerca attraverserebbe una cartella esclusa dal Secondo cervello: usa cerca, o una sottocartella.";
const unresolved = "Con cartelle escluse dal Secondo cervello, un percorso di cui Bubo non sa dire dove finisce è negato.";

// Maiuscole e forma Unicode non contano: su un volume che non le distingue «privato» è «Privato». Al più nega di più.
const comparable = (path: string) => path.normalize("NFC").toLowerCase();

/** Dove finisce `path` in `cwd`, `~` compreso, come lo apre il disco (symlink, poi `..`) e come lo normalizza chi
 * risolve `..` sul testo; `undefined` se non si può dire (un symlink che non porta da nessuna parte, un ciclo). */
function landings(path: string, cwd: string): string[] | undefined {
  const raw = path === "~" || path.startsWith("~/") ? homedir() + path.slice(1) : path;
  const reals = [realPath(raw, cwd), realPath(resolve(cwd, raw), cwd)];
  return reals.every((real): real is string => real !== undefined) ? reals.map(comparable) : undefined;
}

/** Le cartelle escluse risolte, e anche come sono scritte: un percorso che porta a una delle due forme è dentro. */
function hiddenLandings(hidden: string[], cwd: string): string[] {
  return hidden.flatMap((dir) => [...(landings(dir, cwd) ?? []), comparable(resolve(cwd, dir))]);
}

/** Perché `path` tocca una cartella esclusa `hidden`: ci finisce dentro, o, se `isSearch`, ne è sopra e la
 * attraverserebbe; nega anche quando non si sa dove finisce. `undefined` se non la tocca. */
export function hiddenPathReason(path: string, cwd: string, hidden: string[], isSearch: boolean): string | undefined {
  const reals = landings(path, cwd);
  if (!reals) return unresolved;
  const dirs = hiddenLandings(hidden, cwd);
  if (reals.some((real) => isInside(real, dirs))) return insideHidden;
  if (isSearch && dirs.some((dir) => isInside(dir, reals))) return acrossHidden;
  return undefined;
}

/** Perché il testo di un comando nomina una cartella esclusa: assoluta, reale, dalla home o relativa a `cwd`. Il
 * testo non dice tutto (variabili, glob, `cd`): è una difesa in più, non l'unica. */
function hiddenCommandReason(command: string, cwd: string, hidden: string[]): string | undefined {
  const text = comparable(command);
  const home = comparable(homedir());
  const forms = new Set<string>();
  for (const dir of hiddenLandings(hidden, cwd)) {
    forms.add(dir);
    if (dir.startsWith(home + "/")) forms.add(`~${dir.slice(home.length)}`).add(`$home${dir.slice(home.length)}`);
    const fromCwd = relative(comparable(cwd), dir);
    if (fromCwd && !fromCwd.startsWith("..")) forms.add(fromCwd);
  }
  const escape = (form: string) => form.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return [...forms].some((form) => new RegExp(`(^|[\\s'"=:(/])${escape(form)}(?=$|[\\s'"/;|&)*])`).test(text))
    ? insideHidden : undefined;
}

/** Perché lo strumento `tool` di `copilot` non può toccare `args` in una Domanda in `cwd` con le cartelle escluse
 * `hidden`; `undefined` se può. Le regole delle Domande Claude (`hiddenPathDenial`), poi ogni percorso risolto come
 * fa il cancello (`gate.ts`), e il testo dei comandi. */
export function hiddenToolDenial(tool: string, args: unknown, cwd: string, hidden: string[]): string | undefined {
  if (hidden.length === 0) return undefined;
  const as = guardedAs[tool] ?? "Read";
  const claude = hiddenPathDenial(as, args, cwd, hidden);
  if (claude) return claude;
  const fields = (typeof args === "object" && args !== null ? args : {}) as Record<string, unknown>;
  for (const key of ["path", "file_path", "notebook_path"]) {
    const path = fields[key];
    const reason = typeof path === "string" ? hiddenPathReason(path, cwd, hidden, as === "Grep" || as === "Glob") : undefined;
    if (reason) return reason;
  }
  if (shellTools.has(tool) && typeof fields.command === "string") return hiddenCommandReason(fields.command, cwd, hidden);
  return undefined;
}

/** L'hook prima di ogni strumento che tiene `copilot` fuori dalle cartelle escluse: un errore nega, mai lascia passare
 * (l'SDK conta come «nessuna decisione» un hook che lancia). */
export function hiddenFoldersHook(cwd: string, hidden: string[]): PreToolUseHandler {
  return (input) => {
    let reason: string | undefined;
    try {
      reason = hiddenToolDenial(input.toolName, input.toolArgs, cwd, hidden);
    } catch (error) {
      reason = `Il cancello di Bubo non ha potuto controllare la chiamata: ${error instanceof Error ? error.message : error}`;
    }
    return reason ? { permissionDecision: "deny", permissionDecisionReason: reason } : undefined;
  };
}

/** Perché una Richiesta tocca una cartella esclusa, e va respinta prima del cancello: il file da leggere o scrivere, e
 * ogni percorso di un comando, che non può nemmeno passarci sopra, e il suo testo. */
export function hiddenRequestDenial(asked: CopilotRequest, cwd: string, hidden: string[]): string | undefined {
  if (hidden.length === 0) return undefined;
  if (asked.kind === "read") return hiddenToolDenial("view", { path: asked.path }, cwd, hidden);
  if (asked.kind === "write") return hiddenToolDenial("create", { path: asked.fileName }, cwd, hidden);
  if (asked.kind === "shell") {
    for (const path of asked.possiblePaths ?? []) {
      const reason = hiddenPathReason(path, cwd, hidden, true);
      if (reason) return reason;
    }
    return hiddenCommandReason(asked.fullCommandText ?? "", cwd, hidden);
  }
  return undefined;
}

/** Chiede il permesso per una Richiesta di `copilot` nella Domanda: dal cancello di `CopilotPermissions`. */
export type AskPermission = (asked: CopilotRequest) => Promise<PermissionRequestResult>;

/** `cerca` e `ricorda` di Bubo come strumenti della sessione della Domanda `conversation`: rispondono da Bubo, senza
 * Richiesta di permesso, e ogni scrittura va nel registro delle modifiche, annullabile. */
export function buboTools(conversation: string, askBubo: AskBubo): Tool<any>[] {
  const search = z.object(searchTool.shape);
  const remember = z.object(rememberTool.shape);
  return [
    defineTool(searchTool.name, {
      description: searchTool.description, parameters: search, skipPermission: true, defer: "never",
      // Il consenso vale per le note: mai la memoria dei Progetti né le conversazioni passate.
      handler: (args) => askBubo({ ...searchCall(search.parse(args), conversation), project: undefined, source: "secondo-cervello" }),
    }),
    defineTool(rememberTool.name, {
      description: rememberTool.description, parameters: remember, skipPermission: true, defer: "never",
      // Mai `confermato` dal modello: Copilot non riscrive le note dell'utente né il Profilo, solo Bubo/.
      handler: (args) => askBubo({ ...rememberCall(remember.parse(args), conversation), confirmed: false }),
    }),
  ];
}

/** La sessione di una Domanda come `copilot` nel terminale: i suoi strumenti, e ogni Richiesta a `askPermission`. La
 * configurazione e le istruzioni della cartella solo se `trusted`. Con il Secondo cervello (`brain` e `askBubo`)
 * Profilo e Regole in coda al prompt di sistema, e in più `cerca` e `ricorda` di Bubo. Le cartelle escluse `hidden`
 * restano chiuse a ogni strumento. */
export function questionSession(question: Pick<CopilotQuestion, "id" | "cwd" | "model" | "effort" | "brain" | "hidden" | "trusted">,
                                askPermission: AskPermission, askBubo?: AskBubo): SessionConfig {
  const hidden = question.hidden ?? [];
  const trusted = question.trusted === true;
  return {
    clientName: "bubo",
    workingDirectory: question.cwd,
    model: question.model,
    reasoningEffort: question.effort,
    streaming: true,
    // Una cartella di cui l'utente non si fida non esegue nulla di suo: niente hook, server MCP, estensioni né istruzioni.
    enableConfigDiscovery: trusted,
    enableOnDemandInstructionDiscovery: trusted,
    ...(question.brain && askBubo
      ? { tools: buboTools(question.id, askBubo), systemMessage: { mode: "append" as const, content: question.brain } }
      : {}),
    ...(hidden.length > 0 ? { hooks: { onPreToolUse: hiddenFoldersHook(question.cwd, hidden) } } : {}),
    onPermissionRequest: async (asked) => {
      let reason: string | undefined;
      try {
        reason = hidden.length > 0 ? hiddenRequestDenial(asked, question.cwd, hidden) : undefined;
      } catch {
        reason = deniedWithoutBubo;
      }
      return reason ? decision(false, reason) : askPermission(asked);
    },
  };
}

/** I modelli di `listModels()` che il piano abilita, senza quelli spenti dalla policy dell'organizzazione. */
export function copilotModelsOf(models: ModelInfo[]): CopilotModel[] {
  return models.filter((model) => model.policy?.state !== "disabled").map((model) => ({
    id: model.id,
    name: model.name,
    ...(model.billing?.multiplier !== undefined && { multiplier: model.billing.multiplier }),
    ...(model.supportedReasoningEfforts?.length && { supportedEfforts: model.supportedReasoningEfforts }),
    ...(model.defaultReasoningEffort && { defaultEffort: model.defaultReasoningEffort }),
  }));
}

/** Le Domande via Copilot in corso, una per `id`, e la lettura dei modelli. */
export class CopilotQuestions {
  private readonly running = new Map<string, () => void>();

  /** `askBubo` risponde a `cerca` e `ricorda` delle Domande con il Secondo cervello; senza, nessuna li riceve.
   * `permissions` è il cancello delle Richieste, lo stesso delle Sessioni Copilot. */
  constructor(private readonly send: (event: CopilotQuestionEvent) => void,
              private readonly environment: Record<string, string>,
              private readonly askBubo?: AskBubo,
              private readonly permissions: CopilotPermissions = new CopilotPermissions(send)) {}

  /** Risponde alla Richiesta `request`; `false` se non è di un turno Copilot. */
  answer(request: string, allowed: boolean): boolean {
    return this.permissions.answer(request, allowed);
  }

  /** Ferma la Domanda `id`; `false` se non è una Domanda via Copilot in corso. */
  cancel(id: string): boolean {
    const stop = this.running.get(id);
    stop?.();
    return stop !== undefined;
  }

  /** I modelli del piano dell'utente, come `copilotModels`; un errore se `copilot` non li dà. */
  async models(id: string, copilot: string): Promise<void> {
    const client = this.client(copilot, dirname(copilot));
    try {
      await client.start();
      this.send({ type: "copilotModels", id, models: copilotModelsOf(await client.listModels()) });
    } catch (error) {
      this.send({ type: "error", id, message: messageOf(error) });
    } finally {
      await close(client);
    }
  }

  /** Risponde alla Domanda; restituisce l'attesa del primo testo, se è arrivato. */
  async ask(question: CopilotQuestion): Promise<FirstToken | undefined> {
    const { id } = question;
    const asked = performance.now();
    const stopped = new AbortController();
    let session: CopilotSession | undefined;
    let firstToken: FirstToken | undefined;
    const client = this.client(question.copilot, question.cwd);
    const finished = Promise.withResolvers<"done" | "stopped" | { error: string }>();
    const usage = new CopilotUsage();
    this.running.set(id, () => {
      if (stopped.signal.aborted) return;
      stopped.abort();
      finished.resolve("stopped");
      void session?.abort().catch(() => {});
    });
    try {
      // Una Domanda gira come la riga di comando: Modalità autonoma, il cancello chiede solo sui livelli 4–5.
      const askPermission: AskPermission = (asked) => this.permissions.ask(id, asked, stopped.signal, true);
      session = await client.createSession(questionSession(question, askPermission, this.askBubo));
      if (stopped.signal.aborted) return undefined;
      let sent = 0;
      session.on((event: SessionEvent) => {
        if (event.type === "assistant.message_delta") {
          if (!event.data.deltaContent) return;
          const now = performance.now();
          firstToken ??= { sinceAsked: Math.round(now - asked), sinceSent: Math.round(now - sent) };
          this.send({ type: "text", id, text: event.data.deltaContent });
        } else if (event.type === "assistant.usage") {
          if (event.agentId === undefined) usage.add(event.data);
        } else if (event.type === "session.idle") {
          finished.resolve("done");
        } else if (event.type === "session.error") {
          finished.resolve({ error: clean(event.data.message) ?? event.data.errorType });
        }
      });
      sent = performance.now();
      await session.send({ prompt: question.prompt });
      const end = await finished.promise;
      const turn = usage.turn();
      if (turn) this.send({ type: "usage", id, ...turn });
      if (end === "done") {
        const answeredBy = usage.answeredBy();
        if (answeredBy) this.send({ type: "answeredBy", id, ...answeredBy });
        this.send({ type: "done", id });
      } else if (end !== "stopped") {
        this.send({ type: "error", id, message: end.error });
      }
      return firstToken;
    } catch (error) {
      if (!stopped.signal.aborted) this.send({ type: "error", id, message: messageOf(error) });
      return undefined;
    } finally {
      stopped.abort();
      this.running.delete(id);
      await close(client, session);
    }
  }

  private client(copilot: string, cwd: string) {
    return new CopilotClient({
      connection: RuntimeConnection.forStdio({ path: copilot, env: withFolderFirst(this.environment, copilot) }),
      useLoggedInUser: true,
      workingDirectory: cwd,
    });
  }
}

type UsageData = Extract<SessionEvent, { type: "assistant.usage" }>["data"];

/** I token di una Domanda per modello, dagli `assistant.usage` del thread principale: Spesa, senza cifra (#542). */
export class CopilotUsage {
  private readonly models = new Map<string, TurnUsage["models"][number]>();
  private last?: AnsweredBy;

  add(data: UsageData) {
    const tokens = this.models.get(data.model)
      ?? { model: data.model, inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, thinkingTokens: 0 };
    tokens.inputTokens += data.inputTokens ?? 0;
    tokens.outputTokens += data.outputTokens ?? 0;
    tokens.cacheReadTokens += data.cacheReadTokens ?? 0;
    tokens.cacheWriteTokens += data.cacheWriteTokens ?? 0;
    tokens.thinkingTokens += data.reasoningTokens ?? 0;
    this.models.set(data.model, tokens);
    const effort = data.reasoningEffort && data.reasoningEffort !== "none" ? data.reasoningEffort : undefined;
    this.last = { model: data.model, ...(effort && { effort }) };
  }

  /** `undefined` se `copilot` non ha detto nessun token. */
  turn(): TurnUsage | undefined {
    if (this.models.size === 0) return undefined;
    return { mode: "apiKey", basis: "unknown", complete: true, models: [...this.models.values()] };
  }

  answeredBy(): AnsweredBy | undefined {
    return this.last;
  }
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
