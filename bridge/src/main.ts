// Ponte agente di Bubo: JSON su righe, stdin → comandi, stdout → eventi.
// Protocollo in Bubo/Agent/BridgeMessage.swift; stessa versione nei due lati.
import { query, type Query } from "@anthropic-ai/claude-agent-sdk";
import { createInterface } from "node:readline";

const version = 1;

type Command =
  | { v: number; type: "ask"; id: string; prompt: string; cwd: string }
  | { v: number; type: "cancel"; id: string };

type Event =
  | { type: "ready" }
  | { type: "text"; id: string; text: string }
  | { type: "done"; id: string }
  | { type: "error"; id?: string; message: string };

function send(event: Event) {
  process.stdout.write(JSON.stringify({ v: version, ...event }) + "\n");
}

// Swift ha già costruito l'ambiente da zero: il ponte lo passa a `claude` così com'è,
// meno le proprie variabili, e con la memoria automatica spenta nelle Domande.
const { BUBO_CLAUDE_PATH: claudePath, ...inherited } = process.env;
const childEnv = { ...inherited, CLAUDE_CODE_DISABLE_AUTO_MEMORY: "1" };

const running = new Map<string, Query>();

async function ask(id: string, prompt: string, cwd: string) {
  const conversation = query({
    prompt,
    options: {
      cwd,
      env: childEnv,
      pathToClaudeCodeExecutable: claudePath,
      // Finché non c'è la fiducia per cartella (#266), mai hook, env o MCP del repo.
      settingSources: ["user"],
      includePartialMessages: true,
      persistSession: false,
    },
  });
  running.set(id, conversation);
  try {
    for await (const message of conversation) {
      if (message.type === "stream_event" && message.event.type === "content_block_delta"
          && message.event.delta.type === "text_delta") {
        send({ type: "text", id, text: message.event.delta.text });
      } else if (message.type === "result") {
        if (message.subtype === "success" && !message.is_error) send({ type: "done", id });
        else send({ type: "error", id, message: message.subtype === "success" ? message.result : message.subtype });
      }
    }
  } catch (error) {
    send({ type: "error", id, message: error instanceof Error ? error.message : String(error) });
  } finally {
    running.delete(id);
  }
}

if (!claudePath) {
  send({ type: "error", message: "BUBO_CLAUDE_PATH mancante" });
  process.exit(1);
}

const lines = createInterface({ input: process.stdin });
lines.on("line", (line) => {
  let command: Command;
  try {
    command = JSON.parse(line);
  } catch {
    send({ type: "error", message: "riga non JSON" });
    return;
  }
  if (command.v !== version) {
    send({ type: "error", message: `versione ${command.v} non supportata, attesa ${version}` });
    return;
  }
  switch (command.type) {
    case "ask": void ask(command.id, command.prompt, command.cwd); break;
    case "cancel": void running.get(command.id)?.interrupt(); break;
  }
});
// stdin chiuso: Bubo è uscito o ha chiuso il ponte.
lines.on("close", () => process.exit(0));
send({ type: "ready" });
