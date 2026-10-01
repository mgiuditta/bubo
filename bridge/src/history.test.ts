import { expect, test } from "bun:test";
import type { SessionMessage } from "@anthropic-ai/claude-agent-sdk";
import { conversation, messages, transcriptLimit } from "./history";

function entry(type: SessionMessage["type"], content: unknown, toolUse: string | null = null): SessionMessage {
  return { type, uuid: "u", session_id: "s", message: { role: type, content }, parent_tool_use_id: toolUse, parent_agent_id: null };
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
  ])).toEqual([{ role: "user", text: "Ciao" }, { role: "assistant", text: "Eccomi" }]);
});

test("di una conversazione lunga, solo gli ultimi messaggi", () => {
  const long = Array.from({ length: transcriptLimit + 5 }, (_, index) => entry("user", `${index}`));
  const read = messages(long);
  expect(read.length).toBe(transcriptLimit);
  expect(read[0].text).toBe("5");
});
