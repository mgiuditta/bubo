// Il formato JSONL dei transcript è interno alla CLI: il ponte legge le conversazioni solo con le funzioni dell'SDK.
import { expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

test("nessun file del ponte legge i transcript JSONL", () => {
  const sources = readdirSync(import.meta.dir).filter((name) => name.endsWith(".ts") && !name.endsWith(".test.ts"));
  expect(sources).toContain("history.ts");
  for (const name of sources) {
    const source = readFileSync(join(import.meta.dir, name), "utf8");
    expect({ name, readsFiles: /from "(node:)?fs(\/promises)?"|Bun\.file|readFile/.test(source) }).toEqual({ name, readsFiles: false });
    expect({ name, jsonl: /\.jsonl/.test(source) }).toEqual({ name, jsonl: false });
  }
});
