// Il router di Bubo (feature 10) dal lato del ponte: lo sforzo chiesto, il catalogo dei modelli e chi ha risposto.
import type { EffortLevel, HookCallbackMatcher, HookInput, ModelInfo, SDKMessage } from "@anthropic-ai/claude-agent-sdk";

const effortLevels: readonly EffortLevel[] = ["low", "medium", "high", "xhigh", "max"];

/** Lo sforzo chiesto da Bubo; un valore che l'SDK non conosce vale "nessuno", cioè il default del modello. */
export function effortOf(value: unknown): EffortLevel | undefined {
  return effortLevels.find((level) => level === value);
}

/** Una riga del catalogo, solo con quello che serve al router. */
export type CatalogEntry = { value: string; resolvedModel?: string; displayName: string; supportedEffortLevels?: EffortLevel[] };

/** Il catalogo di `supportedModels()`: un modello senza sforzo (Haiku) resta senza `supportedEffortLevels`. */
export function catalogOf(models: ModelInfo[]): CatalogEntry[] {
  return models.map((model) => ({
    value: model.value,
    ...(model.resolvedModel && { resolvedModel: model.resolvedModel }),
    displayName: model.displayName,
    ...(model.supportsEffort !== false && model.supportedEffortLevels?.length
      && { supportedEffortLevels: model.supportedEffortLevels }),
  }));
}

/** Chi ha risposto davvero a un turno: il modello del thread principale e lo sforzo effettivo, se il modello ne ha. */
export type AnsweredBy = { model: string; effort?: string };

/**
 * Segue il modello dai messaggi dell'assistente e lo sforzo dall'hook `Stop`, che lo dà "dopo l'eventuale
 * declassamento silenzioso" e non lo dà per i modelli senza sforzo. Solo il thread principale: i subagent no.
 */
export class AnswerWitness {
  private model?: string;
  private effort?: string;

  read(message: SDKMessage) {
    if (message.type === "assistant" && !message.error && message.parent_tool_use_id === null) {
      this.model = message.message.model;
    }
  }

  readonly stopHook: HookCallbackMatcher = {
    hooks: [async (input: HookInput) => {
      if (input.hook_event_name === "Stop" && input.agent_id === undefined) this.effort = input.effort?.level;
      return {};
    }],
  };

  /** `undefined` finché nessun messaggio dell'assistente ha detto il modello. */
  answeredBy(): AnsweredBy | undefined {
    if (!this.model) return undefined;
    return { model: this.model, ...(this.effort && { effort: this.effort }) };
  }
}
