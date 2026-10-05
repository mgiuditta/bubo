import { realpathSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, resolve, sep } from "node:path";
import { z } from "zod";

// Gli strumenti di Bubo che `claude` usa senza chiedere: `cerca` sempre, `ricorda` nelle Domande e nelle Sessioni,
// dove scrive nel Secondo cervello; ogni scrittura si può annullare da Bubo. Le Esecuzioni non lo ricevono.
export function allowedBuboTools(remembers: boolean): string[] {
  return remembers ? ["mcp__bubo__cerca", "mcp__bubo__ricorda"] : ["mcp__bubo__cerca"];
}

// Il prompt di sistema del turno: le sue parti in ordine, quelle che ci sono (l'istruzione dell'Orb, quella della
// Domanda nel Secondo cervello, il Profilo e le Regole); senza nessuna, `undefined`, e resta quello vuoto dell'SDK.
export function systemPromptOf(...parts: (string | undefined)[]): string | undefined {
  const found = parts.filter((part): part is string => part !== undefined && part.length > 0);
  return found.length > 0 ? found.join("\n\n") : undefined;
}

// Una Domanda legge i file da sola e li cambia solo dopo una Richiesta: `inBrain` dice che gira nel Secondo cervello, `hidden` sono le sue
// cartelle escluse, che non legge.
export type ReadOnly = { inBrain: boolean; hidden: string[] };

export function readOnlyOf(value: unknown): ReadOnly | undefined {
  if (typeof value !== "object" || value === null) return undefined;
  const { brain, hidden } = value as { brain?: unknown; hidden?: unknown };
  return {
    inBrain: brain === true,
    hidden: Array.isArray(hidden) ? hidden.filter((dir): dir is string => typeof dir === "string" && dir.startsWith("/")) : [],
  };
}

// Gli strumenti integrati di una Domanda: quelli che leggono partono da soli; quelli che scrivono, eseguono o vanno in
// rete passano ognuno da una Richiesta di permesso nella chat, come nelle Sessioni. Restano negati solo i subagent:
// lavorerebbero fuori dalla vista della Domanda.
export const readTools = ["Read", "Grep", "Glob", "WebSearch"];
export const askedTools = ["Edit", "MultiEdit", "Write", "NotebookEdit", "Bash", "BashOutput", "KillShell", "WebFetch"];
export const deniedTools = ["Task"];

// Perché uno strumento di `askedTools` chiede sempre in una Domanda: nessuna regola `allow` né `defaultMode` delle
// impostazioni dell'utente lo lascia partire da solo; `undefined` per gli altri.
export function askedToolReason(tool: string): string | undefined {
  return askedTools.includes(tool) ? "In una Domanda ogni scrittura, comando o accesso alla rete si approva nella chat." : undefined;
}

// Le opzioni di una Domanda: gli strumenti che leggono e quelli che chiedono; negati, dopo le regole `denied` della
// squadra, `deniedTools` e le cartelle `hidden` (una regola `Read` vale anche per Grep e Glob).
export function readOnlyOptions(turn: ReadOnly, denied: string[] = []): { tools: string[]; disallowedTools: string[] } {
  return {
    tools: [...readTools, ...askedTools],
    disallowedTools: [...denied, ...deniedTools, ...turn.hidden.map((dir) => `Read(/${dir.replace(/\/+$/, "")}/**)`)],
  };
}

// Cosa sa una Domanda che gira nel Secondo cervello: dove si trova, che legge liberamente e che il resto lo chiede.
export const brainHomeInstruction = "Lavori dentro il Secondo cervello dell'utente: la cartella di lavoro è la sua "
  + "cartella di note. Leggi e cerca i file liberamente con Read, Grep e Glob, oltre che con cerca. Per salvare un "
  + "ricordo o una nota usa ricorda. Quando serve fare di più (creare cartelle o file, lanciare uno script, usare un "
  + "Server MCP, aprire un link) fallo con gli strumenti che hai: l'utente approva ogni azione nella chat. Non "
  + "rimandarlo a una Sessione o a un altro strumento per cose che puoi fare tu.";

// Il percorso reale di `path`, symlink risolti; se non esiste ancora, quello della cartella più vicina che esiste.
function realPath(path: string): string {
  try {
    // `native` dà le maiuscole del disco: su un volume che non le distingue, «archivio» è «Archivio».
    return realpathSync.native(path);
  } catch {
    const parent = resolve(path, "..");
    return parent === path ? path : resolve(realPath(parent), path.slice(parent.length + 1));
  }
}

// Gli strumenti che le cartelle escluse fermano sul percorso: quelli che leggono e quelli che scrivono un file.
export const hiddenGuardedTools = ["Read", "Grep", "Glob", "Edit", "MultiEdit", "Write", "NotebookEdit"];

// Perché Read, Grep, Glob o uno strumento che scrive non possono toccare `input` in una Domanda che gira in `cwd`: il loro percorso, reale, è
// in una cartella esclusa `hidden`, o la contiene (una ricerca da sopra la attraverserebbe); `undefined` se possono.
// Le regole `Read(...)` restano: questo vale anche con symlink e con nomi che hanno caratteri da glob.
export function hiddenPathDenial(tool: string, input: unknown, cwd: string, hidden: string[]): string | undefined {
  if (hidden.length === 0 || !hiddenGuardedTools.includes(tool)) return undefined;
  const fields = (input ?? {}) as { file_path?: unknown; notebook_path?: unknown; path?: unknown; pattern?: unknown; glob?: unknown };
  // Un pattern di Glob, o il filtro `glob` di Grep, assoluto, dalla home, con `..` ovunque (anche in `{..,x}`) o con
  // escape `\\` può uscire dalla cartella cercata: negato senza provare a interpretarlo.
  const pattern = tool === "Glob" ? fields.pattern : fields.glob;
  if (tool !== "Read" && typeof pattern === "string" && /^[/~]|\.\.|\\/.test(pattern)) {
    return "Con cartelle escluse dal Secondo cervello i pattern restano dentro la cartella cercata: niente percorsi assoluti né «..».";
  }
  const given = typeof fields.file_path === "string" ? fields.file_path
    : typeof fields.notebook_path === "string" ? fields.notebook_path
    : typeof fields.path === "string" ? fields.path : cwd;
  // `~` lo espande la CLI: qui pure, perché il percorso confrontato sia quello che verrà letto.
  const raw = given === "~" || given.startsWith("~/") ? homedir() + given.slice(1) : given;
  const target = realPath(isAbsolute(raw) ? raw : resolve(cwd, raw));
  const inside = (child: string, parent: string) => child === parent || child.startsWith(parent + sep);
  for (const dir of hidden.map(realPath)) {
    if (inside(target, dir)) return "Questa cartella è esclusa dal Secondo cervello: Bubo non la legge.";
    if (tool !== "Read" && inside(dir, target)) {
      return "La ricerca attraverserebbe una cartella esclusa dal Secondo cervello: usa cerca, o cerca in una sottocartella.";
    }
  }
  return undefined;
}

// `cerca` e `ricorda`, gli stessi per `claude` (il server MCP `bubo`) e per `copilot` (strumenti della sessione di una
// Domanda): Bubo risponde a ogni chiamata con `found`.
// `cerca` chiede l'Indice a Bubo: i frammenti restano tra Bubo e il modello.
// `ricorda` fa scrivere a Bubo nel Secondo cervello: una nota nuova in `Bubo/Note/`, del testo in coda a una nota, o
// una nota riscritta; quelle dell'utente, fuori da `Bubo/`, solo dopo la sua conferma.
export const searchTool = {
  name: "cerca",
  description: "Cerca per parole nell'Indice di Bubo: la memoria di Claude Code di tutti i Progetti, il CLAUDE.md dell'utente, il suo Secondo cervello, la cartella di note Markdown che ha scelto (per esempio un vault Obsidian), e le conversazioni passate, delle Sessioni di Bubo e della riga di comando. Note e conversazioni non arrivano in nessun altro modo: cercale qui quando servono. Restituisce i frammenti con il percorso del file, o con la conversazione, chi ha scritto e la data; per le note del Secondo cervello anche la citazione [[…]] da mettere nella risposta dopo ogni affermazione che ne viene.",
  shape: {
    testo: z.string().describe("Le parole da cercare"),
    progetto: z.string().optional().describe("Percorso della cartella di un Progetto, per cercare solo nella sua memoria"),
    fonte: z.enum(["memoria", "secondo-cervello", "conversazioni"]).optional()
      .describe("Dove cercare: \"memoria\" (memoria dei Progetti e CLAUDE.md), \"secondo-cervello\" (le note dell'utente) o \"conversazioni\" (le conversazioni passate); senza, ovunque"),
  },
};

export const rememberTool = {
  name: "ricorda",
  description: "Scrive nel Secondo cervello dell'utente, la sua cartella di note Markdown. Usalo quando l'utente chiede di ricordare qualcosa (\"ricordati questo\", \"segnati che…\") o quando il prompt di sistema ti dice di salvare da solo. Modi: \"nuova\" crea una nota in Bubo/Note con titolo; \"aggiungi\" mette il testo in coda alla nota indicata; \"riscrivi\" sostituisce tutta la nota indicata. Le note fuori da Bubo/ sono dell'utente: per riscriverle chiedigli prima e passa confermato solo se ha detto di sì. Anche ogni modifica di Bubo/Profilo.md vuole la conferma dell'utente; Bubo/Regole.md e Bubo/Intervista.md non si scrivono mai. Non cancella note. L'utente può annullare ogni scrittura. Restituisce dove ha scritto, o perché non l'ha fatto.",
  shape: {
    testo: z.string().describe("Cosa scrivere, in Markdown, comprensibile anche letto da solo tra mesi"),
    modo: z.enum(["nuova", "aggiungi", "riscrivi"]).optional().describe("Come scrivere; senza, \"nuova\""),
    titolo: z.string().optional().describe("Per una nota nuova: un titolo breve, che diventa il nome del file"),
    nota: z.string().optional().describe("Per aggiungere o riscrivere: il percorso della nota .md relativo al Secondo cervello, per esempio Bubo/Profilo.md"),
    confermato: z.boolean().optional().describe("Solo dopo che l'utente ha detto di sì a riscrivere una sua nota fuori da Bubo/"),
  },
};

export type SearchArguments = z.infer<z.ZodObject<typeof searchTool.shape>>;
export type RememberArguments = z.infer<z.ZodObject<typeof rememberTool.shape>>;

/** Una chiamata a `cerca` o `ricorda` per Bubo, senza l'`id` con cui torna il suo `found`. */
export type BuboToolCall =
  | { type: "search"; query: string; project?: string; source?: string; conversation: string }
  | { type: "remember"; conversation: string; mode: "nuova" | "aggiungi" | "riscrivi"; title?: string; note?: string; text: string; confirmed?: boolean };

/** La chiamata a `cerca` della conversazione `conversation`, per la riga "Richiamato". */
export function searchCall({ testo, progetto, fonte }: SearchArguments, conversation: string): BuboToolCall {
  return { type: "search", query: testo, project: progetto, source: fonte, conversation };
}

/** La chiamata a `ricorda` della conversazione `conversation`: la scrittura va nel registro e si può annullare. */
export function rememberCall({ testo, modo, titolo, nota, confermato }: RememberArguments, conversation: string): BuboToolCall {
  return { type: "remember", conversation, mode: modo ?? "nuova", title: titolo, note: nota, text: testo, confirmed: confermato };
}
