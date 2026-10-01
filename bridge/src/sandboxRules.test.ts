import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import type { Query, SDKPermissionRuleEntry } from "@anthropic-ai/claude-agent-sdk";
import { sandboxRules, widensSandbox } from "./sandboxRules";

const entry = (rule: string, extra: Partial<SDKPermissionRuleEntry> = {}): SDKPermissionRuleEntry =>
  ({ behavior: "allow", source: "userSettings", rule, editability: "persistent", ...extra });

test("allargano la Sandbox solo le allow Edit, Write e WebFetch in vigore", () => {
  expect(widensSandbox(entry("Edit(~/altro/**)"))).toBe(true);
  expect(widensSandbox(entry("Write(/tmp/x)"))).toBe(true);
  expect(widensSandbox(entry("WebFetch(domain:github.com)"))).toBe(true);
  expect(widensSandbox(entry("Bash(npm test)"))).toBe(false);
  expect(widensSandbox(entry("WebFetch"))).toBe(false);
  expect(widensSandbox(entry("Edit(~/x)", { behavior: "deny" }))).toBe(false);
  expect(widensSandbox(entry("Edit(~/x)", { notInEffect: true }))).toBe(false);
});

test("le Regole arrivano con la loro fonte, ripulite", async () => {
  const conversation = {
    listPermissionRules: async () => ({
      state: { rules: [entry("Edit(~/a\x1b[31m/**)", { source: "projectSettings" }), entry("Read(**)")], workspaceDirectories: [], originalCwd: "/", managedOnly: false },
    }),
  } as unknown as Query;
  expect(await sandboxRules(conversation)).toEqual([{ rule: "Edit(~/a/**)", source: "projectSettings" }]);
});

test("senza il metodo, errore invece di un elenco vuoto", async () => {
  expect(sandboxRules({} as Query)).rejects.toThrow("listPermissionRules");
});

// `listPermissionRules` esiste a runtime ma non in `sdk.d.ts` 0.3.286: si rompe se l'SDK lo toglie.
test("l'SDK ha ancora listPermissionRules", () => {
  const sdk = readFileSync(require.resolve("@anthropic-ai/claude-agent-sdk")).toString();
  expect(sdk).toContain('async listPermissionRules(){return(await this.request({subtype:"list_permission_rules"})).response}');
});
