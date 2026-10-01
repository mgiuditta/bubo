import type { SDKMessage } from "@anthropic-ai/claude-agent-sdk";

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

const editLines = 100;
const editLineLength = 200;

const summaryLength = 200;

export function progress(message: SDKMessage): Progress | undefined {
  if (message.type === "system" && message.subtype === "session_state_changed") {
    return { type: "state", state: message.state };
  }
  // Solo il filo principale: i subagent hanno `parent_tool_use_id`; un errore dell'API non è un riassunto.
  if (message.type === "assistant" && !message.error && message.parent_tool_use_id === null) {
    const text = message.message.content.flatMap((block) => (block.type === "text" ? [block.text] : [])).join("\n");
    const line = text.split("\n").map((line) => line.replace(/^[#>*\-\s]+/, "").trim()).find((line) => line.length > 0);
    if (line) return { type: "summary", text: line.length > summaryLength ? line.slice(0, summaryLength - 1) + "…" : line };
  }
  return undefined;
}

export function edits(message: SDKMessage): Edit[] {
  if (message.type !== "assistant" || message.error) return [];
  return message.message.content.flatMap((block) => {
    if (block.type !== "tool_use" || (block.name !== "Edit" && block.name !== "Write")) return [];
    const input = block.input as { file_path?: unknown; new_string?: unknown; content?: unknown };
    const text = block.name === "Edit" ? input.new_string : input.content;
    if (typeof input.file_path !== "string" || typeof text !== "string") return [];
    const lines = [...new Set(text.split("\n").map((line) => line.trim()).filter((line) => line.length > 0))]
      .slice(0, editLines).map((line) => line.slice(0, editLineLength));
    return [{ type: "edit" as const, file: input.file_path, lines }];
  });
}
