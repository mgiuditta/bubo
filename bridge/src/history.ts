// La Cronologia CLI, letta solo con le funzioni dell'SDK: nessun parsing del JSONL, nessuna scrittura in ~/.claude.
import type { SDKSessionInfo, SessionMessage, SessionStoreEntry } from "@anthropic-ai/claude-agent-sdk";
import { withoutOrbTags } from "./orb";

export type Conversation = { id: string; title: string; cwd?: string; branch?: string; lastModified: number };
// `id` è l'uuid del messaggio; `date`, in millisecondi, c'è solo se la conversazione è nella copia di Bubo.
export type Message = { id: string; role: "user" | "assistant"; text: string; date?: number };

// Le conversazioni lette per prime: quelle che Bubo mostra senza una ricerca.
export const firstPage = 50;
// I messaggi più recenti che si leggono di una conversazione.
export const transcriptLimit = 200;

export function conversation(info: SDKSessionInfo): Conversation {
  return { id: info.sessionId, title: info.summary, cwd: info.cwd, branch: info.gitBranch, lastModified: info.lastModified };
}

// Solo il testo di chi parla: risultati degli strumenti, ragionamenti e comandi locali restano fuori.
// Gli ultimi `limit` messaggi (`Infinity` per tutti); la data da `dates`, se il messaggio c'è.
export function messages(session: SessionMessage[], dates = new Map<string, number>(), limit = transcriptLimit): Message[] {
  return session.flatMap((entry) => {
    if (entry.type === "system" || entry.parent_tool_use_id) return [];
    const content = (entry.message as { content?: unknown } | null)?.content;
    const written = typeof content === "string" ? content
      : Array.isArray(content)
        ? content.filter((block) => block?.type === "text" && typeof block.text === "string").map((block) => block.text).join("\n")
        : "";
    // Il tag dell'Orb è per Bubo, non per chi rilegge.
    const text = entry.type === "assistant" ? withoutOrbTags(written) : written;
    if (!text.trim() || text.startsWith("<command-name>") || text.startsWith("<local-command")) return [];
    const date = dates.get(entry.uuid);
    return [{ id: entry.uuid, role: entry.type, text, ...(date === undefined ? {} : { date }) }];
  }).slice(-limit);
}

// La data di ogni messaggio dalle voci della copia: un campo tipizzato dell'SDK, non il JSONL.
export function dates(entries: SessionStoreEntry[]): Map<string, number> {
  const found = new Map<string, number>();
  for (const entry of entries) {
    const date = entry.timestamp === undefined ? NaN : Date.parse(entry.timestamp);
    if (entry.uuid && !Number.isNaN(date)) found.set(entry.uuid, date);
  }
  return found;
}
