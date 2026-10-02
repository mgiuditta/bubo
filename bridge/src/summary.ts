import type { CanUseTool, Options, Query, SDKAssistantMessageError, SDKMessage } from "@anthropic-ai/claude-agent-sdk";
import { turnFailure, type TurnFailure } from "./failure";
import { limitFromRateLimit, type Limit } from "./quota";
import { UsageReader, type TurnUsage } from "./usage";

// Il Riassunto di Sessione (spec 13, #118): un solo turno del modello leggero, senza strumenti, senza impostazioni
// né memoria di nessun Progetto e senza copia della conversazione. Il testo arriva già filtrato da Bubo.

/** Gli eventi di un riassunto: gli stessi di `ask`, così Bubo li legge allo stesso modo. */
export type SummaryEvent =
  | { type: "text"; id: string; text: string }
  | { type: "done"; id: string }
  | ({ type: "usage"; id: string } & TurnUsage)
  | ({ type: "limit"; id: string } & Limit)
  | { type: "signInRequired"; id: string }
  | ({ type: "error"; id: string; message: string } & TurnFailure);

// Nessuno strumento passa, nemmeno se la CLI ne offrisse uno.
const refuseAll: CanUseTool = async () => ({ behavior: "deny", message: "Il riassunto non usa strumenti." });

/**
 * Le opzioni di `query()` per un riassunto in `cwd`, una cartella vuota di Bubo (niente CLAUDE.md né `.mcp.json`):
 * un turno, 0 strumenti, 0 fonti di impostazioni, 0 persistenza.
 */
export function summaryOptions(cwd: string, model: string | undefined, env: Record<string, string | undefined>,
                               claudePath: string | undefined): Options {
  return {
    cwd,
    model,
    env: { ...env, CLAUDE_CODE_DISABLE_AUTO_MEMORY: "1" },
    pathToClaudeCodeExecutable: claudePath,
    maxTurns: 1,
    tools: [],
    allowedTools: [],
    mcpServers: {},
    strictMcpConfig: true,
    settingSources: [],
    persistSession: false,
    canUseTool: refuseAll,
  };
}

/** Riassume `prompt` con `model`, mandando a `send` il testo, le cifre del turno e la fine. */
export async function summarize(id: string, prompt: string, options: Options,
                                ask: (request: { prompt: string; options: Options }) => Query,
                                send: (event: SummaryEvent) => void) {
  const conversation = ask({ prompt, options });
  let usage: UsageReader | undefined;
  let failure: SDKAssistantMessageError | undefined;
  let limit: Limit | undefined;
  let succeeded = false;
  try {
    for await (const message of conversation as AsyncIterable<SDKMessage>) {
      if (message.type === "system" && message.subtype === "init") {
        usage ??= new UsageReader(message.apiKeySource === "none" ? "subscription" : "apiKey");
      }
      const turn = usage?.read(message);
      if (turn) send({ type: "usage", id, ...turn });
      if (message.type === "rate_limit_event") {
        limit = limitFromRateLimit(message.rate_limit_info) ?? limit;
      } else if (message.type === "assistant" && message.error) {
        failure = message.error;
      } else if (message.type === "assistant") {
        const text = message.message.content.flatMap((block) => (block.type === "text" ? [block.text] : [])).join("");
        if (text) send({ type: "text", id, text });
      } else if (message.type === "result") {
        if (message.subtype === "success" && !message.is_error) succeeded = true;
        else if (limit) send({ type: "limit", id, ...limit });
        else if (failure === "authentication_failed") send({ type: "signInRequired", id });
        else send({ type: "error", id, message: message.subtype === "success" ? message.result : message.subtype,
                    ...turnFailure(failure, undefined) });
      }
    }
    if (succeeded) send({ type: "done", id });
  } catch (error) {
    send({ type: "error", id, message: error instanceof Error ? error.message : String(error) });
  }
}
