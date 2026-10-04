import { expect, test } from "bun:test";
import type { ModelUsage, SDKMessage } from "@anthropic-ai/claude-agent-sdk";
import { restoredFrom, UsageReader } from "./usage";

// Campi del `result` registrato con `/context` (costo 0) da `claude` 2.1.286 in un CLAUDE_CONFIG_DIR isolato.
function result(session: string, cost: number, modelUsage: Record<string, Partial<ModelUsage>> = {},
                subtype: "success" | "error_during_execution" = "success"): SDKMessage {
  return {
    type: "result", subtype, is_error: subtype !== "success", duration_ms: 33, duration_api_ms: 0, num_turns: 1,
    stop_reason: null, session_id: session, total_cost_usd: cost, permission_denials: [], errors: [], result: "",
    uuid: "bbf20396-3af0-40f9-9926-616a25cb010a",
    usage: { input_tokens: 0, output_tokens: 0, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 },
    modelUsage: Object.fromEntries(Object.entries(modelUsage).map(([model, usage]) => [model, {
      inputTokens: 0, outputTokens: 0, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, webSearchRequests: 0,
      costUSD: 0, contextWindow: 200000, maxOutputTokens: 64000, ...usage,
    }])),
  } as unknown as SDKMessage;
}

function assistant(id: string, model: string, input: number, output: number): SDKMessage {
  return {
    type: "assistant", parent_tool_use_id: null, session_id: "s", uuid: id,
    message: { id, model, content: [], usage: { input_tokens: input, output_tokens: output, cache_read_input_tokens: 2, cache_creation_input_tokens: 0 } },
  } as unknown as SDKMessage;
}

const sonnet = (costUSD: number, inputTokens = 100, outputTokens = 10) => ({ inputTokens, outputTokens, costUSD });

function readAll(reader: UsageReader, messages: SDKMessage[]) {
  for (const message of messages) reader.read(message);
  return reader.turn();
}

test("in streaming si tiene l'ultimo totale, mai la somma", () => {
  const turn = readAll(new UsageReader("subscription"), [
    result("s", 0.1, { "claude-sonnet-4-5": sonnet(0.1) }),
    result("s", 0.3, { "claude-sonnet-4-5": sonnet(0.3, 300, 30) }),
  ]);
  expect(turn).toEqual({ mode: "subscription", cost: 0.3, basis: "list", complete: true, models: [
    { model: "claude-sonnet-4-5", inputTokens: 300, outputTokens: 30, cacheReadTokens: 0, cacheWriteTokens: 0, thinkingTokens: 0, cost: 0.3 },
  ] });
});

test("/clear riparte con un altro session_id: si sommano gli ultimi totali di ciascuno", () => {
  const turn = readAll(new UsageReader("apiKey"), [
    result("s", 0.1, { "claude-sonnet-4-5": sonnet(0.1) }),
    result("s", 0.2, { "claude-sonnet-4-5": sonnet(0.2) }),
    result("t", 0.1, { "claude-sonnet-4-5": sonnet(0.1) }),
  ]);
  expect(turn?.cost).toBe(0.3);
  expect(turn?.mode).toBe("apiKey");
});

test("i subagent sono in modelUsage, con il loro modello", () => {
  const turn = readAll(new UsageReader("subscription"), [
    result("s", 0.25, { "claude-sonnet-4-5": sonnet(0.2), "claude-haiku-4-5": { ...sonnet(0.05), thinkingTokens: 4 } }),
  ]);
  expect(turn?.models.map((tokens) => [tokens.model, tokens.cost, tokens.thinkingTokens]))
    .toEqual([["claude-sonnet-4-5", 0.2, 0], ["claude-haiku-4-5", 0.05, 4]]);
});

test("un fork toglie il totale ripristinato dal transcript", () => {
  const restored = restoredFrom([
    { type: "user", uuid: "u" },
    { type: "cost-state", totalCostUSD: 0.05, modelUsage: { "claude-sonnet-4-5": { inputTokens: 1, outputTokens: 1, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, costUSD: 0.05 } } },
    { type: "cost-state", totalCostUSD: 0.125, modelUsage: { "claude-sonnet-4-5": { inputTokens: 10, outputTokens: 5, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, costUSD: 0.125 } } },
  ]);
  expect(restored?.cost).toBe(0.125);
  const turn = readAll(new UsageReader("subscription", restored), [result("f", 0.2, { "claude-sonnet-4-5": sonnet(0.2, 30, 15) })]);
  expect(turn?.cost).toBe(0.075);
  expect(turn?.models[0]).toMatchObject({ inputTokens: 20, outputTokens: 10, cost: 0.075 });
});

test("un fork di `/context` non costa nulla e non lascia modelli", () => {
  const restored = restoredFrom([{ type: "cost-state", totalCostUSD: 0.125, modelUsage: { "claude-sonnet-4-5": { inputTokens: 10, outputTokens: 5, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, costUSD: 0.125 } } }]);
  const turn = readAll(new UsageReader("subscription", restored), [result("f", 0.125, { "claude-sonnet-4-5": sonnet(0.125, 10, 5) })]);
  expect(turn).toMatchObject({ cost: 0, models: [] });
});

test("un crash con cifre a zero tiene l'ultimo result valido", () => {
  const turn = readAll(new UsageReader("apiKey"), [
    result("s", 0.4, { "claude-sonnet-4-5": sonnet(0.4) }),
    result("s", 0, {}, "error_during_execution"),
  ]);
  expect(turn).toMatchObject({ cost: 0.4, complete: true });
});

test("un crash senza result valido conta i token dei messaggi e segna la cifra incompleta", () => {
  const turn = readAll(new UsageReader("apiKey"), [
    assistant("m1", "claude-sonnet-4-5", 100, 1),
    assistant("m1", "claude-sonnet-4-5", 100, 40),
    assistant("m2", "claude-sonnet-4-5", 200, 20),
    result("s", 0, {}, "error_during_execution"),
  ]);
  expect(turn).toEqual({ mode: "apiKey", basis: "list", complete: false, models: [
    { model: "claude-sonnet-4-5", inputTokens: 300, outputTokens: 60, cacheReadTokens: 4, cacheWriteTokens: 0, thinkingTokens: 0 },
  ] });
});

test("costBasis unknown vince su list", () => {
  const turn = readAll(new UsageReader("apiKey"), [
    result("s", 0.3, { "claude-sonnet-4-5": { ...sonnet(0.1), costBasis: "list" }, "modello-nuovo": { ...sonnet(0.2), costBasis: "unknown" } }),
  ]);
  expect(turn?.basis).toBe("unknown");
});

test("`/context` senza turni: zero, completo", () => {
  expect(readAll(new UsageReader("subscription"), [result("s", 0)])).toEqual({ mode: "subscription", cost: 0, basis: "list", complete: true, models: [] });
});

test("niente da contare prima di un result o di un messaggio", () => {
  expect(new UsageReader("subscription").turn()).toBeUndefined();
});

// Transcript registrati come sequenze di messaggi: streaming, `/clear`, subagent, crash.
// Lo storico ha una voce per turno, l'ultima mandata; la sua somma è la somma dei `total_cost_usd` finali di ciascun
// `session_id`, scarto 0.
test("somma dello storico = somma dei total_cost_usd finali", () => {
  const turns: SDKMessage[][] = [
    [result("a", 0.1, { m: sonnet(0.1) }), result("a", 0.35, { m: sonnet(0.35) })],
    [result("b", 0.2, { m: sonnet(0.2) }), result("c", 0.07, { m: sonnet(0.07) })],
    [result("d", 0.5, { m: sonnet(0.3), h: sonnet(0.2) })],
    [result("e", 0.12, { m: sonnet(0.12) }), result("e", 0, {}, "error_during_execution")],
  ];
  const ledger = new Map<number, number>();
  turns.forEach((messages, index) => {
    const reader = new UsageReader("apiKey");
    for (const message of messages) {
      const turn = reader.read(message);
      if (turn?.cost !== undefined) ledger.set(index, turn.cost);
    }
  });
  const history = [...ledger.values()].reduce((sum, cost) => sum + cost, 0);
  expect(history.toFixed(10)).toBe((0.35 + 0.2 + 0.07 + 0.5 + 0.12).toFixed(10));
});

test("a ogni risposta la stima dei token finora, finché non arriva il result", () => {
  const reader = new UsageReader("apiKey");
  expect(reader.estimate()).toBeUndefined();
  reader.read(assistant("m1", "claude-sonnet-4-5", 100, 1));
  reader.read(assistant("m1", "claude-sonnet-4-5", 100, 40));
  expect(reader.estimate()).toEqual({ mode: "apiKey", basis: "list", complete: false, models: [
    { model: "claude-sonnet-4-5", inputTokens: 100, outputTokens: 40, cacheReadTokens: 2, cacheWriteTokens: 0, thinkingTokens: 0 },
  ] });
  reader.read(result("s", 0.3, { "claude-sonnet-4-5": sonnet(0.3) }));
  expect(reader.estimate()).toBeUndefined();
});
