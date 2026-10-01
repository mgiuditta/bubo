// Il formato JSONL dei transcript è interno alla CLI: il ponte legge le conversazioni solo con le funzioni dell'SDK.
import { expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

// I soli file del ponte che toccano il disco, e mai i transcript.
const diskReaders = new Set([
  "gate.ts",   // il cancello della Sandbox risolve i symlink dei percorsi (`lstat`, `readlink`, `realpath`)
  "memory.ts", // le righe Ricordato leggono il file della Memoria di Progetto prima e dopo la scrittura
]);

test("nessun file del ponte legge i transcript JSONL", () => {
  const sources = readdirSync(import.meta.dir).filter((name) => name.endsWith(".ts") && !name.endsWith(".test.ts"));
  expect(sources).toContain("history.ts");
  for (const name of sources) {
    const source = readFileSync(join(import.meta.dir, name), "utf8");
    const readsFiles = /from "(node:)?fs(\/promises)?"|Bun\.file|\breadFile(Sync)?\b/.test(source);
    expect({ name, readsFiles }).toEqual({ name, readsFiles: diskReaders.has(name) });
    expect({ name, jsonl: /\.jsonl/.test(source) }).toEqual({ name, jsonl: false });
  }
});
