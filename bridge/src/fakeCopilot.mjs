#!/usr/bin/env bun
// Un `copilot` finto per i test di `copilot.ts`: parla il JSON-RPC del Copilot SDK su stdio (`--stdio`), senza rete e
// senza turni pagati. Il prompt sceglie la scena:
// - "scrivi": chiede il permesso di scrivere `nota.txt` nella cartella della sessione e la scrive solo se approvato;
// - "chiedi <json>": fa a Bubo la domanda `<json>` (`userInput.request`, come `ask_user`) e risponde con la risposta
//   ricevuta, in JSON; se il turno si ferma prima, con `session.abort`, finisce lì;
// - "lungo": comincia a rispondere e aspetta `session.abort`;
// - "errore": finisce con `session.error` di rete; "crediti": con `session.error` di Quota finita;
// - "token": due chiamate al modello, una di un subagente, con i loro token;
// - "ambiente": risponde con argomenti, cartella e token visti dal processo;
// - "attività": legge, modifica, crea e lancia uno shell, poi riassume;
// - "ricordi": risponde con i prompt di prima, letti dallo stato della sessione;
// - altro: risponde "Ciao mondo".
// Lo stato di ogni sessione sta in `.copilot-state/<id>.json` nella sua cartella, come `~/.copilot/session-state`:
// un nuovo processo la riprende con `session.resume`, e senza quel file la ripresa fallisce.
import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const stateOf = (cwd, sessionId) => join(cwd, ".copilot-state", `${sessionId}.json`);

function save(sessionId) {
  const { cwd, prompts } = sessions.get(sessionId);
  mkdirSync(join(cwd, ".copilot-state"), { recursive: true });
  writeFileSync(stateOf(cwd, sessionId), JSON.stringify({ prompts }));
}

let buffer = Buffer.alloc(0);
const sessions = new Map();

function write(message) {
  const body = Buffer.from(JSON.stringify({ jsonrpc: "2.0", ...message }));
  process.stdout.write(`Content-Length: ${body.length}\r\n\r\n`);
  process.stdout.write(body);
}

function emit(sessionId, type, data, ephemeral = false) {
  const event = { id: randomUUID(), timestamp: new Date().toISOString(), parentId: null, ephemeral, type, data };
  write({ method: "session.event", params: { sessionId, event } });
}

const permissions = new Map();
// Le risposte di Bubo alle richieste del finto `copilot` (`userInput.request`), per id.
const replies = new Map();
let nextRequest = 1;

function request(method, params) {
  const id = `fake-${nextRequest++}`;
  const reply = new Promise((resolve) => replies.set(id, resolve));
  write({ id, method, params });
  return reply;
}

async function play(sessionId, prompt) {
  const session = sessions.get(sessionId);
  const say = (text) => emit(sessionId, "assistant.message_delta", { deltaContent: text, messageId: "m1" }, true);
  const idle = () => emit(sessionId, "session.idle", {}, true);
  const earlier = session.prompts.slice(0, -1);
  emit(sessionId, "assistant.turn_start", { turnId: "t1" });
  if (prompt === "scrivi") {
    const requestId = randomUUID();
    const path = join(session.cwd, "nota.txt");
    const answer = new Promise((resolve) => permissions.set(requestId, resolve));
    emit(sessionId, "permission.requested", {
      requestId,
      permissionRequest: { kind: "write", fileName: path, diff: "+ciao", intention: "Scrive la nota", canOfferSessionApproval: true },
    });
    const result = await answer;
    if (result.kind === "approve-once") {
      writeFileSync(path, "ciao\n");
      say("Scritto");
    } else {
      say(`Rifiutato: ${result.feedback ?? ""}`);
    }
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
  } else if (prompt === "ambiente") {
    say(JSON.stringify({
      args: process.argv.slice(2),
      cwd: session.cwd,
      model: session.model ?? null,
      effort: session.effort ?? null,
      tokens: ["GH_TOKEN", "GITHUB_TOKEN", "COPILOT_GITHUB_TOKEN"].filter((name) => process.env[name] !== undefined),
    }));
    idle();
  } else if (prompt === "token") {
    const usage = (inputTokens, outputTokens) => ({ model: "gpt-6", inputTokens, outputTokens, cacheReadTokens: 10 });
    emit(sessionId, "assistant.usage", usage(100, 20), true);
    write({ method: "session.event", params: { sessionId, event: {
      id: randomUUID(), timestamp: new Date().toISOString(), parentId: null, ephemeral: true, agentId: "sub",
      type: "assistant.usage", data: usage(50, 10) } } });
    say("Fatto");
    idle();
  } else if (prompt === "attività") {
    const tool = (toolName, args) => {
      const toolCallId = randomUUID();
      emit(sessionId, "tool.execution_start", { toolCallId, toolName, arguments: args });
      emit(sessionId, "tool.execution_complete", { toolCallId, success: true, result: { content: "ok" } });
    };
    tool("view", { path: join(session.cwd, "a.txt") });
    tool("edit", { path: join(session.cwd, "a.txt"), old_str: "x", new_str: "  uno\ndue\n\nuno" });
    tool("create", { path: join(session.cwd, "b.txt"), file_text: "nuovo" });
    tool("str_replace_editor", { command: "view", path: join(session.cwd, "c.txt") });
    tool("bash", { command: "npm run dev" });
    emit(sessionId, "assistant.message", { content: "Riassunto del sub", messageId: "s1", parentToolCallId: "p1" });
    emit(sessionId, "assistant.message", { content: "## Ho letto e scritto\nAltro", messageId: "m3" });
    idle();
  } else if (prompt === "ricordi" || prompt.endsWith("Ora: ricordi")) {
    const text = prompt === "ricordi" ? `Prima: ${earlier.join(", ")}` : "Dalla copia";
    say(text);
    emit(sessionId, "assistant.message", { content: text, messageId: "m2" });
    idle();
  } else {
    say("Ciao");
    say(" mondo");
    emit(sessionId, "assistant.message", { content: "Ciao mondo", messageId: "m1" });
    idle();
  }
}

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
    case "session.create": {
      const sessionId = params.sessionId ?? randomUUID();
      sessions.set(sessionId, { cwd: params.workingDirectory, model: params.model, effort: params.reasoningEffort, prompts: [] });
      save(sessionId);
      return reply({ sessionId, workspacePath: params.workingDirectory });
    }
    case "session.resume": {
      const { sessionId, workingDirectory: cwd } = params;
      if (!existsSync(stateOf(cwd, sessionId))) {
        return write({ id, error: { code: -32603, message: `Session not found: ${sessionId}` } });
      }
      const { prompts } = JSON.parse(readFileSync(stateOf(cwd, sessionId), "utf8"));
      sessions.set(sessionId, { cwd, model: params.model, effort: params.reasoningEffort, prompts });
      return reply({ sessionId, workspacePath: cwd });
    }
    case "session.send":
      sessions.get(params.sessionId).prompts.push(params.prompt);
      save(params.sessionId);
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
