import { expect, test } from "bun:test";
import { allowedBuboTools, brainHomeInstruction, readOnlyOf, readOnlyOptions, systemPromptOf } from "./tools";

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
