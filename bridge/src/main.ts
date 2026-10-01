// Ponte agente di Bubo: JSON su righe, stdin → comandi, stdout → eventi.
// Protocollo in Bubo/Agent/BridgeMessage.swift; stessa versione nei due lati.
import {
  createSdkMcpServer, getSessionMessages, importSessionToStore, type CanUseTool, type HookCallbackMatcher, listSessions, type McpServerStatus, type Options, prewarm, query, tool, type HookInput, type PermissionMode, type Query, type SandboxSettings, type SDKAssistantMessageError, type SessionStoreEntry, type SettingSource, type SpareProcess,
} from "@anthropic-ai/claude-agent-sdk";
import { randomUUID } from "node:crypto";
import { homedir } from "node:os";
import { createInterface } from "node:readline";
import { z } from "zod";
import { edits, progress, reads, searched, type Edit, type Progress, type Read } from "./activity";
import { isLocal, isOutsideSandbox, sandboxGate, type RiskQuestion } from "./gate";
import { configuration, type Configuration, type Instructions } from "./config";
import { conversation, firstPage, messages, type Conversation, type Message } from "./history";
import { deniedOwnCard, deniedWithoutBubo, isAllowed, isLasting, isTooLong, needsItsOwnCard, networkRule, networkTool, permissionRequest, permissionResult, type PermissionRequest } from "./permission";
import { allowedPreviewTools, offerPreview, PreviewCalls, previewTools, turnServers, type PreviewCall } from "./preview";
import { MemoryWrites, recalled, withAutoMemory, type Recalled, type Remembered } from "./memory";
import { limitFromRateLimit, quotaFromRateLimit, readQuota, type Limit, type Quota } from "./quota";
import { sandboxSettings, sandboxUnavailableReason } from "./sandbox";
import { sandboxRules, type SandboxRule } from "./sandboxRules";
import { blockedLine, blocksOf, type SandboxBlock } from "./violations";
import { settingSources } from "./settingSources";
import { SpareSlot, type SpareKey } from "./spare";
import { ConversationStore } from "./store";
import { teamRuleOptions, teamRules, type TeamRules } from "./teamRules";
import { allowedBuboTools } from "./tools";
import { restoredFrom, UsageReader, type Restored, type TurnUsage } from "./usage";

const version = 4;

type Command =
  | { v: number; type: "ask"; id: string; prompt: string; cwd: string; settingSources?: unknown; projectConfigRoot?: unknown; model?: unknown; env?: unknown; resume?: unknown; keep?: unknown; sandbox?: unknown; preview?: unknown; rules?: unknown; remember?: unknown; permissionMode?: unknown }
  | { v: number; type: "cancel"; id: string }
  | { v: number; type: "found"; id: string; text: string }
  | { v: number; type: "quota" }
  | { v: number; type: "config"; id: string; cwd: string; settingSources?: unknown; projectConfigRoot?: unknown }
  | { v: number; type: "warm"; settingSources?: unknown; projectConfigRoot?: unknown }
  | { v: number; type: "cool" }
  | { v: number; type: "history"; id: string; all?: unknown }
  | { v: number; type: "transcript"; id: string; conversation: string }
  | { v: number; type: "keep"; id: string }
  | { v: number; type: "forget"; conversations?: unknown }
  | { v: number; type: "forgetHistory"; id: string }
  | { v: number; type: "permission"; request: string; behavior?: unknown; scope?: unknown }
  | { v: number; type: "sandboxRules"; id: string; cwd: string; settingSources?: unknown; projectConfigRoot?: unknown }
  | { v: number; type: "previewServer"; id: string; available?: unknown }
  | { v: number; type: "previewResult"; call?: unknown; text?: unknown; image?: unknown; error?: unknown }
  | { v: number; type: "risk"; request: string; dangerous?: unknown };

type Event =
  | { type: "ready" }
  | { type: "text"; id: string; text: string }
  | { type: "done"; id: string }
  | { type: "ran"; id: string }
  | (Progress & { id: string })
  | (Edit & { id: string })
  | (Remembered & { id: string })
  | (Recalled & { id: string })
  | (Read & { id: string })
  | { type: "error"; id?: string; message: string }
  | ({ type: "limit"; id: string } & Limit)
  | { type: "signInRequired"; id: string }
  | { type: "sandboxUnavailable"; id: string; reason: string }
  | { type: "search"; id: string; query: string; project?: string; source?: string; conversation: string }
  | (PreviewCall & { id: string })
  | { type: "remember"; id: string; title: string; text: string }
  | ({ type: "quota" } & Quota)
  | ({ type: "config"; id: string } & Configuration)
  | { type: "history"; id: string; conversations: Conversation[] }
  | { type: "transcript"; id: string; messages: Message[] }
  | { type: "kept"; id: string; count: number }
  | { type: "forgot"; id: string }
  | (PermissionRequest & { id: string })
  | { type: "permissionWithdrawn"; id: string; request: string }
  | (SandboxBlock & { type: "sandboxBlock"; id: string })
  | { type: "sandboxRules"; id: string; rules: SandboxRule[] }
  | (RiskQuestion & { type: "risk"; id: string; request: string })
  | ({ type: "usage"; id: string } & TurnUsage);

function send(event: Event) {
  process.stdout.write(JSON.stringify({ v: version, ...event }) + "\n");
}

// La risposta di Bubo a una Richiesta: `lasting` quando vale per il resto della Sessione.
type Answer = { allowed: boolean; lasting: boolean };
const denied: Answer = { allowed: false, lasting: false };

// Le Richieste di permesso in attesa della risposta di Bubo: si risolvono una volta sola, approvate solo con "allow".
const permissions = new Map<string, (answer: Answer) => void>();

// `canUseTool` della conversazione `id`. Chiude sempre su "no": se Bubo non si raggiunge, se la CLI ritira la
// Richiesta, se la risposta non è "allow". Se Bubo esce, stdin si chiude e il ponte esce senza approvare nulla.
// Con la Sandbox accesa, un Bash che chiede di uscirne arriva a Bubo segnato "fuori dalla sandbox".
// Un host fuori dai domini della Sandbox approvato per la Sessione porta con sé `WebFetch(domain:host)` di sessione.
function askBubo(id: string, isSandboxed: boolean): CanUseTool {
  return async (toolName, input, options) => {
    if (needsItsOwnCard(toolName, options)) return permissionResult(false, input, deniedOwnCard);
    if (options.signal.aborted) return permissionResult(false, input, deniedWithoutBubo);
    const request = randomUUID();
    const shown = permissionRequest(request, toolName, input, options);
    if (isSandboxed && isOutsideSandbox(toolName, input)) shown.outsideSandbox = true;
    if (isTooLong(shown)) return permissionResult(false, input, deniedWithoutBubo);
    let reached = true;
    const answer = await new Promise<Answer>((resolve) => {
      permissions.set(request, resolve);
      options.signal.addEventListener("abort", () => {
        resolve(denied);
        if (permissions.delete(request)) send({ type: "permissionWithdrawn", id, request });
      }, { once: true });
      try {
        send({ ...shown, id });
      } catch {
        reached = false;
        resolve(denied);
      }
    });
    permissions.delete(request);
    const rule = answer.lasting && toolName === networkTool ? networkRule(input.host) : undefined;
    return permissionResult(answer.allowed, input, reached ? undefined : deniedWithoutBubo, rule && [rule]);
  };
}

// Le domande sul Livello di rischio del cancello in attesa di Bubo: `true` per i livelli 4–5.
const risks = new Map<string, (dangerous: boolean) => void>();

// Il Livello di rischio lo dà Bubo, come alle Richieste: il cancello chiede solo se è 4 o 5. Senza risposta, sì.
function riskFromBubo(id: string, signal: AbortSignal) {
  return (question: RiskQuestion) => new Promise<boolean>((resolve) => {
    if (signal.aborted) return resolve(true);
    const request = randomUUID();
    const stop = () => { risks.delete(request); resolve(true); };
    risks.set(request, (dangerous) => { signal.removeEventListener("abort", stop); resolve(dangerous); });
    signal.addEventListener("abort", stop, { once: true });
    try {
      send({ type: "risk", id, request, ...question });
    } catch {
      risks.delete(request);
      resolve(true);
    }
  });
}

// Una Quota senza finestre non si manda: Bubo tiene ciò che sa, o non mostra nulla.
function sendQuota(quota: Quota) {
  if (quota.fiveHour || quota.sevenDay) send({ type: "quota", ...quota });
}

// Swift ha già costruito l'ambiente da zero: il ponte lo passa a `claude` così com'è, meno le proprie variabili.
// CLAUDE_CODE_SANDBOXED farebbe passare per fidata qualunque cartella (#266): mai al figlio.
const { BUBO_CLAUDE_PATH: claudePath, BUBO_CONVERSATIONS: conversationsPath, CLAUDE_CODE_SANDBOXED: _sandboxed, ...inherited } = process.env;
const childEnv = { ...inherited };
// Dove `claude` tiene la memoria automatica: la stessa cartella di configurazione del figlio.
const configDirectory = childEnv.CLAUDE_CONFIG_DIR ?? `${homedir()}/.claude`;

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
// Le chiamate a `cerca` e `ricorda` in attesa del risultato di Bubo, che arriva con `found`.
const toolCalls = new Map<string, (text: string) => void>();

// Manda `event` a Bubo e aspetta il testo con cui risponde.
function askBuboFor(event: (id: string) => Event): Promise<string> {
  const id = randomUUID();
  return new Promise<string>((resolve) => {
    toolCalls.set(id, resolve);
    send(event(id));
  });
}

// `cerca` chiede l'Indice a Bubo: i frammenti restano tra Bubo e Claude.
// `ricorda`, solo con `remembers`, fa scrivere a Bubo una nota in `Bubo/Note/` del Secondo cervello.
// Un server per conversazione: un'istanza MCP si collega a un solo trasporto. `conversation` dice a Bubo di chi è
// ogni chiamata a `cerca`, per la riga "Richiamato" della Sessione.
function buboTools(conversation: string, remembers = false) {
  const search = tool(
    "cerca",
    "Cerca per parole nell'Indice di Bubo: la memoria di Claude Code di tutti i Progetti, il CLAUDE.md dell'utente e il suo Secondo cervello, la cartella di note Markdown che ha scelto (per esempio un vault Obsidian). Le note non arrivano in nessun altro modo: cercale qui quando servono. Restituisce i frammenti con il percorso del file.",
    {
      testo: z.string().describe("Le parole da cercare"),
      progetto: z.string().optional().describe("Percorso della cartella di un Progetto, per cercare solo nella sua memoria"),
      fonte: z.enum(["memoria", "secondo-cervello"]).optional()
        .describe("Dove cercare: \"memoria\" (memoria dei Progetti e CLAUDE.md) o \"secondo-cervello\" (le note dell'utente); senza, ovunque"),
    },
    async ({ testo, progetto, fonte }) => {
      const text = await askBuboFor((id) => ({ type: "search", id, query: testo, project: progetto, source: fonte, conversation }));
      return { content: [{ type: "text", text }] };
    },
    { annotations: { readOnlyHint: true } },
  );
  const remember = tool(
    "ricorda",
    "Salva una nota nuova nel Secondo cervello dell'utente, la sua cartella di note Markdown, in Bubo/Note. Usalo solo quando l'utente chiede di ricordare qualcosa (\"ricordati questo\", \"segnati che…\"). Non modifica né sostituisce note esistenti. Restituisce il percorso della nota, o perché non è stata salvata.",
    {
      titolo: z.string().describe("Un titolo breve, che diventa il nome del file"),
      testo: z.string().describe("Cosa ricordare, in Markdown, comprensibile anche letto da solo tra mesi"),
    },
    async ({ titolo, testo }) => {
      const text = await askBuboFor((id) => ({ type: "remember", id, title: titolo, text: testo }));
      return { content: [{ type: "text", text }] };
    },
    { annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false } },
  );
  return createSdkMcpServer({ name: "bubo", tools: remembers ? [search, remember] : [search] });
}

// Le chiamate agli strumenti dell'Anteprima, in attesa di `PreviewDriver`.
const previewCalls = new PreviewCalls((id, call) => send({ ...call, id }));

// L'hook che dice a Bubo della fine di un Bash della conversazione `id`. Con la Sandbox accesa, ogni blocco del
// comando va a Bubo e, come riga "Bloccato dalla sandbox: …", anche all'agente.
function ranBash(id: string, isSandboxed: boolean): HookCallbackMatcher {
  return { matcher: "Bash", hooks: [async (input) => {
    send({ type: "ran", id });
    const blocks = isSandboxed ? blocksOf(input) : [];
    for (const block of blocks) send({ type: "sandboxBlock", id, ...block });
    if (!blocks.length || (input.hook_event_name !== "PostToolUse" && input.hook_event_name !== "PostToolUseFailure")) return {};
    return { hookSpecificOutput: { hookEventName: input.hook_event_name, additionalContext: blocks.map(blockedLine).join("\n") } };
  }] };
}

// Gli hook che seguono le scritture dell'agente nella memoria, per la riga "Ricordato" della conversazione `id`: il
// file si copia prima della scrittura, perché Annulla possa rimetterlo com'era. Anche quelle dei subagent.
function memoryHooks(id: string): Record<"PreToolUse" | "PostToolUse" | "PostToolUseFailure", HookCallbackMatcher[]> {
  const writes = new MemoryWrites(configDirectory);
  const matcher = "Write|Edit";
  return {
    PreToolUse: [{ matcher, hooks: [async (input: HookInput) => {
      if (input.hook_event_name === "PreToolUse") writes.start(input.tool_use_id, input.tool_input);
      return {};
    }] }],
    PostToolUse: [{ matcher, hooks: [async (input: HookInput) => {
      const remembered = input.hook_event_name === "PostToolUse" ? writes.finish(input.tool_use_id) : undefined;
      if (remembered) send({ ...remembered, id });
      return {};
    }] }],
    PostToolUseFailure: [{ matcher, hooks: [async (input: HookInput) => {
      if (input.hook_event_name === "PostToolUseFailure") writes.forget(input.tool_use_id);
      return {};
    }] }],
  };
}

// I file trovati da Grep e Glob, letture tenui della Galassia: l'SDK li dà solo nella risposta dello strumento.
function searchedFiles(id: string): HookCallbackMatcher {
  return {
    matcher: "Grep|Glob",
    hooks: [async (input) => {
      const read = input.hook_event_name === "PostToolUse" ? searched(input) : undefined;
      if (read) send({ ...read, id });
      return {};
    }],
  };
}

// In un worktree `projectConfigRoot` è il checkout principale: impostazioni, `.mcp.json` e `.claude/` vengono da lì.
// `model` è un alias di `claude` (`sonnet`, `opus`); senza, vale il modello scelto dall'utente.
// `env` si aggiunge all'ambiente del figlio: le porte della Sessione.
// `resume` è una conversazione della Cronologia CLI: si riprende sempre come fork, con un id nuovo.
// `keep` è l'id che Bubo dà alla conversazione di un turno di una Sessione, da conservare: `claude` scrive il suo
// transcript in ~/.claude/projects come dalla riga di comando (`sessionStore` non funziona senza la scrittura locale)
// e l'SDK lo copia nello store. Senza `keep`, come per le Domande, `claude` non scrive nulla.
// `keep` dice anche che il turno è di una Sessione: solo lì la memoria automatica è accesa.
// `sandbox` è la Sandbox della Sessione, se accesa: se non parte, `claude` esce prima di ogni comando.
// `preview` dice che la Sessione ha già un server: il turno parte con gli strumenti dell'Anteprima.
// `rules` sono le Risorse di squadra in vigore nel Progetto, come regole di sessione.
// `remembers` dà lo strumento `ricorda`: solo alle Domande.
// `permissionMode` è `auto` nella Modalità autonoma, `default` nelle altre Sessioni; senza, decide `claude`.
// Il cancello (`gate.ts`) passa prima di ogni strumento: con la Sandbox accesa o in Modalità autonoma.
async function ask(id: string, prompt: string, cwd: string, sources: SettingSource[], projectConfigRoot?: string,
                   model?: string, env: Record<string, string> = {}, resume?: string, keep?: string,
                   sandbox?: SandboxSettings, preview = false, rules: TeamRules = teamRules(undefined), remembers = false,
                   permissionMode?: PermissionMode) {
  const mirrored = keep !== undefined && store !== undefined;
  const restored = resume === undefined ? undefined : await restoredOf(resume);
  const stopped = new AbortController();
  let servers: Promise<McpServerStatus[]> | undefined;
  const gate = sandboxGate({
    cwd,
    sandbox,
    isDangerous: riskFromBubo(id, stopped.signal),
    isLocalServer: async (name) => {
      servers ??= conversation.mcpServerStatus();
      return isLocal((await servers).find((server) => server.name === name));
    },
  });
  const memory = keep === undefined ? undefined : memoryHooks(id);
  const conversation = query({
    prompt,
    options: {
      cwd,
      projectConfigRoot,
      model,
      env: { ...withAutoMemory(childEnv, keep !== undefined), ...env },
      pathToClaudeCodeExecutable: claudePath,
      settingSources: sources,
      mcpServers: turnServers(buboTools(id, remembers), preview ? previewTools(id, previewCalls) : undefined),
      ...teamRuleOptions(rules, [...allowedBuboTools(remembers), ...allowedPreviewTools]),
      includePartialMessages: true,
      resume,
      forkSession: resume !== undefined,
      sandbox,
      permissionMode,
      ...(mirrored ? { sessionId: keep, persistSession: true, sessionStore: store } : { persistSession: false }),
      canUseTool: askBubo(id, sandbox !== undefined),
      // La fine di un Bash dell'agente, riuscito o no, può avere avviato o fermato un server: Bubo cerca le porte
      // (spec 15). Un Bash fallito o interrotto passa da `PostToolUseFailure`, non da `PostToolUse`.
      // Le scritture in memoria, solo nelle Sessioni: nelle Domande la memoria automatica è spenta.
      // Grep e Glob riusciti danno i file letti alla Galassia (spec 11).
      hooks: {
        PreToolUse: [{ hooks: [gate] }, ...(memory?.PreToolUse ?? [])],
        PostToolUse: [ranBash(id, sandbox !== undefined), searchedFiles(id), ...(memory?.PostToolUse ?? [])],
        PostToolUseFailure: [ranBash(id, sandbox !== undefined), ...(memory?.PostToolUseFailure ?? [])],
      },
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
      const recall = recalled(message);
      if (recall) send({ ...recall, id });
      for (const read of reads(message)) send({ ...read, id });
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
    const reason = sandbox ? sandboxUnavailableReason(error) : undefined;
    if (reason) send({ type: "sandboxUnavailable", id, reason });
    else send({ type: "error", id, message: error instanceof Error ? error.message : String(error) });
  } finally {
    stopped.abort();
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
    options: { env: withAutoMemory(childEnv, false), pathToClaudeCodeExecutable: claudePath, settingSources: [], persistSession: false },
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
// quindi costo 0. Niente server `bubo`: i conteggi restano quelli della CLI. Memoria automatica accesa come in una
// Sessione: `memoryFiles` comprende il `MEMORY.md` del Progetto.
// Con un `claude` di riserva per le stesse fonti (`warm`) `init` arriva senza l'avvio della CLI (#311);
// se la riserva non c'è o rifiuta la cartella, si parte a freddo come prima.
async function inspect(id: string, cwd: string, sources: SettingSource[], projectConfigRoot?: string) {
  try {
    const found = await fromSpare(cwd, { sources, projectConfigRoot }) ?? await fromCold(cwd, sources, projectConfigRoot);
    send(found ? { type: "config", id, ...found } : { type: "error", id, message: "claude non ha mandato init" });
  } catch (error) {
    send({ type: "error", id, message: error instanceof Error ? error.message : String(error) });
  }
}

// Le opzioni che `inspect` fissa all'avvio di `claude`; i CLAUDE.md caricati finiscono in `loaded`.
function inspectOptions(sources: SettingSource[], projectConfigRoot: string | undefined, loaded: Instructions[]): Options {
  return {
    projectConfigRoot,
    env: withAutoMemory(childEnv, true),
    pathToClaudeCodeExecutable: claudePath,
    settingSources: sources,
    persistSession: false,
    hooks: {
      InstructionsLoaded: [{ hooks: [async (input: HookInput) => {
        if (input.hook_event_name === "InstructionsLoaded") loaded.push({ path: input.file_path, type: input.memory_type });
        return {};
      }] }],
    },
  };
}

// Il `claude` di riserva del pannello: al massimo uno, avviato e chiuso solo su richiesta di Bubo.
type ConfigSpare = { spare: SpareProcess; loaded: Instructions[]; close(): void };
const spares = new SpareSlot<ConfigSpare>(async ({ sources, projectConfigRoot }) => {
  const loaded: Instructions[] = [];
  const spare = await prewarm({ options: inspectOptions(sources, projectConfigRoot, loaded) });
  return { spare, loaded, close: () => spare.close() };
});

async function fromSpare(cwd: string, key: SpareKey) {
  const warm = await spares.take(key);
  if (!warm) return undefined;
  try {
    const conversation = warm.spare.claim({ prompt: "/context", options: { cwd } });
    warm.spare.claimed.catch(() => {});
    return await readConfiguration(conversation, warm.loaded, warm.spare.claimed);
  } catch (error) {
    // Cartella rifiutata (impostazioni del Progetto, cartella mancante) o riserva morta: si riparte a freddo.
    console.error("Claude di riserva non usato:", error instanceof Error ? error.message : error);
    return undefined;
  } finally {
    warm.close();
  }
}

async function fromCold(cwd: string, sources: SettingSource[], projectConfigRoot?: string) {
  const loaded: Instructions[] = [];
  const conversation = query({ prompt: "/context", options: { cwd, ...inspectOptions(sources, projectConfigRoot, loaded) } });
  try {
    return await readConfiguration(conversation, loaded);
  } finally {
    conversation.close();
  }
}

// La configurazione da `init`, solo dopo che la riserva ha accettato la cartella (`claimed`): prima, `init`
// descriverebbe la cartella di parcheggio. `undefined` se `claude` finisce senza `init`.
async function readConfiguration(conversation: Query, loaded: Instructions[], claimed?: Promise<unknown>) {
  for await (const message of conversation) {
    if (message.type === "system" && message.subtype === "init") {
      await claimed;
      // L'hook scatta solo quando un turno costruisce il prompt: i CLAUDE.md vengono anche da getContextUsage.
      // `summary`: senza le chiamate di conteggio dei token di `full`, bastano percorsi e tipi.
      // Anche gli agenti si leggono qui: `supportedAgents()` vuole una query inizializzata, e questa non costa.
      const [servers, usage, agents] = await Promise.all([
        conversation.mcpServerStatus(), conversation.getContextUsage({ detail: "summary" }), conversation.supportedAgents(),
      ]);
      const memory = usage.memoryFiles.map(({ path, type }) => ({ path, type }));
      return configuration(message, servers, [...memory, ...loaded], agents);
    }
  }
  return undefined;
}

// Le Regole di permesso di `claude` in `cwd` che allargano la Sandbox, con le stesse fonti di una Sessione lì.
// Come la Quota: `claude` parte, risponde sul canale di controllo e si chiude prima di ogni turno.
async function readSandboxRules(id: string, cwd: string, sources: SettingSource[], projectConfigRoot?: string) {
  const conversation = query({
    prompt: (async function* () { await new Promise(() => {}); })(),
    options: { cwd, projectConfigRoot, env: childEnv, pathToClaudeCodeExecutable: claudePath, settingSources: sources, persistSession: false },
  });
  try {
    send({ type: "sandboxRules", id, rules: await sandboxRules(conversation) });
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
      const mode = command.permissionMode === "auto" || command.permissionMode === "default" ? command.permissionMode : undefined;
      void ask(command.id, command.prompt, command.cwd, settingSources(command.settingSources), root, model, env, resume, keep,
               sandboxSettings(command.sandbox), command.preview === true, teamRules(command.rules),
               command.remember === true, mode);
      break;
    }
    case "config": {
      const root = typeof command.projectConfigRoot === "string" && command.projectConfigRoot.startsWith("/")
        ? command.projectConfigRoot : undefined;
      void inspect(command.id, command.cwd, settingSources(command.settingSources), root);
      break;
    }
    case "warm": {
      const root = typeof command.projectConfigRoot === "string" && command.projectConfigRoot.startsWith("/")
        ? command.projectConfigRoot : undefined;
      spares.warm({ sources: settingSources(command.settingSources), projectConfigRoot: root });
      break;
    }
    case "cool": spares.cool(); break;
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
    case "found": toolCalls.get(command.id)?.(command.text); toolCalls.delete(command.id); break;
    case "quota": void quota(); break;
    case "previewServer": {
      // Il server della Sessione è comparso o sparito a turno in corso.
      const conversation = running.get(command.id);
      if (conversation) {
        void offerPreview(conversation, buboTools(command.id), command.available === true ? previewTools(command.id, previewCalls) : undefined);
      }
      break;
    }
    case "previewResult": previewCalls.answer(command.call, command); break;
    case "risk": risks.get(command.request)?.(command.dangerous !== false); risks.delete(command.request); break;
    case "permission":
      permissions.get(command.request)?.({ allowed: isAllowed(command.behavior), lasting: isLasting(command.scope) });
      permissions.delete(command.request);
      break;
    case "sandboxRules": {
      const root = typeof command.projectConfigRoot === "string" && command.projectConfigRoot.startsWith("/")
        ? command.projectConfigRoot : undefined;
      void readSandboxRules(command.id, command.cwd, settingSources(command.settingSources), root);
      break;
    }
  }
});
// stdin chiuso: Bubo è uscito o ha chiuso il ponte.
lines.on("close", () => process.exit(0));
send({ type: "ready" });
