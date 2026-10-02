// Ponte agente di Bubo: JSON su righe, stdin → comandi, stdout → eventi.
// Protocollo in Bubo/Agent/BridgeMessage.swift; stessa versione nei due lati.
import {
  createSdkMcpServer, getSessionMessages, importSessionToStore, type CanUseTool, type HookCallbackMatcher, listSessions, type McpServerStatus, type Options, prewarm, query, tool, type HookInput, type EffortLevel, type PermissionMode, type Query, type SandboxSettings, type SDKAPIRetryMessage, type SDKAssistantMessageError, type SessionStoreEntry, type SettingSource, type SpareProcess,
} from "@anthropic-ai/claude-agent-sdk";
import { randomUUID } from "node:crypto";
import { homedir } from "node:os";
import { createInterface } from "node:readline";
import { z } from "zod";
import { edits, progress, reads, searched, type Edit, type Progress, type Read } from "./activity";
import { isLocal, isOutsideSandbox, sandboxGate, type RiskQuestion } from "./gate";
import { turnFailure, type TurnFailure } from "./failure";
import { claudeInfo, isBelowMinimum, isTooOldForAnthropic, type ClaudeInfo } from "./compat";
import { configuration, type Configuration, type Instructions } from "./config";
import { conversation, dates, firstPage, messages, transcriptLimit, type Conversation, type Message } from "./history";
import { deniedOwnCard, deniedWithoutBubo, isAllowed, isLasting, isTooLong, needsItsOwnCard, networkRule, networkTool, permissionRequest, permissionResult, type PermissionRequest } from "./permission";
import { agentQuestion, answersOf, notShown, questionResult, type AgentQuestion } from "./question";
import { allowedPreviewTools, offerPreview, PreviewCalls, previewTools, turnServers, type PreviewCall } from "./preview";
import { orbInstruction, rosaOf, TurnVariante } from "./orb";
import { MemoryWrites, recalled, withAutoMemory, type Recalled, type Remembered } from "./memory";
import { AnswerWitness, catalogOf, effortOf, type AnsweredBy, type CatalogEntry } from "./router";
import { limitFromRateLimit, quotaFromRateLimit, readQuota, type Limit, type Quota } from "./quota";
import { sandboxSettings, sandboxUnavailableReason } from "./sandbox";
import { sandboxRules, type SandboxRule } from "./sandboxRules";
import { blockedLine, blocksOf, type SandboxBlock } from "./violations";
import { settingSources } from "./settingSources";
import { summarize, summaryOptions } from "./summary";
import { SpareSlot, type SpareKey } from "./spare";
import { ConversationStore, mirrorOnly } from "./store";
import { teamRuleOptions, teamRules, type TeamRules } from "./teamRules";
import { Denials, unattendedOf, unattendedOptions, type Denial, type Unattended } from "./unattended";
import { allowedBuboTools } from "./tools";
import { restoredFrom, UsageReader, type Restored, type TurnUsage } from "./usage";

const version = 4;

type Command =
  | { v: number; type: "ask"; id: string; prompt: string; cwd: string; settingSources?: unknown; projectConfigRoot?: unknown; model?: unknown; env?: unknown; resume?: unknown; upTo?: unknown; keep?: unknown; sandbox?: unknown; preview?: unknown; rules?: unknown; remember?: unknown; permissionMode?: unknown; effort?: unknown; orb?: unknown; unattended?: unknown; dirs?: unknown }
  | { v: number; type: "cancel"; id: string }
  | { v: number; type: "found"; id: string; text: string }
  | { v: number; type: "quota" }
  | { v: number; type: "config"; id: string; cwd: string; settingSources?: unknown; projectConfigRoot?: unknown }
  | { v: number; type: "warm"; settingSources?: unknown; projectConfigRoot?: unknown }
  | { v: number; type: "cool" }
  | { v: number; type: "reconnect"; server?: unknown }
  | { v: number; type: "history"; id: string; all?: unknown }
  | { v: number; type: "transcript"; id: string; conversation: string; all?: unknown }
  | { v: number; type: "keep"; id: string }
  | { v: number; type: "forget"; conversations?: unknown }
  | { v: number; type: "forgetHistory"; id: string }
  | { v: number; type: "permission"; request: string; behavior?: unknown; scope?: unknown }
  | { v: number; type: "question"; request: string; answers?: unknown }
  | { v: number; type: "sandboxRules"; id: string; cwd: string; settingSources?: unknown; projectConfigRoot?: unknown }
  | { v: number; type: "previewServer"; id: string; available?: unknown }
  | { v: number; type: "previewResult"; call?: unknown; text?: unknown; image?: unknown; error?: unknown }
  | { v: number; type: "risk"; request: string; dangerous?: unknown }
  | { v: number; type: "summarize"; id: string; prompt: string; cwd: string; model?: unknown };

type Event =
  | { type: "ready" }
  | { type: "text"; id: string; text: string }
  | { type: "done"; id: string }
  | { type: "variante"; id: string; nome: string }
  | { type: "ran"; id: string }
  | (Progress & { id: string })
  | (Edit & { id: string })
  | (Remembered & { id: string })
  | (Recalled & { id: string })
  | (Read & { id: string })
  | ({ type: "error"; id?: string; message: string } & TurnFailure)
  | ({ type: "limit"; id: string } & Limit)
  | { type: "signInRequired"; id: string }
  | { type: "sandboxUnavailable"; id: string; reason: string }
  | ({ type: "claude"; id: string } & ClaudeInfo)
  | { type: "outdated"; id: string; version?: string }
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
  | (AgentQuestion & { id: string })
  | { type: "permissionWithdrawn"; id: string; request: string }
  | (SandboxBlock & { type: "sandboxBlock"; id: string })
  | { type: "sandboxRules"; id: string; rules: SandboxRule[] }
  | (RiskQuestion & { type: "risk"; id: string; request: string })
  | ({ type: "usage"; id: string } & TurnUsage)
  | ({ type: "answeredBy"; id: string } & AnsweredBy)
  | { type: "models"; models: CatalogEntry[] }
  | (Denial & { type: "denial"; id: string })
  | { type: "mode"; id: string; permissionMode: PermissionMode };

function send(event: Event) {
  process.stdout.write(JSON.stringify({ v: version, ...event }) + "\n");
}

// La risposta di Bubo a una Richiesta: `lasting` quando vale per il resto della Sessione.
type Answer = { allowed: boolean; lasting: boolean };
const denied: Answer = { allowed: false, lasting: false };

// Le cartelle degli Allegati come arrivano da Bubo: solo percorsi assoluti.
function directoriesOf(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((dir): dir is string => typeof dir === "string" && dir.startsWith("/")) : [];
}

// Le Richieste di permesso in attesa della risposta di Bubo: si risolvono una volta sola, approvate solo con "allow".
const permissions = new Map<string, (answer: Answer) => void>();

// `canUseTool` della conversazione `id`. Chiude sempre su "no": se Bubo non si raggiunge, se la CLI ritira la
// Richiesta, se la risposta non è "allow". Se Bubo esce, stdin si chiude e il ponte esce senza approvare nulla.
// Con la Sandbox accesa, un Bash che chiede di uscirne arriva a Bubo segnato "fuori dalla sandbox".
// Un host fuori dai domini della Sandbox approvato per la Sessione porta con sé `WebFetch(domain:host)` di sessione.
function askBubo(id: string, isSandboxed: boolean): CanUseTool {
  return async (toolName, input, options) => {
    if (toolName === "AskUserQuestion") return askQuestion(id, input, options.signal);
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

// Le domande dell'agente in attesa delle risposte di Bubo: un elenco per posizione, oppure nulla se l'utente non risponde.
const questions = new Map<string, (replies: unknown) => void>();

// `AskUserQuestion` della conversazione `id`: Bubo mostra le domande nella Sessione e risponde con le scelte. Senza
// risposte valide, se Bubo non si raggiunge o se la CLI ritira la domanda (turno fermato, scadenza), è negata.
async function askQuestion(id: string, input: Record<string, unknown>, signal: AbortSignal) {
  if (signal.aborted) return questionResult(input, undefined, notShown);
  const request = randomUUID();
  const shown = agentQuestion(request, input);
  if (!shown) return questionResult(input, undefined, notShown);
  let reached = true;
  const replies = await new Promise<unknown>((resolve) => {
    questions.set(request, resolve);
    signal.addEventListener("abort", () => {
      resolve(undefined);
      if (questions.delete(request)) send({ type: "permissionWithdrawn", id, request });
    }, { once: true });
    try {
      send({ ...shown, id });
    } catch {
      reached = false;
      resolve(undefined);
    }
  });
  questions.delete(request);
  return questionResult(input, answersOf(input, replies), reached ? undefined : notShown);
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
    "Cerca per parole nell'Indice di Bubo: la memoria di Claude Code di tutti i Progetti, il CLAUDE.md dell'utente, il suo Secondo cervello, la cartella di note Markdown che ha scelto (per esempio un vault Obsidian), e le conversazioni passate, delle Sessioni di Bubo e della riga di comando. Note e conversazioni non arrivano in nessun altro modo: cercale qui quando servono. Restituisce i frammenti con il percorso del file, o con la conversazione, chi ha scritto e la data.",
    {
      testo: z.string().describe("Le parole da cercare"),
      progetto: z.string().optional().describe("Percorso della cartella di un Progetto, per cercare solo nella sua memoria"),
      fonte: z.enum(["memoria", "secondo-cervello", "conversazioni"]).optional()
        .describe("Dove cercare: \"memoria\" (memoria dei Progetti e CLAUDE.md), \"secondo-cervello\" (le note dell'utente) o \"conversazioni\" (le conversazioni passate); senza, ovunque"),
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
// `effort` è lo sforzo scelto dal router; senza, vale il default del modello. Prima di `done` il ponte dice chi ha
// risposto (`answeredBy`): il modello e lo sforzo effettivo, che l'SDK può aver declassato in silenzio.
// `env` si aggiunge all'ambiente del figlio: le porte della Sessione.
// `resume` è una conversazione della Cronologia CLI, o il turno prima di una Sessione (#412): si riprende sempre come
// fork, con un id nuovo. `claude` la riprende dal transcript in ~/.claude: lo store resta solo la copia, perché un
// `resume` letto dallo store gira con una cartella di configurazione temporanea, senza memoria automatica, skill né
// CLAUDE.md dell'utente. Dallo store solo se ~/.claude non l'ha più.
// `upTo` è il messaggio di `resume` a cui il fork si ferma, incluso (Continua da qui, #159): `resumeSessionAt`.
// `keep` è l'id che Bubo dà alla conversazione di un turno di una Sessione, da conservare: `claude` scrive il suo
// transcript in ~/.claude/projects come dalla riga di comando (`sessionStore` non funziona senza la scrittura locale)
// e l'SDK lo copia nello store, se c'è. Senza `keep`, come per le Domande, `claude` non scrive nulla.
// `keep` dice anche che il turno è di una Sessione: solo lì la memoria automatica è accesa.
// `sandbox` è la Sandbox della Sessione, se accesa: se non parte, `claude` esce prima di ogni comando.
// `preview` dice che la Sessione ha già un server: il turno parte con gli strumenti dell'Anteprima.
// `rules` sono le Risorse di squadra in vigore nel Progetto, come regole di sessione.
// `remembers` dà lo strumento `ricorda`: solo alle Domande.
// `permissionMode` è `auto` nella Modalità autonoma, `default` nelle altre Sessioni; senza, decide `claude`.
// `rosa` sono i nomi delle Varianti che l'agente può dare all'Orb con `⟦orb:nome⟧` (ADR 0002): vanno in coda al prompt
// di sistema, che senza resta quello vuoto dell'SDK. Il tag non arriva mai a Bubo come testo, diventa `variante`.
// Il cancello (`gate.ts`) passa prima di ogni strumento: con la Sandbox accesa o in Modalità autonoma.
// `unattended` è il turno di un'Esecuzione, senza nessuno davanti: nessuna Richiesta di permesso, le Regole
// dell'Automazione come regole di sessione, e prima di `done` un evento `denial` per ogni azione negata. Con `init`
// arriva `mode`, la modalità che `claude` ha scelto davvero: `auto` può non essere disponibile.
// `dirs` sono le cartelle che `claude` legge oltre a `cwd`, come `--add-dir`: quelle degli Allegati di una Domanda.
async function ask(id: string, prompt: string, cwd: string, sources: SettingSource[], projectConfigRoot?: string,
                   model?: string, env: Record<string, string> = {}, resume?: string, upTo?: string, keep?: string,
                   sandbox?: SandboxSettings, preview = false, rules: TeamRules = teamRules(undefined), remembers = false,
                   permissionMode?: PermissionMode, effort?: EffortLevel, rosa: string[] = [], unattended?: Unattended,
                   dirs: string[] = []) {
  const resumed = resume === undefined ? undefined : await transcriptOf(resume);
  const restored = resumed?.restored;
  const copy = store && (resumed?.isLocal === false ? store : mirrorOnly(store));
  const stopped = new AbortController();
  let servers: Promise<McpServerStatus[]> | undefined;
  const denials = unattended ? new Denials() : undefined;
  const gate = sandboxGate({
    cwd,
    sandbox,
    isDangerous: riskFromBubo(id, stopped.signal),
    isLocalServer: async (name) => {
      servers ??= conversation.mcpServerStatus();
      return isLocal((await servers).find((server) => server.name === name));
    },
    isUnattended: unattended !== undefined,
  }, (input) => denials?.gate(input));
  const ruleOptions = teamRuleOptions(rules, [...allowedBuboTools(remembers), ...allowedPreviewTools]);
  // Una volta sola, prima della fine del turno: dopo `done` Bubo non ascolta più.
  let reported = false;
  const report = (found: Parameters<Denials["result"]>[0] = []) => {
    if (!denials || reported) return;
    reported = true;
    for (const denial of denials.result(found)) send({ type: "denial", id, ...denial });
  };
  const memory = keep === undefined ? undefined : memoryHooks(id);
  const witness = new AnswerWitness();
  const conversation = query({
    prompt,
    options: {
      cwd,
      ...(dirs.length > 0 ? { additionalDirectories: dirs } : {}),
      projectConfigRoot,
      model,
      effort,
      env: { ...withAutoMemory(childEnv, keep !== undefined), ...env },
      pathToClaudeCodeExecutable: claudePath,
      settingSources: sources,
      mcpServers: turnServers(buboTools(id, remembers), preview ? previewTools(id, previewCalls) : undefined),
      ...ruleOptions,
      includePartialMessages: true,
      resume,
      forkSession: resume !== undefined,
      ...(resume !== undefined && upTo !== undefined ? { resumeSessionAt: upTo } : {}),
      sandbox,
      permissionMode,
      ...(rosa.length > 0 ? { systemPrompt: orbInstruction(rosa) } : {}),
      ...(keep === undefined ? { persistSession: false } : { sessionId: keep, persistSession: true, sessionStore: copy }),
      ...(unattended ? unattendedOptions(ruleOptions, unattended) : { canUseTool: askBubo(id, sandbox !== undefined) }),
      // La fine di un Bash dell'agente, riuscito o no, può avere avviato o fermato un server: Bubo cerca le porte
      // (spec 15). Un Bash fallito o interrotto passa da `PostToolUseFailure`, non da `PostToolUse`.
      // Le scritture in memoria, solo nelle Sessioni: nelle Domande la memoria automatica è spenta.
      // Grep e Glob riusciti danno i file letti alla Galassia (spec 11).
      hooks: {
        PreToolUse: [{ hooks: [gate] }, ...(memory?.PreToolUse ?? [])],
        PostToolUse: [ranBash(id, sandbox !== undefined), searchedFiles(id), ...(memory?.PostToolUse ?? [])],
        PostToolUseFailure: [ranBash(id, sandbox !== undefined), ...(memory?.PostToolUseFailure ?? [])],
        Stop: [witness.stopHook],
        // Con `'none'` la Richiesta non arriva a nessuno, ma l'hook scatta ancora con le regole che `claude` propone.
        ...(denials ? { PermissionRequest: [{ hooks: [async (input: HookInput) => {
          if (input.hook_event_name === "PermissionRequest") denials.requested(input);
          return {};
        }] }] } : {}),
      },
    },
  });
  running.set(id, conversation);
  // Perché il turno si è fermato: un limite rifiutato o un accesso non valido diventano eventi a sé.
  let limit: Limit | undefined;
  let failure: SDKAssistantMessageError | undefined;
  let retry: SDKAPIRetryMessage | undefined;
  let succeeded = false;
  // Le conversazioni a cui la copia ha perso un pezzo: si rifanno dal transcript a fine turno.
  const torn = new Set<string>();
  // Le cifre del turno: abbonamento o API key secondo la credenziale che `claude` dice di usare.
  let usage: UsageReader | undefined;
  // La versione di un `claude` troppo vecchio, vuota se non si sa.
  let outdated: string | undefined;
  const orb = new TurnVariante(new Set(rosa));
  const sendText = (text: string) => { if (text) send({ type: "text", id, text }); };
  try {
    for await (const message of conversation) {
      if (message.type === "system" && message.subtype === "init") {
        usage ??= new UsageReader(message.apiKeySource === "none" ? "subscription" : "apiKey", restored);
        if (unattended) send({ type: "mode", id, permissionMode: message.permissionMode });
      }
      if (message.type === "system" && message.subtype === "permission_denied") denials?.denied(message);
      // A ogni `init` il `claude` di questa Conversazione: si aggiorna anche con Bubo aperto. Sotto la minima di
      // Bubo, o rifiutato da Anthropic, la Conversazione si chiude prima del turno del modello.
      const claude = claudeInfo(message);
      if (claude) send({ type: "claude", id, ...claude });
      if (claude && isBelowMinimum(claude.version)) {
        outdated = claude.version;
        break;
      }
      if (isTooOldForAnthropic(message)) {
        outdated = "";
        break;
      }
      witness.read(message);
      const turn = usage?.read(message);
      if (turn) send({ type: "usage", id, ...turn });
      if (message.type === "system" && message.subtype === "api_retry") retry = message;
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
        const { text, variante } = orb.text(message.event.delta.text);
        if (variante) send({ type: "variante", id, nome: variante });
        sendText(text);
      } else if (message.type === "stream_event" && message.event.type === "content_block_stop") {
        sendText(orb.flush());
      } else if (message.type === "rate_limit_event") {
        sendQuota(quotaFromRateLimit(message.rate_limit_info));
        limit = limitFromRateLimit(message.rate_limit_info) ?? limit;
      } else if (message.type === "assistant" && message.error) {
        failure = message.error;
      } else if (message.type === "assistant" && message.parent_tool_use_id === null) {
        const variante = orb.tools(message.message.content.flatMap((block) => (block.type === "tool_use" ? [block] : [])));
        if (variante) send({ type: "variante", id, nome: variante });
      } else if (message.type === "result") {
        report(message.permission_denials);
        if (message.subtype === "success" && !message.is_error) succeeded = true;
        else if (limit) send({ type: "limit", id, ...limit });
        else if (failure === "authentication_failed") send({ type: "signInRequired", id });
        else send({ type: "error", id, message: message.subtype === "success" ? message.result : message.subtype,
                    ...turnFailure(failure, retry) });
      }
    }
    sendText(orb.flush());
    report();
    const answeredBy = witness.answeredBy();
    if (answeredBy) send({ type: "answeredBy", id, ...answeredBy });
    if (outdated !== undefined) send({ type: "outdated", id, ...(outdated && { version: outdated }) });
    // `done` dopo l'ultimo messaggio, non al `result`: mai "finita" con subagent ancora attivi.
    else if (succeeded) send({ type: "done", id });
  } catch (error) {
    // Interrotto senza un `result` valido: i token visti finora, con la cifra segnata incompleta.
    report();
    const turn = usage?.turn();
    if (turn && !turn.complete) send({ type: "usage", id, ...turn });
    const reason = sandbox ? sandboxUnavailableReason(error) : undefined;
    if (reason) send({ type: "sandboxUnavailable", id, reason });
    else send({ type: "error", id, message: error instanceof Error ? error.message : String(error) });
  } finally {
    if (outdated !== undefined) conversation.close();
    stopped.abort();
    running.delete(id);
    for (const session of torn) await repair(session);
  }
}

// Se il transcript di `session` è ancora in ~/.claude, e il totale che `resume` ne ripristina (`cost-state`), da togliere
// al turno: quei turni sono già contati, della Cronologia CLI o dei turni prima della Sessione. Dalla copia se la CLI
// l'ha già cancellato; senza `cost-state` `resume` non ripristina nulla.
async function transcriptOf(session: string): Promise<{ isLocal: boolean; restored?: Restored }> {
  const entries: SessionStoreEntry[] = [];
  try {
    await importSessionToStore(session, {
      append: async (key, read) => { if (!key.subpath) entries.push(...read); },
      load: async () => null,
    });
  } catch (error) {
    console.error("Transcript da riprendere non letto:", error instanceof Error ? error.message : error);
  }
  const isLocal = entries.length > 0;
  if (!isLocal && store) entries.push(...store.entries(session));
  return { isLocal, restored: restoredFrom(entries) };
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
// Dalla stessa conversazione anche il catalogo dei modelli per il router (`supportedModels()`), senza un secondo
// `claude`. Senza fonti di impostazioni caricate, un `availableModels` dell'utente o del Progetto qui non restringe
// l'elenco: lo sforzo effettivo di `answeredBy` resta la verità.
async function quota() {
  const conversation = query({
    prompt: (async function* () { await new Promise(() => {}); })(),
    options: { env: withAutoMemory(childEnv, false), pathToClaudeCodeExecutable: claudePath, settingSources: [], persistSession: false },
  });
  try {
    const [read, models] = await Promise.allSettled([readQuota(conversation), conversation.supportedModels()]);
    if (read.status === "fulfilled") sendQuota(read.value);
    else console.error("Quota non letta:", read.reason instanceof Error ? read.reason.message : read.reason);
    if (models.status === "fulfilled") send({ type: "models", models: catalogOf(models.value) });
    else console.error("Catalogo dei modelli non letto:", models.reason instanceof Error ? models.reason.message : models.reason);
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

// Gli ultimi messaggi di `session`, o tutti con `all`, per l'Indice: sempre con le funzioni dell'SDK.
async function transcript(id: string, session: string, all: boolean) {
  try {
    // Dopo la pulizia della CLI il transcript locale non c'è più: resta la copia.
    let read = await getSessionMessages(session);
    if (!read.length && store) read = await getSessionMessages(session, { sessionStore: store });
    send({ type: "transcript", id, messages: messages(read, dates(store?.entries(session) ?? []), all ? Infinity : transcriptLimit) });
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
      const upTo = typeof command.upTo === "string" ? command.upTo : undefined;
      const keep = typeof command.keep === "string" ? command.keep : undefined;
      const mode = command.permissionMode === "auto" || command.permissionMode === "default" ? command.permissionMode : undefined;
      void ask(command.id, command.prompt, command.cwd, settingSources(command.settingSources), root, model, env, resume, upTo, keep,
               sandboxSettings(command.sandbox), command.preview === true, teamRules(command.rules),
               command.remember === true, mode, effortOf(command.effort), rosaOf(command.orb), unattendedOf(command.unattended),
               directoriesOf(command.dirs));
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
    case "reconnect":
      // Dopo un `claude mcp login`: i turni in corso si ricollegano, i successivi lo fanno da soli.
      if (typeof command.server === "string") {
        for (const conversation of running.values()) void conversation.reconnectMcpServer(command.server).catch(() => {});
      }
      break;
    case "history": void history(command.id, command.all === true); break;
    case "transcript": void transcript(command.id, command.conversation, command.all === true); break;
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
    case "summarize":
      void summarize(command.id, command.prompt, summaryOptions(command.cwd, typeof command.model === "string" ? command.model : undefined, childEnv, claudePath), query, send);
      break;
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
    case "question":
      questions.get(command.request)?.(command.answers);
      questions.delete(command.request);
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
