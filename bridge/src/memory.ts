import type { SDKMessage } from "@anthropic-ai/claude-agent-sdk";
import { readFileSync, statSync } from "node:fs";
import { normalize } from "node:path";

// La memoria automatica (`~/.claude/projects/<repo>/memory/`) è la Memoria di Progetto: accesa dove c'è un Progetto,
// nelle Sessioni e nell'ispezione, come nella CLI; spenta nelle Domande, che non devono ereditare i ricordi del
// repo da cui partono (spec 13).
export function withAutoMemory(env: Record<string, string | undefined>, isOn: boolean): Record<string, string | undefined> {
  const { CLAUDE_CODE_DISABLE_AUTO_MEMORY: _ignored, ...rest } = env;
  return isOn ? rest : { ...rest, CLAUDE_CODE_DISABLE_AUTO_MEMORY: "1" };
}

// Una scrittura dell'agente nella memoria, per la riga "Ricordato". `before` e `after` sono il file prima e dopo, per
// Annulla: `before` manca se il file è nuovo; mancano tutti e due se uno dei due è troppo grande (niente Annulla).
export type Remembered = { type: "remembered"; file: string; before?: string; after?: string };

// I ricordi che `claude` porta nel turno (`memory_recall`), per la riga "Richiamato".
export type Recalled = {
  type: "recalled";
  mode: "select" | "synthesize";
  memories: { path: string; scope: "personal" | "team" | "organization"; content?: string }[];
};

// Oltre questa misura un file non si copia: la memoria di Claude Code ne carica al più 25 KB per l'indice.
const fileLimit = 256 * 1024;
const recalledLimit = 20;
const recalledContentLength = 20_000;

// Il file di memoria che `input` di `Write` o `Edit` scrive: `<config>/projects/<repo>/memory/<nome>`, come la
// cartella che Claude Code usa; `undefined` per ogni altro file.
export function memoryFile(input: unknown, configDirectory: string): string | undefined {
  const path = (input as { file_path?: unknown } | null)?.file_path;
  if (typeof path !== "string" || !path.startsWith("/")) return undefined;
  const file = normalize(path);
  const projects = normalize(configDirectory + "/projects/");
  if (!file.startsWith(projects)) return undefined;
  const parts = file.slice(projects.length).split("/");
  return parts.length === 3 && parts[0] && parts[1] === "memory" && parts[2] ? file : undefined;
}

// Il contenuto di `file`, `null` se non esiste, `undefined` se non si legge o è troppo grande.
function contents(file: string): string | null | undefined {
  try {
    if (statSync(file).size > fileLimit) return undefined;
    return readFileSync(file, "utf8");
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === "ENOENT" ? null : undefined;
  }
}

// Le scritture in memoria in corso: il file com'era a `PreToolUse`, fino al `PostToolUse` della stessa chiamata.
export class MemoryWrites {
  private readonly before = new Map<string, { file: string; text: string | null | undefined }>();

  constructor(private readonly configDirectory: string) {}

  // Prima della scrittura `call`: copia il file, se è di memoria.
  start(call: string, input: unknown) {
    const file = memoryFile(input, this.configDirectory);
    if (file) this.before.set(call, { file, text: contents(file) });
  }

  // Dopo la scrittura `call`, riuscita: la riga da mostrare, se era in memoria.
  finish(call: string): Remembered | undefined {
    const started = this.before.get(call);
    this.before.delete(call);
    if (!started) return undefined;
    const after = contents(started.file);
    if (started.text === undefined || typeof after !== "string") return { type: "remembered", file: started.file };
    return { type: "remembered", file: started.file, ...(started.text === null ? {} : { before: started.text }), after };
  }

  // La scrittura `call` è fallita: nessuna riga.
  forget(call: string) {
    this.before.delete(call);
  }
}

export function recalled(message: SDKMessage): Recalled | undefined {
  if (message.type !== "system" || message.subtype !== "memory_recall") return undefined;
  return {
    type: "recalled",
    mode: message.mode,
    memories: message.memories.slice(0, recalledLimit).map(({ path, scope, content }) => ({
      path, scope, ...(content === undefined ? {} : { content: content.slice(0, recalledContentLength) }),
    })),
  };
}
