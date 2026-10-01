// Ponte agente di Bubo: JSON su righe, stdin → comandi, stdout → eventi.
// Protocollo in Bubo/Agent/BridgeMessage.swift; stessa versione nei due lati.
import {
  createSdkMcpServer, getSessionMessages, importSessionToStore, type CanUseTool, listSessions, query, tool, type HookInput, type Query, type SDKAssistantMessageError, type SessionStoreEntry, type SettingSource,
} from "@anthropic-ai/claude-agent-sdk";
import { randomUUID } from "node:crypto";
import { createInterface } from "node:readline";
import { z } from "zod";
import { edits, progress, type Edit, type Progress } from "./activity";
import { configuration, type Configuration, type Instructions } from "./config";
import { conversation, firstPage, messages, type Conversation, type Message } from "./history";
import { deniedOwnCard, deniedWithoutBubo, isAllowed, isTooLong, needsItsOwnCard, permissionRequest, permissionResult, type PermissionRequest } from "./permission";
import { limitFromRateLimit, quotaFromRateLimit, readQuota, type Limit, type Quota } from "./quota";
import { settingSources } from "./settingSources";
import { ConversationStore } from "./store";
import { restoredFrom, UsageReader, type Restored, type TurnUsage } from "./usage";

const version = 3;

type Command =
  | { v: number; type: "ask"; id: string; prompt: string; cwd: string; settingSources?: unknown; projectConfigRoot?: unknown; model?: unknown; env?: unknown; resume?: unknown; keep?: unknown }
  | { v: number; type: "cancel"; id: string }
  | { v: number; type: "found"; id: string; text: string }
  | { v: number; type: "quota" }
  | { v: number; type: "config"; id: string; cwd: string; settingSources?: unknown; projectConfigRoot?: unknown }
  | { v: number; type: "history"; id: string; all?: unknown }
  | { v: number; type: "transcript"; id: string; conversation: string }
  | { v: number; type: "keep"; id: string }
  | { v: number; type: "forget"; conversations?: unknown }
  | { v: number; type: "forgetHistory"; id: string }
  | { v: number; type: "permission"; request: string; behavior?: unknown };

type Event =
  | { type: "ready" }
  | { type: "text"; id: string; text: string }
  | { type: "done"; id: string }
  | (Progress & { id: string })
  | (Edit & { id: string })
  | { type: "error"; id?: string; message: string }
  | ({ type: "limit"; id: string } & Limit)
  | { type: "signInRequired"; id: string }
  | { type: "search"; id: string; query: string; project?: string }
  | ({ type: "quota" } & Quota)
  | ({ type: "config"; id: string } & Configuration)
  | { type: "history"; id: string; conversations: Conversation[] }
  | { type: "transcript"; id: string; messages: Message[] }
  | { type: "kept"; id: string; count: number }
  | { type: "forgot"; id: string }
  | (PermissionRequest & { id: string })
  | { type: "permissionWithdrawn"; id: string; request: string }
  | ({ type: "usage"; id: string } & TurnUsage);

function send(event: Event) {
  process.stdout.write(JSON.stringify({ v: version, ...event }) + "\n");
}

// Le Richieste di permesso in attesa della risposta di Bubo: si risolvono una volta sola, con `true` solo per "allow".
const permissions = new Map<string, (allowed: boolean) => void>();

// `canUseTool` della conversazione `id`. Chiude sempre su "no": se Bubo non si raggiunge, se la CLI ritira la
// Richiesta, se la risposta non è "allow". Se Bubo esce, stdin si chiude e il ponte esce senza approvare nulla.
function askBubo(id: string): CanUseTool {
  return async (toolName, input, options) => {
    if (needsItsOwnCard(toolName, options)) return permissionResult(false, input, deniedOwnCard);
    if (options.signal.aborted) return permissionResult(false, input, deniedWithoutBubo);
    const request = randomUUID();
    const shown = permissionRequest(request, toolName, input, options);
    if (isTooLong(shown)) return permissionResult(false, input, deniedWithoutBubo);
    let reached = true;
    const allowed = await new Promise<boolean>((resolve) => {
      permissions.set(request, resolve);
      options.signal.addEventListener("abort", () => {
        resolve(false);
        if (permissions.delete(request)) send({ type: "permissionWithdrawn", id, request });
      }, { once: true });
      try {
        send({ ...shown, id });
      } catch {
        reached = false;
        resolve(false);
      }
    });
    permissions.delete(request);
    return permissionResult(allowed, input, reached ? undefined : deniedWithoutBubo);
  };
}

// Una Quota senza finestre non si manda: Bubo tiene ciò che sa, o non mostra nulla.
function sendQuota(quota: Quota) {
  if (quota.fiveHour || quota.sevenDay) send({ type: "quota", ...quota });
}

// Swift ha già costruito l'ambiente da zero: il ponte lo passa a `claude` così com'è,
// meno le proprie variabili, e con la memoria automatica spenta nelle Domande.
// CLAUDE_CODE_SANDBOXED farebbe passare per fidata qualunque cartella (#266): mai al figlio.
const { BUBO_CLAUDE_PATH: claudePath, BUBO_CONVERSATIONS: conversationsPath, CLAUDE_CODE_SANDBOXED: _sandboxed, ...inherited } = process.env;
const childEnv = { ...inherited, CLAUDE_CODE_DISABLE_AUTO_MEMORY: "1" };

// La copia a specchio delle conversazioni (ADR 0006); senza, le Sessioni lavorano come prima, senza copia.
const store = (() => {
  if (!conversationsPath) return undefined;
  try {
    return new ConversationStore(conversationsPath);
  } catch (error) {
    console.error("Copia delle conversazioni non disponibile:", error instanceof Error ? error.message : error);
    return undefined;
  }
})();

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
// `keep` è l'id che Bubo dà alla conversazione di un turno di una Sessione, da conservare: `claude` scrive il suo
// transcript in ~/.claude/projects come dalla riga di comando (`sessionStore` non funziona senza la scrittura locale)
// e l'SDK lo copia nello store. Senza `keep`, come per le Domande, `claude` non scrive nulla.
async function ask(id: string, prompt: string, cwd: string, sources: SettingSource[], projectConfigRoot?: string,
                   model?: string, env: Record<string, string> = {}, resume?: string, keep?: string) {
  const mirrored = keep !== undefined && store !== undefined;
  const restored = resume === undefined ? undefined : await restoredOf(resume);
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
      ...(mirrored ? { sessionId: keep, persistSession: true, sessionStore: store } : { persistSession: false }),
      canUseTool: askBubo(id),
      // La fine di un Bash dell'agente può avere avviato o fermato un server: Bubo cerca le porte (spec 15).
      hooks: { PostToolUse: [{ matcher: "Bash", hooks: [async () => { send({ type: "ran", id }); return {}; }] }] },
    },
  });
  running.set(id, conversation);
  // Perché il turno si è fermato: un limite rifiutato o un accesso non valido diventano eventi a sé.
  let limit: Limit | undefined;
  let failure: SDKAssistantMessageError | undefined;
  let succeeded = false;
  // Le conversazioni a cui la copia ha perso un pezzo: si rifanno dal transcript a fine turno.
  const torn = new Set<string>();
  // Le cifre del turno: abbonamento o API key secondo la credenziale che `claude` dice di usare.
  let usage: UsageReader | undefined;
  try {
    for await (const message of conversation) {
      if (message.type === "system" && message.subtype === "init") {
        usage ??= new UsageReader(message.apiKeySource === "none" ? "subscription" : "apiKey", restored);
      }
      const turn = usage?.read(message);
      if (turn) send({ type: "usage", id, ...turn });
      if (message.type === "system" && message.subtype === "mirror_error") {
        console.error("Copia della conversazione incompleta:", message.error);
        torn.add(message.key.sessionId);
      }
      const update = progress(message);
      if (update) send({ ...update, id });
      for (const edit of edits(message)) send({ ...edit, id });
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
    // Interrotto senza un `result` valido: i token visti finora, con la cifra segnata incompleta.
    const turn = usage?.turn();
    if (turn && !turn.complete) send({ type: "usage", id, ...turn });
    send({ type: "error", id, message: error instanceof Error ? error.message : String(error) });
  } finally {
    running.delete(id);
    for (const session of torn) await repair(session);
  }
}

// Il totale che `resume` ripristina dal transcript di `session` (`cost-state`), da togliere al turno: quei turni sono
// della Cronologia CLI. Dalla copia se la CLI l'ha già cancellato; senza `cost-state` `resume` non ripristina nulla.
async function restoredOf(session: string): Promise<Restored | undefined> {
  const entries: SessionStoreEntry[] = [];
  try {
    await importSessionToStore(session, {
      append: async (key, read) => { if (!key.subpath) entries.push(...read); },
      load: async () => null,
    });
  } catch (error) {
    console.error("Transcript da riprendere non letto:", error instanceof Error ? error.message : error);
  }
  if (!entries.length && store) entries.push(...store.entries(session));
  return restoredFrom(entries);
}

async function repair(session: string) {
  try {
    await store?.replace(session);
  } catch (error) {
    console.error("Copia non riparata:", error instanceof Error ? error.message : error);
  }
}

// Copia nello store la Cronologia CLI: le conversazioni mai viste, e quelle andate avanti dall'ultima copia.
// Il transcript si legge con `importSessionToStore`, mai a mano; ~/.claude resta com'è.
let clearings = 0;
async function keepHistory(id: string) {
  if (!store) {
    send({ type: "error", id, message: "copia delle conversazioni non disponibile" });
    return;
  }
  try {
    let count = 0;
    const clearing = clearings;
    for (const info of await listSessions({ includeProgrammatic: false })) {
      if ((store.importedAt(info.sessionId) ?? -1) >= info.lastModified) continue;
      try {
        await store.replace(info.sessionId);
        // L'interruttore si è spento durante la copia: niente resta.
        if (clearings !== clearing) {
          store.forget([info.sessionId]);
          break;
        }
        store.markImported(info.sessionId, info.lastModified);
        count += 1;
      } catch (error) {
        console.error("Conversazione non copiata:", error instanceof Error ? error.message : error);
      }
    }
    send({ type: "kept", id, count });
  } catch (error) {
    send({ type: "error", id, message: error instanceof Error ? error.message : String(error) });
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
    // Dopo la pulizia della CLI il transcript locale non c'è più: resta la copia.
    let read = await getSessionMessages(session);
    if (!read.length && store) read = await getSessionMessages(session, { sessionStore: store });
    send({ type: "transcript", id, messages: messages(read) });
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
      const keep = typeof command.keep === "string" ? command.keep : undefined;
      void ask(command.id, command.prompt, command.cwd, settingSources(command.settingSources), root, model, env, resume, keep);
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
    case "keep": void keepHistory(command.id); break;
    case "forget":
      if (Array.isArray(command.conversations)) {
        store?.forget(command.conversations.filter((session): session is string => typeof session === "string"));
      }
      break;
    case "forgetHistory":
      clearings += 1;
      store?.forgetImported();
      send({ type: "forgot", id: command.id });
      break;
    case "cancel": void running.get(command.id)?.interrupt(); break;
    case "found": searches.get(command.id)?.(command.text); searches.delete(command.id); break;
    case "quota": void quota(); break;
    case "permission": permissions.get(command.request)?.(isAllowed(command.behavior)); permissions.delete(command.request); break;
  }
});
// stdin chiuso: Bubo è uscito o ha chiuso il ponte.
lines.on("close", () => process.exit(0));
send({ type: "ready" });
