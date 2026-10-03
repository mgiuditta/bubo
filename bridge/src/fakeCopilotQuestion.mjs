#!/usr/bin/env bun
// Un `copilot` finto per i test di `copilot-question.ts`: parla il JSON-RPC del Copilot SDK su stdio, senza rete e
// senza turni pagati. Il prompt sceglie la scena:
// - "sessione": risponde con gli strumenti chiesti dalla sessione, il modello e i token visti dal processo;
// - "strumento": chiede il permesso di eseguire un comando e risponde con la decisione ricevuta;
// - "lungo": comincia a rispondere e aspetta `session.abort`;
// - "errore": finisce con `session.error`;
// - altro: risponde "Ciao mondo", con i token di due chiamate al modello e di un subagent.
import { randomUUID } from "node:crypto";

let buffer = Buffer.alloc(0);
const sessions = new Map();
const permissions = new Map();

function write(message) {
  const body = Buffer.from(JSON.stringify({ jsonrpc: "2.0", ...message }));
  process.stdout.write(`Content-Length: ${body.length}\r\n\r\n`);
  process.stdout.write(body);
}

function emit(sessionId, type, data, extra = {}) {
  const event = { id: randomUUID(), timestamp: new Date().toISOString(), parentId: null, ephemeral: true, type, data, ...extra };
  write({ method: "session.event", params: { sessionId, event } });
}

const usage = (model, inputTokens, outputTokens) =>
  ({ model, inputTokens, outputTokens, cacheReadTokens: 10, reasoningTokens: 5, reasoningEffort: "low" });

async function play(sessionId, prompt) {
  const session = sessions.get(sessionId);
  const say = (text) => emit(sessionId, "assistant.message_delta", { deltaContent: text, messageId: "m1" });
  const idle = () => emit(sessionId, "session.idle", {});
  if (prompt === "sessione") {
    say(JSON.stringify({
      availableTools: session.availableTools ?? null,
      model: session.model ?? null,
      effort: session.effort ?? null,
      tokens: ["GH_TOKEN", "GITHUB_TOKEN", "COPILOT_GITHUB_TOKEN"].filter((name) => process.env[name] !== undefined),
    }));
    idle();
  } else if (prompt === "strumento") {
    const requestId = randomUUID();
    const answer = new Promise((resolve) => permissions.set(requestId, resolve));
    emit(sessionId, "permission.requested", {
      requestId,
      permissionRequest: { kind: "shell", fullCommandText: "rm -rf /", intention: "Pulisce", commands: [], possiblePaths: [], possibleUrls: [], hasWriteFileRedirection: false, canOfferSessionApproval: false },
    });
    const result = await answer;
    say(result.kind);
    idle();
  } else if (prompt === "lungo") {
    say("Comincio");
    session.stop = () => {
      emit(sessionId, "abort", { reason: "user" });
      idle();
    };
  } else if (prompt === "errore") {
    emit(sessionId, "session.error", { errorType: "quota", message: "Crediti finiti" });
    idle();
  } else {
    say("Ciao");
    emit(sessionId, "assistant.usage", usage("gpt-6", 100, 20));
    say(" mondo");
    emit(sessionId, "assistant.usage", usage("gpt-6", 50, 10));
    emit(sessionId, "assistant.usage", usage("gpt-6-mini", 999, 999), { agentId: "sub" });
    idle();
  }
}

const models = [
  { id: "gpt-6", name: "GPT-6", capabilities: { supports: { vision: true, reasoningEffort: true }, limits: { max_context_window_tokens: 1 } },
    policy: { state: "enabled", terms: "" }, billing: { multiplier: 1 }, supportedReasoningEfforts: ["low", "high"], defaultReasoningEffort: "low" },
  { id: "grok-5", name: "Grok 5", capabilities: { supports: { vision: false, reasoningEffort: false }, limits: { max_context_window_tokens: 1 } } },
  { id: "spento", name: "Spento", capabilities: { supports: { vision: false, reasoningEffort: false }, limits: { max_context_window_tokens: 1 } },
    policy: { state: "disabled", terms: "" } },
];

function handle(message) {
  if (message.method === undefined) return;
  const { id, method, params } = message;
  const reply = (result) => write({ id, result });
  switch (method) {
    case "connect": return reply({ protocolVersion: 3 });
    case "models.list": return reply({ models });
    case "session.create": {
      const sessionId = params.sessionId ?? randomUUID();
      sessions.set(sessionId, { model: params.model, effort: params.reasoningEffort, availableTools: params.availableTools });
      return reply({ sessionId, workspacePath: params.workingDirectory });
    }
    case "session.send":
      reply({ messageId: randomUUID() });
      void play(params.sessionId, params.prompt);
      return;
    case "session.abort":
      sessions.get(params.sessionId)?.stop?.();
      return reply({});
    case "session.permissions.handlePendingPermissionRequest":
      permissions.get(params.requestId)?.(params.result);
      permissions.delete(params.requestId);
      return reply({ success: true });
    default:
      if (id !== undefined) reply({ success: true });
  }
}

process.stdin.on("data", (chunk) => {
  buffer = Buffer.concat([buffer, chunk]);
  for (;;) {
    const end = buffer.indexOf("\r\n\r\n");
    if (end < 0) return;
    const length = Number(/Content-Length: (\d+)/i.exec(buffer.subarray(0, end).toString())?.[1]);
    if (buffer.length < end + 4 + length) return;
    const body = buffer.subarray(end + 4, end + 4 + length).toString();
    buffer = buffer.subarray(end + 4 + length);
    handle(JSON.parse(body));
  }
});
process.stdin.on("end", () => process.exit(0));
