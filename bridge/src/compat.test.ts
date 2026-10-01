import { expect, test } from "bun:test";
import type { SDKMessage } from "@anthropic-ai/claude-agent-sdk";
import { claudeInfo, isBelowMinimum, isTooOldForAnthropic, minimumClaudeVersion } from "./compat";

test("la minima viene da compat.json", () => {
  expect(minimumClaudeVersion).toBe("2.1.275");
});

test("sotto, uguale, sopra la minima e formati strani", () => {
  const cases: [string, boolean][] = [
    ["2.1.274", true], ["2.0.999", true], ["1.9.300", true], ["2.1.275-beta.1", true], ["2.1", true],
    ["2.1.275", false], ["2.1.275 (Claude Code)", false], ["v2.1.275", false],
    ["2.1.276", false], ["2.2.0", false], ["3.0", false], ["10.0.0", false], ["2.1.286.1", false],
    ["", false], ["abc", false], ["Claude Code", false],
  ];
  for (const [version, below] of cases) expect([version, isBelowMinimum(version, "2.1.275")]).toEqual([version, below]);
});

test("versione e capabilities dall'init, assenti = vuote, solo stringhe", () => {
  const init = (extra: object) => ({ type: "system", subtype: "init", claude_code_version: "2.1.286", ...extra }) as unknown as SDKMessage;
  expect(claudeInfo(init({ capabilities: ["interrupt_receipt_v1", "nuova_v9", 3] })))
    .toEqual({ version: "2.1.286", capabilities: ["interrupt_receipt_v1", "nuova_v9"] });
  expect(claudeInfo(init({}))).toEqual({ version: "2.1.286", capabilities: [] });
  expect(claudeInfo({ type: "system", subtype: "status" } as unknown as SDKMessage)).toBeUndefined();
});

test("il rifiuto di Anthropic per una CLI troppo vecchia", () => {
  const result = (reason?: string) => ({ type: "result", subtype: "error_during_execution", startup_failure_reason: reason }) as unknown as SDKMessage;
  expect(isTooOldForAnthropic(result("cli_version_too_old"))).toBe(true);
  expect(isTooOldForAnthropic(result("cwd_unavailable"))).toBe(false);
  expect(isTooOldForAnthropic(result())).toBe(false);
});
