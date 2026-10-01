// UsageReader (feature 18): token e cifra di un turno dal `result` dell'SDK, con unità e origine.
// Ogni `result` porta il totale progressivo della query: si tiene l'ultimo, mai la somma. `/clear` riparte da zero
// con un altro `session_id`, quindi si tiene l'ultimo per `session_id` e si sommano quelli. Un fork riparte dal
// totale salvato nel transcript (`cost-state`): si toglie, perché quei turni sono della Cronologia CLI.
import type { ModelUsage, SDKMessage, SDKResultMessage, SessionStoreEntry } from "@anthropic-ai/claude-agent-sdk";

/** Abbonamento: la cifra è Valore a listino. API key: è Spesa. */
export type Mode = "subscription" | "apiKey";
/** Da quale tabella viene la stima a listino dell'SDK; `unknown` è un prezzo indovinato. */
export type Basis = "list" | "managed" | "unknown";

export type ModelTokens = {
  model: string;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  thinkingTokens: number;
  /** Assente quando il turno si è interrotto senza un `result` valido. */
  cost?: number;
};

/** Il turno com'è finora: `cost` assente e `complete` falso dopo un crash senza `result` valido. */
export type TurnUsage = { mode: Mode; cost?: number; basis: Basis; complete: boolean; models: ModelTokens[] };

/** Il totale ripristinato da un `resume`: costo e token per modello. */
export type Restored = { cost: number; models: Record<string, Pick<ModelUsage, "inputTokens" | "outputTokens" | "cacheReadInputTokens" | "cacheCreationInputTokens" | "thinkingTokens" | "costUSD">> };

// Le differenze tra numeri in virgola mobile lasciano code (0.30000000000000004): bastano dieci decimali.
const tidy = (value: number) => Number(value.toFixed(10));

const basisRank: Basis[] = ["list", "managed", "unknown"];

function isZeroed(result: SDKResultMessage) {
  return result.total_cost_usd === 0 && Object.values(result.modelUsage).every((usage) => usage.costUSD === 0
    && usage.inputTokens === 0 && usage.outputTokens === 0);
}

/** L'ultimo `cost-state` di un transcript letto con `importSessionToStore`: il totale che un `resume` ripristina. */
export function restoredFrom(entries: SessionStoreEntry[]): Restored | undefined {
  const state = entries.findLast((entry) => entry.type === "cost-state") as
    { totalCostUSD?: unknown; modelUsage?: unknown } | undefined;
  if (typeof state?.totalCostUSD !== "number" || typeof state.modelUsage !== "object" || !state.modelUsage) return undefined;
  return { cost: state.totalCostUSD, models: state.modelUsage as Restored["models"] };
}

export class UsageReader {
  private readonly results = new Map<string, SDKResultMessage>();
  // Il primo `session_id`: l'unico a cui un fork aggiunge il totale ripristinato.
  private first?: string;
  // Dai messaggi dell'assistente, l'ultimo per `message.id`: i token di un turno interrotto senza `result`.
  private readonly partial = new Map<string, { model: string; input: number; output: number; read: number; write: number }>();

  constructor(private readonly mode: Mode, private readonly restored?: Restored) {}

  /** Legge `message`; restituisce il turno aggiornato quando arriva un `result`. */
  read(message: SDKMessage): TurnUsage | undefined {
    if (message.type === "assistant" && !message.error) {
      const usage = message.message.usage;
      this.partial.set(message.message.id, {
        model: message.message.model, input: usage.input_tokens, output: usage.output_tokens,
        read: usage.cache_read_input_tokens ?? 0, write: usage.cache_creation_input_tokens ?? 0,
      });
    }
    if (message.type !== "result") return undefined;
    this.first ??= message.session_id;
    // Un `result` azzerato da un crash non cancella l'ultimo valido.
    if (!isZeroed(message) || !this.results.has(message.session_id)) this.results.set(message.session_id, message);
    return this.turn();
  }

  /** Il turno com'è adesso; `undefined` se non è arrivato nulla da contare. */
  turn(): TurnUsage | undefined {
    const valid = [...this.results.entries()].filter(([, result]) => !isZeroed(result));
    if (!valid.length && this.partial.size) return this.fromMessages();
    if (!this.results.size) return undefined;
    const models = new Map<string, ModelTokens>();
    let cost = 0;
    let basis: Basis = "list";
    for (const [session, result] of valid) {
      const restored = session === this.first ? this.restored : undefined;
      cost += result.total_cost_usd - (restored?.cost ?? 0);
      for (const [model, usage] of Object.entries(result.modelUsage)) {
        const before = restored?.models[model];
        const tokens = models.get(model) ?? { model, inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, thinkingTokens: 0, cost: 0 };
        tokens.inputTokens += usage.inputTokens - (before?.inputTokens ?? 0);
        tokens.outputTokens += usage.outputTokens - (before?.outputTokens ?? 0);
        tokens.cacheReadTokens += usage.cacheReadInputTokens - (before?.cacheReadInputTokens ?? 0);
        tokens.cacheWriteTokens += usage.cacheCreationInputTokens - (before?.cacheCreationInputTokens ?? 0);
        tokens.thinkingTokens += (usage.thinkingTokens ?? 0) - (before?.thinkingTokens ?? 0);
        tokens.cost = tidy(tokens.cost! + usage.costUSD - (before?.costUSD ?? 0));
        models.set(model, tokens);
        const used = usage.costBasis ?? "list";
        if (basisRank.indexOf(used) > basisRank.indexOf(basis)) basis = used;
      }
    }
    // Un modello che c'era già prima del fork e non ha lavorato in questo turno non conta.
    const worked = [...models.values()].filter((tokens) => tokens.inputTokens || tokens.outputTokens
      || tokens.cacheReadTokens || tokens.cacheWriteTokens || tokens.cost);
    return { mode: this.mode, cost: tidy(cost), basis, complete: true, models: worked };
  }

  private fromMessages(): TurnUsage {
    const models = new Map<string, ModelTokens>();
    for (const usage of this.partial.values()) {
      const tokens = models.get(usage.model) ?? { model: usage.model, inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, thinkingTokens: 0 };
      tokens.inputTokens += usage.input;
      tokens.outputTokens += usage.output;
      tokens.cacheReadTokens += usage.read;
      tokens.cacheWriteTokens += usage.write;
      models.set(usage.model, tokens);
    }
    return { mode: this.mode, basis: "list", complete: false, models: [...models.values()] };
  }
}
