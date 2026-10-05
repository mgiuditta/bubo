#!/usr/bin/env bun
// Un `copilot` finto per i test di `copilot-question.ts`: parla il JSON-RPC del Copilot SDK su stdio, senza rete e
// senza turni pagati. Il prompt sceglie la scena:
// - "sessione": risponde con gli strumenti chiesti dalla sessione, il modello e i token visti dal processo;
// - "note": chiama `cerca` e poi `ricorda` e risponde con i loro risultati;
// - "strumento": chiede il permesso di eseguire un comando e risponde con la decisione ricevuta;
// - "leggi <percorso>" e "scrivi <percorso>": passano dall'hook prima dello strumento (`view`, `create`) e poi chiedono
//   il permesso di leggere o scrivere; rispondono "negato: <motivo>" se l'hook nega, o con la decisione ricevuta;
// - "chiedi <json>": fa a Bubo la domanda `<json>` (`userInput.request`, come `ask_user`) e risponde con la risposta
//   ricevuta, in JSON; se il turno si ferma prima, con `session.abort`, finisce lì;
// - "lungo": comincia a rispondere e aspetta `session.abort`;
// - "errore": finisce con `session.error` di rete; "crediti": con `session.error` di Quota finita;
// - altro: risponde "Ciao mondo", con i token di due chiamate al modello e di un subagent.
import { randomUUID } from "node:crypto";

let buffer = Buffer.alloc(0);
const sessions = new Map();
const permissions = new Map();
const toolResults = new Map();
// Le risposte di Bubo alle richieste del finto `copilot` (`hooks.invoke`), per id.
const replies = new Map();
let nextRequest = 1;

function request(method, params) {
  const id = `fake-${nextRequest++}`;
  const reply = new Promise((resolve) => replies.set(id, resolve));
  write({ id, method, params });
  return reply;
}

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
      hooks: session.hooks ?? false,
      enableConfigDiscovery: session.enableConfigDiscovery ?? false,
      instructionDiscovery: session.instructionDiscovery ?? null,
      tools: session.tools,
      systemMessage: session.systemMessage ?? null,
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
  } else if (prompt.startsWith("leggi ") || prompt.startsWith("scrivi ")) {
    const isRead = prompt.startsWith("leggi ");
    const path = prompt.slice(prompt.indexOf(" ") + 1);
    const hook = await request("hooks.invoke", { sessionId, hookType: "preToolUse",
      input: { toolName: isRead ? "view" : "create", toolArgs: { path }, timestamp: Date.now(), cwd: session.cwd } });
    if (hook?.output?.permissionDecision === "deny") {
      say(`negato: ${hook.output.permissionDecisionReason}`);
      idle();
      return;
    }
    const requestId = randomUUID();
    const answer = new Promise((resolve) => permissions.set(requestId, resolve));
    emit(sessionId, "permission.requested", {
      requestId,
      permissionRequest: isRead
        ? { kind: "read", path, intention: "Legge" }
        : { kind: "write", fileName: path, intention: "Scrive", diff: "", canOfferSessionApproval: false },
    });
    say((await answer).kind);
    idle();
  } else if (prompt === "note") {
    const call = (toolName, args) => {
      const requestId = randomUUID();
      const result = new Promise((resolve) => toolResults.set(requestId, resolve));
      emit(sessionId, "external_tool.requested", { requestId, sessionId, toolCallId: randomUUID(), toolName, arguments: args });
      return result;
    };
    say(await call("cerca", { testo: "gatto", fonte: "secondo-cervello" }));
    say(" | ");
    say(await call("ricorda", { testo: "Il gatto si chiama Bubo", titolo: "Gatto" }));
    idle();
  } else if (prompt.startsWith("chiedi ")) {
    let stopped = false;
    session.stop = () => {
      stopped = true;
      emit(sessionId, "abort", { reason: "user" });
      idle();
    };
    const answer = await request("userInput.request", { sessionId, ...JSON.parse(prompt.slice("chiedi ".length)) });
    if (stopped) return;
    say(JSON.stringify(answer ?? null));
    idle();
  } else if (prompt === "lungo") {
    say("Comincio");
    session.stop = () => {
      emit(sessionId, "abort", { reason: "user" });
      idle();
    };
  } else if (prompt === "errore") {
    emit(sessionId, "session.error", { errorType: "query", message: "fetch failed" });
    idle();
  } else if (prompt === "crediti") {
    emit(sessionId, "session.error", { errorType: "quota", errorCode: "quota_exceeded", message: "Crediti finiti" });
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
  if (message.method === undefined) {
    replies.get(message.id)?.(message.result);
    replies.delete(message.id);
    return;
  }
  const { id, method, params } = message;
  const reply = (result) => write({ id, result });
  switch (method) {
    case "connect": return reply({ protocolVersion: 3 });
    case "models.list": return reply({ models });
    case "session.create": {
      const sessionId = params.sessionId ?? randomUUID();
      sessions.set(sessionId, { model: params.model, effort: params.reasoningEffort, availableTools: params.availableTools,
        hooks: params.hooks, enableConfigDiscovery: params.enableConfigDiscovery,
        instructionDiscovery: params.enableOnDemandInstructionDiscovery, cwd: params.workingDirectory,
        tools: (params.tools ?? []).map((tool) => ({ name: tool.name, skipPermission: tool.skipPermission ?? false })),
        systemMessage: params.systemMessage });
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
    case "session.tools.handlePendingToolCall":
      toolResults.get(params.requestId)?.(params.result ?? `errore: ${params.error}`);
      toolResults.delete(params.requestId);
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
