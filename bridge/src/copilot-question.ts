// Le Domande via Copilot (ADR 0011, ADR 0014): il Copilot SDK lancia il `copilot` dell'utente, con il suo login, come
// nel terminale: i suoi strumenti e la sua configurazione, in Modalità autonoma con lo stesso cancello livelli 4–5 delle
// Domande Claude; con il Secondo cervello anche `cerca` e `ricorda` di Bubo (#678), mai le cartelle escluse. Verso Bubo
// i messaggi neutri del ponte: testo in streaming, Richieste di permesso, token (`usage`), chi ha risposto, fine.
import { CopilotClient, defineTool, RuntimeConnection, type CopilotSession, type ModelInfo,
  type PermissionRequest as CopilotRequest, type PermissionRequestResult, type SessionConfig, type SessionHooks,
  type SessionEvent, type Tool } from "@github/copilot-sdk";
import { dirname } from "node:path";
import { z } from "zod";
import { close, CopilotPermissions, decision, withFolderFirst, type CopilotPermissionEvent } from "./copilot";
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

/** Perché lo strumento `tool` di `copilot` non può toccare `args` in una Domanda in `cwd` con le cartelle escluse
 * `hidden`; `undefined` se può. Le stesse regole delle Domande Claude (`hiddenPathDenial`). */
export function hiddenToolDenial(tool: string, args: unknown, cwd: string, hidden: string[]): string | undefined {
  return hiddenPathDenial(guardedAs[tool] ?? "Read", args, cwd, hidden);
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

/** Una Richiesta di lettura o scrittura dentro una cartella esclusa: respinta prima del cancello. */
function hiddenRequestDenial(asked: CopilotRequest, cwd: string, hidden: string[]): string | undefined {
  if (asked.kind === "read") return hiddenToolDenial("view", { path: asked.path }, cwd, hidden);
  if (asked.kind === "write") return hiddenToolDenial("create", { path: asked.fileName }, cwd, hidden);
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

/** La sessione di una Domanda come `copilot` nel terminale: i suoi strumenti e la sua configurazione, e ogni Richiesta
 * a `askPermission`. Con il Secondo cervello (`brain` e `askBubo`) Profilo e Regole in coda al prompt di sistema, e in
 * più `cerca` e `ricorda` di Bubo. Le cartelle escluse `hidden` restano chiuse a ogni strumento. */
export function questionSession(question: Pick<CopilotQuestion, "id" | "cwd" | "model" | "effort" | "brain" | "hidden">,
                                askPermission: AskPermission, askBubo?: AskBubo): SessionConfig {
  const hidden = question.hidden ?? [];
  return {
    clientName: "bubo",
    workingDirectory: question.cwd,
    model: question.model,
    reasoningEffort: question.effort,
    streaming: true,
    enableConfigDiscovery: true,
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
