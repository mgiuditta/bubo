import { extname } from "node:path";
import { previewServerName } from "./preview";

// La Variante durante il lavoro (ADR 0002): l'agente scrive `⟦orb:nome⟧` quando cambia ciò che fa; quando non lo fa,
// la Variante viene dallo strumento che usa. Il tag non arriva mai all'utente.

const opening = "⟦orb:";
const closing = "⟧";
// Più lungo di qualunque nome del Catalogo: oltre, ciò che sembrava un tag è testo.
const longestName = 64;

// Toglie i tag dal testo che arriva a pezzi: un tag può essere spezzato tra più pezzi, quindi l'inizio di un tag
// possibile resta in attesa del pezzo dopo. Gli spazi e l'a capo subito dopo un tag cadono con lui.
export class OrbTags {
  private pending = "";
  private skipsSpace = false;

  // `known` sono i nomi che l'agente ha ricevuto: un altro nome toglie il tag ma non cambia l'Orb.
  constructor(private readonly known: ReadonlySet<string>) {}

  // Il testo da mostrare di `chunk`, e i nomi validi dei tag che chiude, in ordine.
  push(chunk: string): { text: string; names: string[] } {
    let rest = this.pending + chunk;
    this.pending = "";
    let text = "";
    const names: string[] = [];
    while (rest.length > 0) {
      if (this.skipsSpace) {
        const space = rest.match(/^[ \t]*\n?/)![0];
        rest = rest.slice(space.length);
        // Fino al primo a capo, o al primo carattere che non è uno spazio.
        if (rest.length === 0 && !space.endsWith("\n")) return { text, names };
        this.skipsSpace = false;
        continue;
      }
      const start = rest.indexOf("⟦");
      if (start < 0) {
        text += rest;
        break;
      }
      text += rest.slice(0, start);
      rest = rest.slice(start);
      const tag = rest.match(/^⟦orb:([^⟦⟧\n]*)⟧/u);
      if (tag && tag[1].length <= longestName) {
        const name = tag[1].trim();
        if (this.known.has(name)) names.push(name);
        rest = rest.slice(tag[0].length);
        this.skipsSpace = true;
      } else if (couldBecomeTag(rest)) {
        this.pending = rest;
        break;
      } else {
        text += rest[0];
        rest = rest.slice(1);
      }
    }
    return { text, names };
  }

  // Ciò che resta in attesa a fine testo: un tag mai chiuso non è un tag, e si mostra.
  flush(): string {
    const text = this.pending;
    this.pending = "";
    this.skipsSpace = false;
    return text;
  }
}

// Se `text`, che comincia con "⟦", può ancora diventare un tag col pezzo dopo.
function couldBecomeTag(text: string): boolean {
  if (text.length < opening.length) return opening.startsWith(text);
  if (!text.startsWith(opening)) return false;
  const name = text.slice(opening.length);
  return name.length <= longestName && !/[⟦⟧\n]/u.test(name);
}

// `text` intero senza tag: i riassunti e le conversazioni rilette.
export function withoutOrbTags(text: string): string {
  if (!text.includes(opening)) return text;
  const tags = new OrbTags(new Set());
  return tags.push(text).text + tags.flush();
}

// L'istruzione all'agente, in coda al prompt di sistema: la rosa di nomi che Bubo gli dà, non tutto il Catalogo.
export function orbInstruction(names: readonly string[]): string {
  return `Bubo mostra all'utente un Orb che prende la forma di ciò che stai facendo. Quando cominci un'attività diversa `
    + `(cercare, leggere o scrivere codice, scrivere un testo, organizzare il lavoro…), scrivi da solo, prima del testo, `
    + `${opening}nome${closing} con la forma più adatta tra: ${names.join(", ")}. Al più un tag per messaggio e solo quando `
    + `l'attività cambia; mai un nome fuori elenco. L'utente non vede il tag: non nominarlo.`;
}

// I file di testo, non di codice: scriverli è lavoro di scrittura.
const prose = new Set([".md", ".markdown", ".mdx", ".txt", ".rtf", ".adoc", ".rst", ".tex"]);

// Il ripiego dagli strumenti: la Variante di ciò che lo strumento `tool` fa, guardando anche il file toccato.
// Solo le prime Varianti di ogni Categoria, che la rosa di Bubo contiene sempre. `undefined` lascia l'Orb com'è.
export function varianteOfTool(tool: string, input: unknown): string | undefined {
  const file = (input as { file_path?: unknown; notebook_path?: unknown } | null) ?? {};
  const path = typeof file.file_path === "string" ? file.file_path
    : typeof file.notebook_path === "string" ? file.notebook_path : undefined;
  switch (tool) {
    case "Read":
      return path && !prose.has(extname(path).toLowerCase()) ? "parentesi" : "lente";
    case "Edit":
    case "Write":
      return path && prose.has(extname(path).toLowerCase()) ? "pennello" : "parentesi";
    case "NotebookEdit":
    case "Bash":
    case "LSP":
    case "EnterWorktree":
    case "ExitWorktree":
      return "parentesi";
    case "Grep":
    case "Glob":
    case "WebSearch":
    case "WebFetch":
    case "ToolSearch":
    case "ListMcpResourcesTool":
    case "ReadMcpResourceTool":
    case "ReadMcpResourceDirTool":
    case "ReportFindings":
    case "mcp__bubo__cerca":
      return "lente";
    case "mcp__bubo__ricorda":
    case "ClaudeDesign":
    case "Artifact":
      return "pennello";
    case "CronCreate":
    case "CronDelete":
    case "CronList":
    case "ScheduleWakeup":
    case "RemoteTrigger":
      return "clessidra";
    case "AskUserQuestion":
    case "SendFeedback":
    case "PushNotification":
    case "ReadNotifications":
    case "ShowOnboardingRolePicker":
      return "fumetto";
    case "Agent":
    case "Task":
    case "TaskCreate":
    case "TaskGet":
    case "TaskUpdate":
    case "TaskList":
    case "TaskStop":
    case "TodoWrite":
    case "Workflow":
    case "Monitor":
    case "EnterPlanMode":
    case "ExitPlanMode":
    case "Projects":
    case "ProposeSkills":
    case "ProposeGoal":
    case "RefreshMcpTools":
    case "Skill":
      return "robot";
    default:
      // Gli strumenti dell'Anteprima guardano e provano una pagina: lavoro di codice.
      return tool.startsWith(`mcp__${previewServerName}__`) ? "parentesi" : undefined;
  }
}

// La Variante di un turno: i tag dell'agente, o il ripiego quando non ne scrive. Appena l'agente scrive un tag segue
// l'istruzione, e il ripiego tace fino alla fine del turno: i passi senza tag continuano l'attività del tag.
export class TurnVariante {
  private readonly tags: OrbTags;
  private hasTagged = false;
  private last: string | undefined;

  constructor(private readonly known: ReadonlySet<string>) {
    this.tags = new OrbTags(known);
  }

  // Il testo da mostrare di `chunk`, e la Variante da mandare a Bubo, se cambia.
  text(chunk: string): { text: string; variante?: string } {
    const { text, names } = this.tags.push(chunk);
    if (names.length > 0) this.hasTagged = true;
    return { text, variante: this.changed(names.at(-1)) };
  }

  // Ciò che resta in attesa a fine messaggio.
  flush(): string {
    return this.tags.flush();
  }

  // La Variante del primo strumento con un ripiego tra `tools`, se l'agente non ha scritto tag e cambia.
  tools(tools: readonly { name: string; input: unknown }[]): string | undefined {
    if (this.hasTagged) return undefined;
    const name = tools.map((tool) => varianteOfTool(tool.name, tool.input)).find((name) => name && this.known.has(name));
    return this.changed(name);
  }

  private changed(name: string | undefined): string | undefined {
    if (name === undefined || name === this.last) return undefined;
    this.last = name;
    return name;
  }
}

// La rosa del comando `ask`: solo nomi come quelli del Catalogo, al più `rosaLimit`; altro non entra nel prompt.
const rosaLimit = 64;
export function rosaOf(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const names = value.filter((name): name is string => typeof name === "string" && /^[a-z0-9]+(-[a-z0-9]+)*$/.test(name)
    && name.length <= longestName);
  return [...new Set(names)].slice(0, rosaLimit);
}
