import { isAbsolute, resolve } from "node:path";
import { withoutOrbTags } from "./orb";
import type { PostToolUseHookInput, SDKMessage } from "@anthropic-ai/claude-agent-sdk";

// Ciò da cui Bubo ricava l'Attività di una Sessione: lo stato della conversazione e il riassunto di una riga.
// `session_state_changed` arriva solo con CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS=1; `idle` scatta dopo il
// risultato e dopo la fine dei subagent in background. `requires_action` quando `claude` aspetta una
// risposta di `canUseTool`.
export type Progress =
  | { type: "state"; state: "idle" | "running" | "requires_action" }
  | { type: "summary"; text: string };

// Una scrittura chiesta dall'agente, per dare a ogni blocco della revisione il suo perché: Bubo l'abbina al
// riassunto del momento. Solo le righe scritte, senza spazi ai lati, uniche e al più 100.
export type Edit = { type: "edit"; file: string; lines: string[] };

// I file che l'agente legge, assoluti, per la Galassia (spec 11): `Read` dal suo `file_path`, `Grep` e `Glob` dai
// `filenames` della risposta. Al più 100 per evento.
export type Read = { type: "read"; files: string[] };

const readFiles = 100;
const editLines = 100;
const editLineLength = 200;

const summaryLength = 200;

export function progress(message: SDKMessage): Progress | undefined {
  if (message.type === "system" && message.subtype === "session_state_changed") {
    return { type: "state", state: message.state };
  }
  // Solo il filo principale: i subagent hanno `parent_tool_use_id`; un errore dell'API non è un riassunto.
  if (message.type === "assistant" && !message.error && message.parent_tool_use_id === null) {
    const text = withoutOrbTags(message.message.content.flatMap((block) => (block.type === "text" ? [block.text] : [])).join("\n"));
    const line = text.split("\n").map((line) => line.replace(/^[#>*\-\s]+/, "").trim()).find((line) => line.length > 0);
    if (line) return { type: "summary", text: line.length > summaryLength ? line.slice(0, summaryLength - 1) + "…" : line };
  }
  return undefined;
}

// `NotebookEdit` è una scrittura come `Edit` e `Write` (`NotebookEditInput`); nella 0.3.286 non c'è `MultiEdit`.
export function edits(message: SDKMessage): Edit[] {
  if (message.type !== "assistant" || message.error) return [];
  return message.message.content.flatMap((block) => {
    if (block.type !== "tool_use") return [];
    const input = block.input as { file_path?: unknown; notebook_path?: unknown; new_string?: unknown; content?: unknown; new_source?: unknown };
    const [file, text] = block.name === "Edit" ? [input.file_path, input.new_string]
      : block.name === "Write" ? [input.file_path, input.content]
      : block.name === "NotebookEdit" ? [input.notebook_path, input.new_source]
      : [undefined, undefined];
    if (typeof file !== "string" || typeof text !== "string") return [];
    const lines = [...new Set(text.split("\n").map((line) => line.trim()).filter((line) => line.length > 0))]
      .slice(0, editLines).map((line) => line.slice(0, editLineLength));
    return [{ type: "edit" as const, file, lines }];
  });
}

// Le letture di `Read`, appena l'agente le chiede (`FileReadInput`).
export function reads(message: SDKMessage): Read[] {
  if (message.type !== "assistant" || message.error) return [];
  return message.message.content.flatMap((block) => {
    if (block.type !== "tool_use" || block.name !== "Read") return [];
    const path = (block.input as { file_path?: unknown }).file_path;
    return typeof path === "string" ? [{ type: "read" as const, files: [path] }] : [];
  });
}

// I file trovati da `Grep` e `Glob`, dalla risposta dell'hook `PostToolUse` (`GrepOutput`, `GlobOutput`): solo lì
// l'SDK li dà. I percorsi relativi si risolvono dalla cartella di lavoro dell'agente.
export function searched(input: PostToolUseHookInput): Read | undefined {
  if (input.tool_name !== "Grep" && input.tool_name !== "Glob") return undefined;
  const filenames = (input.tool_response as { filenames?: unknown } | null)?.filenames;
  if (!Array.isArray(filenames)) return undefined;
  const files = filenames.filter((file): file is string => typeof file === "string").slice(0, readFiles)
    .map((file) => (isAbsolute(file) ? file : resolve(input.cwd, file)));
  return files.length > 0 ? { type: "read", files } : undefined;
}
