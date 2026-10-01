import type { SDKMessage } from "@anthropic-ai/claude-agent-sdk";

// Ciò da cui Bubo ricava l'Attività di una Sessione: lo stato della conversazione e il riassunto di una riga.
// `session_state_changed` arriva solo con CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS=1; `idle` scatta dopo il
// risultato e dopo la fine dei subagent in background. `requires_action` quando `claude` aspetta una
// risposta di `canUseTool`.
export type Progress =
  | { type: "state"; state: "idle" | "running" | "requires_action" }
  | { type: "summary"; text: string };

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
