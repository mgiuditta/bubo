// Le Domande via Copilot (ADR 0011): il Copilot SDK lancia il `copilot` dell'utente, con il suo login, in una sessione
// senza tool, o con il Secondo cervello solo `cerca` e `ricorda` di Bubo (#678). Verso Bubo i messaggi neutri del
// ponte: testo in streaming, token (`usage`), chi ha risposto, fine.
import { CopilotClient, defineTool, RuntimeConnection, type CopilotSession, type ModelInfo, type PermissionRequestResult,
  type SessionConfig, type SessionEvent, type Tool } from "@github/copilot-sdk";
import { dirname } from "node:path";
import { z } from "zod";
import { close, withFolderFirst } from "./copilot";
import { clean } from "./permission";
import type { AnsweredBy } from "./router";
import { rememberCall, rememberTool, searchCall, searchTool, type BuboToolCall } from "./tools";
import type { TurnUsage } from "./usage";

type ReasoningEffort = NonNullable<SessionConfig["reasoningEffort"]>;

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
  | { type: "copilotModels"; id: string; models: CopilotModel[] };

export type CopilotQuestion = {
  id: string;
  prompt: string;
  /** Il `copilot` dell'utente, assoluto. */
  copilot: string;
  /** Una cartella vuota di Bubo: nessuna istruzione di Progetto arriva a `copilot`. */
  cwd: string;
  model?: string;
  effort?: ReasoningEffort;
  /** Profilo e Regole del Secondo cervello, con il consenso dell'utente: in coda al prompt di sistema, con `cerca` e
   * `ricorda`. Senza, una sessione senza strumenti né note. */
  brain?: string;
};

/** Manda a Bubo una chiamata a `cerca` o `ricorda` e aspetta il testo con cui risponde (`found`). */
export type AskBubo = (call: BuboToolCall) => Promise<string>;

/** Quanto ha aspettato una Domanda: dal comando di Bubo al primo testo, e dall'invio del prompt al primo testo. */
export type FirstToken = { sinceAsked: number; sinceSent: number };

// Una Domanda non usa strumenti di `copilot`: nessuno è disponibile, e una Richiesta che arrivasse comunque è respinta.
export const refused: PermissionRequestResult = { kind: "reject", feedback: "Le Domande di Bubo non usano strumenti." };

/** `cerca` e `ricorda` di Bubo come strumenti della sessione della Domanda `conversation`: rispondono da Bubo, senza
 * Richiesta di permesso, e ogni scrittura va nel registro delle modifiche, annullabile. */
export function buboTools(conversation: string, askBubo: AskBubo): Tool<any>[] {
  const search = z.object(searchTool.shape);
  const remember = z.object(rememberTool.shape);
  return [
    defineTool(searchTool.name, {
      description: searchTool.description, parameters: search, skipPermission: true, defer: "never",
      handler: (args) => askBubo(searchCall(search.parse(args), conversation)),
    }),
    defineTool(rememberTool.name, {
      description: rememberTool.description, parameters: remember, skipPermission: true, defer: "never",
      handler: (args) => askBubo(rememberCall(remember.parse(args), conversation)),
    }),
  ];
}

/** La sessione di una Domanda: nessuno strumento integrato né MCP, e ogni Richiesta respinta. Con il Secondo cervello
 * (`brain` e `askBubo`) Profilo e Regole in coda al prompt di sistema, e solo `cerca` e `ricorda` di Bubo. */
export function questionSession(question: Pick<CopilotQuestion, "id" | "cwd" | "model" | "effort" | "brain">,
                                askBubo?: AskBubo): SessionConfig {
  return {
    clientName: "bubo",
    workingDirectory: question.cwd,
    model: question.model,
    reasoningEffort: question.effort,
    streaming: true,
    ...(question.brain && askBubo
      ? { tools: buboTools(question.id, askBubo), availableTools: [`custom:${searchTool.name}`, `custom:${rememberTool.name}`],
          systemMessage: { mode: "append" as const, content: question.brain } }
      : { availableTools: [] }),
    enableSkills: false,
    enableOnDemandInstructionDiscovery: false,
    onPermissionRequest: () => refused,
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

  /** `askBubo` risponde a `cerca` e `ricorda` delle Domande con il Secondo cervello; senza, nessuna li riceve. */
  constructor(private readonly send: (event: CopilotQuestionEvent) => void,
              private readonly environment: Record<string, string>,
              private readonly askBubo?: AskBubo) {}

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
      session = await client.createSession(questionSession(question, this.askBubo));
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
