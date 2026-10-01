import { expect, test } from "bun:test";
import type { SDKMessage } from "@anthropic-ai/claude-agent-sdk";
import { progress } from "./activity";

// Sequenze registrate con Claude Code 2.1.286 e SDK 0.3.286 il 01/10/2026, CLAUDE_CONFIG_DIR vuoto,
// CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS=1, API key non valida: costo 0. Solo i campi che contano.
const state = (state: string) => ({ type: "system", subtype: "session_state_changed", state });
const assistant = (text: string, extra: object = {}) =>
  ({ type: "assistant", parent_tool_use_id: null, message: { content: [{ type: "text", text }] }, ...extra });

// `/context`: comando locale, nessun turno del modello.
const context = [
  state("running"),
  { type: "system", subtype: "init" },
  assistant("## Context Usage\n\n**Model:** claude-opus-5-5  \n**Tokens:** 16k / 1m (2%)"),
  { type: "result", subtype: "success", is_error: false },
  state("idle"),
];

// Un prompt qualunque con la chiave non valida: dieci tentativi, poi l'errore; `idle` arriva dopo il `result`.
const failed = [
  state("running"),
  { type: "system", subtype: "init" },
  ...Array.from({ length: 10 }, () => ({ type: "system", subtype: "api_retry" })),
  assistant("Failed to authenticate. API Error: 401 API key is invalid.", { error: "authentication_failed" }),
  { type: "result", subtype: "success", is_error: true },
  state("idle"),
];

const replay = (messages: object[]) => messages.map((message) => progress(message as SDKMessage)).filter(Boolean);

test("/context registrato: running, riassunto senza markdown, idle", () => {
  expect(replay(context)).toEqual([
    { type: "state", state: "running" },
    { type: "summary", text: "Context Usage" },
    { type: "state", state: "idle" },
  ]);
});

test("errore registrato: il messaggio d'errore non diventa il riassunto", () => {
  expect(replay(failed)).toEqual([{ type: "state", state: "running" }, { type: "state", state: "idle" }]);
});

// Dai tipi dell'SDK, non registrata: servirebbe un turno del modello.
test("permesso in attesa e subagent: requires_action, e i messaggi del subagent non sono il riassunto", () => {
  expect(replay([
    state("running"),
    assistant("Eseguo i test."),
    state("requires_action"),
    state("running"),
    assistant("Leggo i file", { parent_tool_use_id: "toolu_1" }),
    state("idle"),
  ])).toEqual([
    { type: "state", state: "running" },
    { type: "summary", text: "Eseguo i test." },
    { type: "state", state: "requires_action" },
    { type: "state", state: "running" },
    { type: "state", state: "idle" },
  ]);
});

test("il riassunto è una riga di al più 200 caratteri", () => {
  const summary = progress(assistant("x".repeat(300)) as SDKMessage);
  expect(summary).toEqual({ type: "summary", text: "x".repeat(199) + "…" });
});
