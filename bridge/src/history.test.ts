import { expect, test } from "bun:test";
import type { SessionMessage } from "@anthropic-ai/claude-agent-sdk";
import { conversation, dates, messages, transcriptLimit } from "./history";

function entry(type: SessionMessage["type"], content: unknown, toolUse: string | null = null, uuid = "u"): SessionMessage {
  return { type, uuid, session_id: "s", message: { role: type, content }, parent_tool_use_id: toolUse, parent_agent_id: null };
}

test("una conversazione prende il titolo che mostra la CLI", () => {
  expect(conversation({ sessionId: "a", summary: "Correggi il login", lastModified: 1, cwd: "/p", gitBranch: "main", customTitle: "x" }))
    .toEqual({ id: "a", title: "Correggi il login", cwd: "/p", branch: "main", lastModified: 1 });
});

test("restano solo i testi di chi parla", () => {
  expect(messages([
    entry("user", "Ciao"),
    entry("assistant", [{ type: "thinking", thinking: "…" }, { type: "text", text: "Eccomi" }, { type: "tool_use", id: "t" }]),
    entry("user", [{ type: "tool_result", tool_use_id: "t", content: "segreto" }]),
    entry("assistant", [{ type: "text", text: "dal subagente" }], "t"),
    entry("user", "<command-name>/context</command-name>"),
    entry("system", "compattato"),
  ])).toEqual([{ id: "u", role: "user", text: "Ciao" }, { id: "u", role: "assistant", text: "Eccomi" }]);
});

test("di una conversazione lunga, solo gli ultimi messaggi", () => {
  const long = Array.from({ length: transcriptLimit + 5 }, (_, index) => entry("user", `${index}`));
  const read = messages(long);
  expect(read.length).toBe(transcriptLimit);
  expect(read[0].text).toBe("5");
});

test("per l'Indice, tutti i messaggi con la data della copia", () => {
  const long = Array.from({ length: transcriptLimit + 5 }, (_, index) => entry("user", `${index}`, null, `m${index}`));
  const read = messages(long, dates([{ type: "user", uuid: "m0", timestamp: "2026-10-01T08:00:00.000Z" }, { type: "user", uuid: "m1" }]), Infinity);
  expect(read.length).toBe(transcriptLimit + 5);
  expect(read[0]).toEqual({ id: "m0", role: "user", text: "0", date: Date.parse("2026-10-01T08:00:00.000Z") });
  expect(read[1]).toEqual({ id: "m1", role: "user", text: "1" });
});
