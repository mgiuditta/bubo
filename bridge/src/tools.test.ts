import { expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, realpathSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { allowedBuboTools, brainHomeInstruction, hiddenPathDenial, readOnlyOf, readOnlyOptions, systemPromptOf } from "./tools";

test("ricorda solo quando Bubo lo chiede: Domande e Sessioni, non le Esecuzioni", () => {
  expect(allowedBuboTools(true)).toEqual(["mcp__bubo__cerca", "mcp__bubo__ricorda"]);
  expect(allowedBuboTools(false)).toEqual(["mcp__bubo__cerca"]);
});

test("Profilo e Regole vanno nel prompt di sistema dopo l'Orb, e senza nulla resta quello dell'SDK", () => {
  expect(systemPromptOf("orb", "## Bubo/Profilo.md")).toBe("orb\n\n## Bubo/Profilo.md");
  expect(systemPromptOf(undefined, "## Bubo/Regole.md")).toBe("## Bubo/Regole.md");
  expect(systemPromptOf("orb", undefined)).toBe("orb");
  expect(systemPromptOf(undefined, "")).toBeUndefined();
});

test("una Domanda legge e cerca i file, ma non scrive, non esegue e non delega", () => {
  const options = readOnlyOptions({ inBrain: true, hidden: [] });
  expect(options.tools).toEqual(["Read", "Grep", "Glob", "WebSearch"]);
  for (const tool of ["Edit", "MultiEdit", "Write", "NotebookEdit", "Bash", "Task"]) {
    expect(options.tools).not.toContain(tool);
    expect(options.disallowedTools).toContain(tool);
  }
});

test("le cartelle escluse del Secondo cervello diventano regole Read negate, dopo quelle della squadra", () => {
  const options = readOnlyOptions({ inBrain: true, hidden: ["/Users/u/Note/Privato/"] }, ["Read(./.env)"]);
  expect(options.disallowedTools[0]).toBe("Read(./.env)");
  expect(options.disallowedTools.at(-1)).toBe("Read(//Users/u/Note/Privato/**)");
});

test("readOnly dal comando: solo percorsi assoluti, e senza oggetto nessuna restrizione", () => {
  expect(readOnlyOf({ brain: true, hidden: ["/a", "b", 3] })).toEqual({ inBrain: true, hidden: ["/a"] });
  expect(readOnlyOf({})).toEqual({ inBrain: false, hidden: [] });
  expect(readOnlyOf(undefined)).toBeUndefined();
});

test("nel Secondo cervello l'istruzione della Domanda viene prima di Profilo e Regole", () => {
  expect(systemPromptOf("orb", brainHomeInstruction, "## Bubo/Profilo.md"))
    .toBe(`orb\n\n${brainHomeInstruction}\n\n## Bubo/Profilo.md`);
});

test("una Domanda non legge le cartelle escluse, nemmeno da un symlink o da una ricerca che le attraversa", () => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "brain-")));
  mkdirSync(join(root, "Archivio [vecchio]"));
  mkdirSync(join(root, "Progetti"));
  symlinkSync(join(root, "Archivio [vecchio]"), join(root, "Progetti", "link"));
  const hidden = [join(root, "Archivio [vecchio]")];
  expect(hiddenPathDenial("Read", { file_path: "Archivio [vecchio]/a.md" }, root, hidden)).toBeDefined();
  expect(hiddenPathDenial("Read", { file_path: join(root, "Progetti", "link", "a.md") }, root, hidden)).toBeDefined();
  expect(hiddenPathDenial("Grep", {}, root, hidden)).toBeDefined();
  mkdirSync(join(root, "Archivio [vecchio]", "dentro"), { recursive: true });
  expect(hiddenPathDenial("Grep", { path: "archivio [VECCHIO]/dentro" }, root, hidden)).toBeDefined();
  expect(hiddenPathDenial("Grep", { path: "Progetti" }, root, hidden)).toBeUndefined();
  expect(hiddenPathDenial("Glob", { path: "Progetti", pattern: "../Archivio*/**" }, root, hidden)).toBeDefined();
  expect(hiddenPathDenial("Glob", { path: "Progetti", pattern: `${root}/Archivio*/**` }, root, hidden)).toBeDefined();
  expect(hiddenPathDenial("Grep", { path: "Progetti", glob: "~/**" }, root, hidden)).toBeDefined();
  expect(hiddenPathDenial("Glob", { path: "Progetti", pattern: "**/*.md" }, root, hidden)).toBeUndefined();
  expect(hiddenPathDenial("Read", { file_path: "Progetti/b.md" }, root, hidden)).toBeUndefined();
  expect(hiddenPathDenial("Read", { file_path: "Archivio [vecchio]/a.md" }, root, [])).toBeUndefined();
});
