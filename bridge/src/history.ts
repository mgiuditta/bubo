// La Cronologia CLI, letta solo con le funzioni dell'SDK: nessun parsing del JSONL, nessuna scrittura in ~/.claude.
import type { SDKSessionInfo, SessionMessage } from "@anthropic-ai/claude-agent-sdk";

export type Conversation = { id: string; title: string; cwd?: string; branch?: string; lastModified: number };
export type Message = { role: "user" | "assistant"; text: string };

// Le conversazioni lette per prime: quelle che Bubo mostra senza una ricerca.
export const firstPage = 50;
// I messaggi più recenti che si leggono di una conversazione.
export const transcriptLimit = 200;

export function conversation(info: SDKSessionInfo): Conversation {
  return { id: info.sessionId, title: info.summary, cwd: info.cwd, branch: info.gitBranch, lastModified: info.lastModified };
}

// Solo il testo di chi parla: risultati degli strumenti, ragionamenti e comandi locali restano fuori.
export function messages(session: SessionMessage[]): Message[] {
  return session.flatMap((entry) => {
    if (entry.type === "system" || entry.parent_tool_use_id) return [];
    const content = (entry.message as { content?: unknown } | null)?.content;
    const text = typeof content === "string" ? content
      : Array.isArray(content)
        ? content.filter((block) => block?.type === "text" && typeof block.text === "string").map((block) => block.text).join("\n")
        : "";
    if (!text.trim() || text.startsWith("<command-name>") || text.startsWith("<local-command")) return [];
    return [{ role: entry.type, text }];
  }).slice(-transcriptLimit);
}
