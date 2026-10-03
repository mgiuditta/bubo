import { expect, test } from "bun:test";
import { allowedBuboTools, systemPromptOf } from "./tools";

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
