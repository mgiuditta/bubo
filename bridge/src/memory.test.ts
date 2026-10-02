import { expect, test } from "bun:test";
import type { SDKMessage } from "@anthropic-ai/claude-agent-sdk";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { memoryFile, MemoryWrites, recalled, withAutoMemory } from "./memory";

test("in una Sessione la memoria automatica resta accesa", () => {
  expect(withAutoMemory({ HOME: "/Users/u" }, true)).toEqual({ HOME: "/Users/u" });
});

test("in una Domanda la memoria automatica si spegne", () => {
  expect(withAutoMemory({ HOME: "/Users/u" }, false)).toEqual({ HOME: "/Users/u", CLAUDE_CODE_DISABLE_AUTO_MEMORY: "1" });
});

test("una variabile ereditata non spegne la memoria di una Sessione", () => {
  expect(withAutoMemory({ CLAUDE_CODE_DISABLE_AUTO_MEMORY: "1" }, true)).toEqual({});
});

test("solo i file nella cartella memory di un progetto sono di memoria", () => {
  const config = "/Users/u/.claude";
  expect(memoryFile({ file_path: "/Users/u/.claude/projects/-Users-u-repo/memory/MEMORY.md" }, config))
    .toBe("/Users/u/.claude/projects/-Users-u-repo/memory/MEMORY.md");
  expect(memoryFile({ file_path: "/Users/u/.claude/projects/-Users-u-repo/memory/sub/a.md" }, config)).toBeUndefined();
  expect(memoryFile({ file_path: "/Users/u/.claude/projects/-Users-u-repo/a.jsonl" }, config)).toBeUndefined();
  expect(memoryFile({ file_path: "/Users/u/.claude/projects/x/memory/../../../settings.json" }, config)).toBeUndefined();
  expect(memoryFile({ file_path: "/Users/u/repo/memory/a.md" }, config)).toBeUndefined();
  expect(memoryFile({ file_path: "memory/a.md" }, config)).toBeUndefined();
  expect(memoryFile({}, config)).toBeUndefined();
});

function memoryFolder() {
  const config = mkdtempSync(join(tmpdir(), "bubo-memory-"));
  const folder = join(config, "projects", "-repo", "memory");
  mkdirSync(folder, { recursive: true });
  return { config, folder };
}

test("una scrittura in memoria porta il file prima e dopo", () => {
  const { config, folder } = memoryFolder();
  const file = join(folder, "MEMORY.md");
  writeFileSync(file, "- vecchio\n");
  const writes = new MemoryWrites(config);
  writes.start("t1", { file_path: file });
  writeFileSync(file, "- vecchio\n- nuovo\n");
  expect(writes.finish("t1")).toEqual({ type: "remembered", file, before: "- vecchio\n", after: "- vecchio\n- nuovo\n" });
  expect(writes.finish("t1")).toBeUndefined();
});

test("un file nuovo non ha un prima: Annulla lo toglie", () => {
  const { config, folder } = memoryFolder();
  const file = join(folder, "feedback_test.md");
  const writes = new MemoryWrites(config);
  writes.start("t1", { file_path: file });
  writeFileSync(file, "testo");
  expect(writes.finish("t1")).toEqual({ type: "remembered", file, after: "testo" });
});

test("un file troppo grande dà la riga senza Annulla", () => {
  const { config, folder } = memoryFolder();
  const file = join(folder, "grande.md");
  writeFileSync(file, "x".repeat(300 * 1024));
  const writes = new MemoryWrites(config);
  writes.start("t1", { file_path: file });
  writeFileSync(file, "piccolo");
  expect(writes.finish("t1")).toEqual({ type: "remembered", file });
});

test("una scrittura fallita o fuori dalla memoria non dà righe", () => {
  const { config, folder } = memoryFolder();
  const writes = new MemoryWrites(config);
  writes.start("t1", { file_path: join(folder, "a.md") });
  writes.forget("t1");
  expect(writes.finish("t1")).toBeUndefined();
  writes.start("t2", { file_path: join(config, "settings.json") });
  expect(writes.finish("t2")).toBeUndefined();
});

test("memory_recall diventa recalled, con il contenuto solo dove c'è", () => {
  const message = {
    type: "system", subtype: "memory_recall", mode: "select", uuid: "u", session_id: "s",
    memories: [{ path: "/m/a.md", scope: "personal" }, { path: "https://org/x", scope: "organization", content: "testo" }],
  } as unknown as SDKMessage;
  expect(recalled(message)).toEqual({
    type: "recalled", mode: "select",
    memories: [{ path: "/m/a.md", scope: "personal" }, { path: "https://org/x", scope: "organization", content: "testo" }],
  });
  expect(recalled({ type: "system", subtype: "init" } as unknown as SDKMessage)).toBeUndefined();
});
