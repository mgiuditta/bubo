import { realpathSync } from "node:fs";
import { isAbsolute, resolve, sep } from "node:path";

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

// Una Domanda legge i file e non li cambia mai: `inBrain` dice che gira nel Secondo cervello, `hidden` sono le sue
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

// Gli strumenti integrati di una Domanda: solo quelli che leggono. Quelli che scrivono, eseguono, delegano a un
// subagent o mandano fuori le note sono anche negati, perché nessuna regola dell'utente li riaccenda: nel Secondo
// cervello si scrive solo con `ricorda`.
export const readTools = ["Read", "Grep", "Glob", "WebSearch"];
export const deniedTools = ["Edit", "MultiEdit", "Write", "NotebookEdit", "Bash", "BashOutput", "KillShell", "Task", "WebFetch"];

// Le opzioni di una Domanda: gli strumenti che leggono; negati, dopo le regole `denied` della squadra, `deniedTools`
// e le cartelle `hidden` (una regola `Read` vale anche per Grep e Glob).
export function readOnlyOptions(turn: ReadOnly, denied: string[] = []): { tools: string[]; disallowedTools: string[] } {
  return {
    tools: readTools,
    disallowedTools: [...denied, ...deniedTools, ...turn.hidden.map((dir) => `Read(/${dir.replace(/\/+$/, "")}/**)`)],
  };
}

// Cosa sa una Domanda che gira nel Secondo cervello: dove si trova e che scrive solo con `ricorda`.
export const brainHomeInstruction = "Lavori dentro il Secondo cervello dell'utente: la cartella di lavoro è la sua "
  + "cartella di note. Leggi e cerca i file liberamente con Read, Grep e Glob, oltre che con cerca. Non puoi "
  + "modificare, creare né cancellare file: per scrivere nel Secondo cervello usa solo ricorda.";

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

// Perché Read, Grep o Glob non possono toccare `input` in una Domanda che gira in `cwd`: il loro percorso, reale, è
// in una cartella esclusa `hidden`, o la contiene (una ricerca da sopra la attraverserebbe); `undefined` se possono.
// Le regole `Read(...)` restano: questo vale anche con symlink e con nomi che hanno caratteri da glob.
export function hiddenPathDenial(tool: string, input: unknown, cwd: string, hidden: string[]): string | undefined {
  if (hidden.length === 0 || !["Read", "Grep", "Glob"].includes(tool)) return undefined;
  const fields = (input ?? {}) as { file_path?: unknown; path?: unknown };
  const raw = typeof fields.file_path === "string" ? fields.file_path : typeof fields.path === "string" ? fields.path : cwd;
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
