#!/usr/bin/env bun
// Un `copilot` finto per i test di `copilot.ts`: parla il JSON-RPC del Copilot SDK su stdio (`--stdio`), senza rete e
// senza turni pagati. Il prompt sceglie la scena:
// - "scrivi": chiede il permesso di scrivere `nota.txt` nella cartella della sessione e la scrive solo se approvato;
// - "lungo": comincia a rispondere e aspetta `session.abort`;
// - "errore": finisce con `session.error`;
// - "ambiente": risponde con argomenti, cartella e token visti dal processo;
// - altro: risponde "Ciao mondo".
import { randomUUID } from "node:crypto";
import { writeFileSync } from "node:fs";
import { join } from "node:path";

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

async function play(sessionId, prompt) {
  const session = sessions.get(sessionId);
  const say = (text) => emit(sessionId, "assistant.message_delta", { deltaContent: text, messageId: "m1" }, true);
  const idle = () => emit(sessionId, "session.idle", {}, true);
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
  } else if (prompt === "lungo") {
    say("Comincio");
    session.stop = () => {
      emit(sessionId, "abort", { reason: "user" });
      idle();
    };
  } else if (prompt === "errore") {
    emit(sessionId, "session.error", { errorType: "quota", message: "Crediti finiti" });
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
  } else {
    say("Ciao");
    say(" mondo");
    emit(sessionId, "assistant.message", { content: "Ciao mondo", messageId: "m1" });
    idle();
  }
}

function handle(message) {
  if (message.method === undefined) return;
  const { id, method, params } = message;
  const reply = (result) => write({ id, result });
  switch (method) {
    case "connect": return reply({ protocolVersion: 3 });
    case "session.create": {
      const sessionId = params.sessionId ?? randomUUID();
      sessions.set(sessionId, { cwd: params.workingDirectory, model: params.model, effort: params.reasoningEffort });
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
