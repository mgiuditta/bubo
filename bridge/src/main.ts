// Ponte agente di Bubo: JSON su righe, stdin → comandi, stdout → eventi.
// Protocollo in Bubo/Agent/BridgeMessage.swift; stessa versione nei due lati.
import { createSdkMcpServer, query, tool, type Query, type SettingSource } from "@anthropic-ai/claude-agent-sdk";
import { randomUUID } from "node:crypto";
import { createInterface } from "node:readline";
import { z } from "zod";
import { quotaFromRateLimit, readQuota, type Quota } from "./quota";
import { settingSources } from "./settingSources";

const version = 3;

type Command =
  | { v: number; type: "ask"; id: string; prompt: string; cwd: string; settingSources?: unknown }
  | { v: number; type: "cancel"; id: string }
  | { v: number; type: "found"; id: string; text: string }
  | { v: number; type: "quota" };

type Event =
  | { type: "ready" }
  | { type: "text"; id: string; text: string }
  | { type: "done"; id: string }
  | { type: "error"; id?: string; message: string }
  | { type: "search"; id: string; query: string; project?: string }
  | ({ type: "quota" } & Quota);

function send(event: Event) {
  process.stdout.write(JSON.stringify({ v: version, ...event }) + "\n");
}

// Una Quota senza finestre non si manda: Bubo tiene ciò che sa, o non mostra nulla.
function sendQuota(quota: Quota) {
  if (quota.fiveHour || quota.sevenDay) send({ type: "quota", ...quota });
}

// Swift ha già costruito l'ambiente da zero: il ponte lo passa a `claude` così com'è,
// meno le proprie variabili, e con la memoria automatica spenta nelle Domande.
// CLAUDE_CODE_SANDBOXED farebbe passare per fidata qualunque cartella (#266): mai al figlio.
const { BUBO_CLAUDE_PATH: claudePath, CLAUDE_CODE_SANDBOXED: _sandboxed, ...inherited } = process.env;
const childEnv = { ...inherited, CLAUDE_CODE_DISABLE_AUTO_MEMORY: "1" };

const running = new Map<string, Query>();
const searches = new Map<string, (text: string) => void>();

// `cerca` chiede l'Indice a Bubo: i frammenti restano tra Bubo e Claude.
// Un server per conversazione: un'istanza MCP si collega a un solo trasporto.
function buboTools() {
  return createSdkMcpServer({
    name: "bubo",
    tools: [tool(
      "cerca",
      "Cerca per parole nell'Indice di Bubo: la memoria di Claude Code di tutti i Progetti e il CLAUDE.md dell'utente. Restituisce i frammenti con il percorso del file.",
      {
        testo: z.string().describe("Le parole da cercare"),
        progetto: z.string().optional().describe("Percorso della cartella di un Progetto, per cercare solo nella sua memoria"),
      },
      async ({ testo, progetto }) => {
        const id = randomUUID();
        const text = await new Promise<string>((resolve) => {
          searches.set(id, resolve);
          send({ type: "search", id, query: testo, project: progetto });
        });
        return { content: [{ type: "text", text }] };
      },
      { annotations: { readOnlyHint: true } },
    )],
  });
}

async function ask(id: string, prompt: string, cwd: string, sources: SettingSource[]) {
  const conversation = query({
    prompt,
    options: {
      cwd,
      env: childEnv,
      pathToClaudeCodeExecutable: claudePath,
      settingSources: sources,
      mcpServers: { bubo: buboTools() },
      allowedTools: ["mcp__bubo__cerca"],
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
      } else if (message.type === "rate_limit_event") {
        sendQuota(quotaFromRateLimit(message.rate_limit_info));
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

// La Quota senza Domanda: `claude` parte, risponde al metodo di uso e si chiude prima di ogni turno.
// Nessuna impostazione caricata, quindi nessun hook o `.mcp.json` di nessuna cartella.
async function quota() {
  const conversation = query({
    prompt: (async function* () { await new Promise(() => {}); })(),
    options: { env: childEnv, pathToClaudeCodeExecutable: claudePath, settingSources: [], persistSession: false },
  });
  try {
    sendQuota(await readQuota(conversation));
  } catch (error) {
    console.error("Quota non letta:", error instanceof Error ? error.message : error);
  } finally {
    conversation.close();
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
    case "ask": void ask(command.id, command.prompt, command.cwd, settingSources(command.settingSources)); break;
    case "cancel": void running.get(command.id)?.interrupt(); break;
    case "found": searches.get(command.id)?.(command.text); searches.delete(command.id); break;
    case "quota": void quota(); break;
  }
});
// stdin chiuso: Bubo è uscito o ha chiuso il ponte.
lines.on("close", () => process.exit(0));
send({ type: "ready" });
