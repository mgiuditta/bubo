// Ponte agente di Bubo: JSON su righe, stdin → comandi, stdout → eventi.
// Protocollo in Bubo/Agent/BridgeMessage.swift; stessa versione nei due lati.
import {
  createSdkMcpServer, getSessionMessages, listSessions, query, tool, type HookInput, type Query, type SDKAssistantMessageError, type SettingSource,
} from "@anthropic-ai/claude-agent-sdk";
import { randomUUID } from "node:crypto";
import { createInterface } from "node:readline";
import { z } from "zod";
import { progress, type Progress } from "./activity";
import { configuration, type Configuration, type Instructions } from "./config";
import { conversation, firstPage, messages, type Conversation, type Message } from "./history";
import { limitFromRateLimit, quotaFromRateLimit, readQuota, type Limit, type Quota } from "./quota";
import { settingSources } from "./settingSources";

const version = 3;

type Command =
  | { v: number; type: "ask"; id: string; prompt: string; cwd: string; settingSources?: unknown; projectConfigRoot?: unknown; model?: unknown; env?: unknown; resume?: unknown }
  | { v: number; type: "cancel"; id: string }
  | { v: number; type: "found"; id: string; text: string }
  | { v: number; type: "quota" }
  | { v: number; type: "config"; id: string; cwd: string; settingSources?: unknown; projectConfigRoot?: unknown }
  | { v: number; type: "history"; id: string; all?: unknown }
  | { v: number; type: "transcript"; id: string; conversation: string };

type Event =
  | { type: "ready" }
  | { type: "text"; id: string; text: string }
  | { type: "done"; id: string }
  | (Progress & { id: string })
  | { type: "error"; id?: string; message: string }
  | ({ type: "limit"; id: string } & Limit)
  | { type: "signInRequired"; id: string }
  | { type: "search"; id: string; query: string; project?: string }
  | ({ type: "quota" } & Quota)
  | ({ type: "config"; id: string } & Configuration)
  | { type: "history"; id: string; conversations: Conversation[] }
  | { type: "transcript"; id: string; messages: Message[] };

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

// In un worktree `projectConfigRoot` è il checkout principale: impostazioni, `.mcp.json` e `.claude/` vengono da lì.
// `model` è un alias di `claude` (`sonnet`, `opus`); senza, vale il modello scelto dall'utente.
// `env` si aggiunge all'ambiente del figlio: le porte della Sessione.
// `resume` è una conversazione della Cronologia CLI: si riprende sempre come fork, con un id nuovo.
// Il transcript è quello che la CLI ha già scritto; con `persistSession: false` il fork non si scrive in ~/.claude.
async function ask(id: string, prompt: string, cwd: string, sources: SettingSource[], projectConfigRoot?: string,
                   model?: string, env: Record<string, string> = {}, resume?: string) {
  const conversation = query({
    prompt,
    options: {
      cwd,
      projectConfigRoot,
      model,
      env: { ...childEnv, ...env },
      pathToClaudeCodeExecutable: claudePath,
      settingSources: sources,
      mcpServers: { bubo: buboTools() },
      allowedTools: ["mcp__bubo__cerca"],
      includePartialMessages: true,
      resume,
      forkSession: resume !== undefined,
      persistSession: false,
    },
  });
  running.set(id, conversation);
  // Perché il turno si è fermato: un limite rifiutato o un accesso non valido diventano eventi a sé.
  let limit: Limit | undefined;
  let failure: SDKAssistantMessageError | undefined;
  let succeeded = false;
  try {
    for await (const message of conversation) {
      const update = progress(message);
      if (update) send({ ...update, id });
      if (message.type === "stream_event" && message.event.type === "content_block_delta"
          && message.event.delta.type === "text_delta") {
        send({ type: "text", id, text: message.event.delta.text });
      } else if (message.type === "rate_limit_event") {
        sendQuota(quotaFromRateLimit(message.rate_limit_info));
        limit = limitFromRateLimit(message.rate_limit_info) ?? limit;
      } else if (message.type === "assistant" && message.error) {
        failure = message.error;
      } else if (message.type === "result") {
        if (message.subtype === "success" && !message.is_error) succeeded = true;
        else if (limit) send({ type: "limit", id, ...limit });
        else if (failure === "authentication_failed") send({ type: "signInRequired", id });
        else send({ type: "error", id, message: message.subtype === "success" ? message.result : message.subtype });
      }
    }
    // `done` dopo l'ultimo messaggio, non al `result`: mai "finita" con subagent ancora attivi.
    if (succeeded) send({ type: "done", id });
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

// La configurazione che `claude` carica in `cwd`, con le stesse fonti di una Sessione lì.
// `/context` è un comando locale: `claude` manda `init` e risponde da sé, senza turni del modello,
// quindi costo 0. Niente server `bubo`: i conteggi restano quelli della CLI.
async function inspect(id: string, cwd: string, sources: SettingSource[], projectConfigRoot?: string) {
  const loaded: Instructions[] = [];
  const conversation = query({
    prompt: "/context",
    options: {
      cwd,
      projectConfigRoot,
      env: childEnv,
      pathToClaudeCodeExecutable: claudePath,
      settingSources: sources,
      persistSession: false,
      hooks: {
        InstructionsLoaded: [{ hooks: [async (input: HookInput) => {
          if (input.hook_event_name === "InstructionsLoaded") loaded.push({ path: input.file_path, type: input.memory_type });
          return {};
        }] }],
      },
    },
  });
  try {
    for await (const message of conversation) {
      if (message.type === "system" && message.subtype === "init") {
        // L'hook scatta solo quando un turno costruisce il prompt: i CLAUDE.md vengono anche da getContextUsage.
        const [servers, usage] = await Promise.all([conversation.mcpServerStatus(), conversation.getContextUsage()]);
        const memory = usage.memoryFiles.map(({ path, type }) => ({ path, type }));
        send({ type: "config", id, ...configuration(message, servers, [...memory, ...loaded]) });
        return;
      }
    }
    send({ type: "error", id, message: "claude non ha mandato init" });
  } catch (error) {
    send({ type: "error", id, message: error instanceof Error ? error.message : String(error) });
  } finally {
    conversation.close();
  }
}

// La Cronologia CLI come `/resume` della CLI: solo le conversazioni interattive, le più recenti prima.
// Senza `all`, la prima pagina; la ricerca le chiede tutte.
async function history(id: string, all: boolean) {
  try {
    const sessions = await listSessions({ limit: all ? undefined : firstPage, includeProgrammatic: false });
    send({ type: "history", id, conversations: sessions.map(conversation) });
  } catch (error) {
    send({ type: "error", id, message: error instanceof Error ? error.message : String(error) });
  }
}

async function transcript(id: string, session: string) {
  try {
    send({ type: "transcript", id, messages: messages(await getSessionMessages(session)) });
  } catch (error) {
    send({ type: "error", id, message: error instanceof Error ? error.message : String(error) });
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
    case "ask": {
      const root = typeof command.projectConfigRoot === "string" && command.projectConfigRoot.startsWith("/")
        ? command.projectConfigRoot : undefined;
      const model = typeof command.model === "string" ? command.model : undefined;
      const env = Object.fromEntries(Object.entries(typeof command.env === "object" && command.env ? command.env : {})
        .filter((entry): entry is [string, string] => typeof entry[1] === "string" && entry[0] !== "CLAUDE_CODE_SANDBOXED"));
      const resume = typeof command.resume === "string" ? command.resume : undefined;
      void ask(command.id, command.prompt, command.cwd, settingSources(command.settingSources), root, model, env, resume);
      break;
    }
    case "config": {
      const root = typeof command.projectConfigRoot === "string" && command.projectConfigRoot.startsWith("/")
        ? command.projectConfigRoot : undefined;
      void inspect(command.id, command.cwd, settingSources(command.settingSources), root);
      break;
    }
    case "history": void history(command.id, command.all === true); break;
    case "transcript": void transcript(command.id, command.conversation); break;
    case "cancel": void running.get(command.id)?.interrupt(); break;
    case "found": searches.get(command.id)?.(command.text); searches.delete(command.id); break;
    case "quota": void quota(); break;
  }
});
// stdin chiuso: Bubo è uscito o ha chiuso il ponte.
lines.on("close", () => process.exit(0));
send({ type: "ready" });
