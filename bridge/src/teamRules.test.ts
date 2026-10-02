import { expect, test } from "bun:test";
import { teamRuleOptions, teamRules } from "./teamRules";

test("le regole di squadra passano come regole di sessione", () => {
  const rules = teamRules({ allow: ["Bash(npm test)"], deny: ["Bash(rm *)"], ask: ["Bash(git push *)"] });
  expect(teamRuleOptions(rules, ["mcp__bubo__cerca"])).toEqual({
    allowedTools: ["mcp__bubo__cerca", "Bash(npm test)"],
    disallowedTools: ["Bash(rm *)"],
    settings: { permissions: { ask: ["Bash(git push *)"] } },
  });
});

test("senza regole di squadra, solo gli strumenti di Bubo", () => {
  expect(teamRuleOptions(teamRules(undefined), ["mcp__bubo__cerca"])).toEqual({ allowedTools: ["mcp__bubo__cerca"] });
});

test("un elenco non valido non porta regole", () => {
  for (const requested of [null, "Bash", [], { allow: "Bash", deny: [1], ask: { a: 1 } }]) {
    expect(teamRules(requested)).toEqual({ allow: [], deny: [], ask: [] });
  }
});
