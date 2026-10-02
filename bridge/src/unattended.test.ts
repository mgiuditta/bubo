import type { PermissionRequestHookInput, PreToolUseHookInput, SDKPermissionDeniedMessage } from "@anthropic-ai/claude-agent-sdk";
import { expect, test } from "bun:test";
import { teamRuleOptions, teamRules } from "./teamRules";
import { Denials, MainAgent, suggestedRules, unattendedOf, unattendedOptions, wrongAgent } from "./unattended";

// Criterio 1: 0 Esecuzioni in attesa di una Richiesta di permesso oltre la fine del turno.
test("senza nessuno davanti la query ha permissionPrompts none e nessun canUseTool", () => {
  const options = unattendedOptions({ allowedTools: [] }, { rules: [] });
  expect(options.permissionPrompts).toBe("none");
  expect(options.canUseTool).toBeUndefined();
  expect("canUseTool" in options).toBe(true);
});

// Criterio 2 e 4: le Regole dell'Automazione sono regole di sessione di questo turno, mai nei settings.
test("le Regole dell'Automazione finiscono in allowedTools, dopo quelle di Bubo e di squadra", () => {
  const base = teamRuleOptions(teamRules({ allow: ["Bash(make)"] }), ["mcp__bubo__cerca"]);
  expect(unattendedOptions(base, { rules: ["Bash(npm test)"] }).allowedTools)
    .toEqual(["mcp__bubo__cerca", "Bash(make)", "Bash(npm test)"]);
});

test("solo regole ben formate arrivano dal comando; senza, nessun turno senza nessuno davanti", () => {
  expect(unattendedOf(undefined)).toBeUndefined();
  expect(unattendedOf("Bash")).toBeUndefined();
  expect(unattendedOf({})).toEqual({ rules: [] });
  expect(unattendedOf({ rules: ["Bash(npm test)", "WebFetch", 1, "", "Bash(a)\nBash(b)", "rm -rf", "Bash("] }))
    .toEqual({ rules: ["Bash(npm test)", "WebFetch"] });
});

test("i suggestions diventano regole Tool(contenuto) così come arrivano; setMode, removeRules e deny si scartano", () => {
  expect(suggestedRules([
    { type: "addRules", rules: [{ toolName: "Bash", ruleContent: "npm test" }, { toolName: "WebSearch" }], behavior: "allow", destination: "localSettings" },
    { type: "addRules", rules: [{ toolName: "Bash", ruleContent: "rm *" }], behavior: "deny", destination: "session" },
    { type: "removeRules", rules: [{ toolName: "Bash", ruleContent: "ls" }], behavior: "allow", destination: "session" },
    { type: "setMode", mode: "acceptEdits", destination: "session" },
    { type: "addDirectories", directories: ["/"], destination: "session" },
    { type: "addRules", rules: [{ toolName: "Bash", ruleContent: "echo (a)" }], behavior: "allow", destination: "session" },
  ])).toEqual(["Bash(npm test)", "WebSearch", "Bash(echo \\(a\\))"]);
  expect(suggestedRules(undefined)).toEqual([]);
});

const base = { session_id: "s", transcript_path: "/t", cwd: "/" };

test("i dinieghi delle quattro fonti si uniscono, uno per tool_use_id, con i suggestions della Richiesta", () => {
  const denials = new Denials();
  denials.gate({ ...base, hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: { command: "rm -rf ~" }, tool_use_id: "g1", agent_id: "a1",
                 agent_type: "revisore" } as PreToolUseHookInput);
  denials.requested({ ...base, hook_event_name: "PermissionRequest", tool_name: "Bash", tool_input: { description: "x", command: "npm test" },
                      permission_suggestions: [{ type: "addRules", rules: [{ toolName: "Bash", ruleContent: "npm test" }], behavior: "allow", destination: "session" }] } as PermissionRequestHookInput);
  denials.denied({ type: "system", subtype: "permission_denied", tool_name: "Bash", tool_use_id: "s1" } as SDKPermissionDeniedMessage);
  denials.denied({ type: "system", subtype: "permission_denied", tool_name: "Bash", tool_use_id: "g1" } as SDKPermissionDeniedMessage);
  denials.denied({ type: "system", subtype: "permission_denied", tool_name: "WebFetch", tool_use_id: "s2" } as SDKPermissionDeniedMessage);
  const found = denials.result([
    { tool_name: "Bash", tool_use_id: "s1", tool_input: { command: "npm test", description: "x" } },
    { tool_name: "Bash", tool_use_id: "g1", tool_input: { command: "rm -rf ~" } },
  ]);
  expect(found).toEqual([
    { toolUseID: "g1", tool: "Bash", command: "rm -rf ~", path: undefined, url: undefined, agent: "revisore", suggestions: [], source: "gate" },
    { toolUseID: "s1", tool: "Bash", command: "npm test", path: undefined, url: undefined, suggestions: ["Bash(npm test)"], source: "sdk" },
    { toolUseID: "s2", tool: "WebFetch", suggestions: [], source: "sdk" },
  ]);
});

// #174: l'Esecuzione gira come l'agente scelto, con `Options.agent`.
test("l'agente dell'Automazione arriva come Options.agent; un nome storto non arriva", () => {
  expect(unattendedOf({ rules: [], agent: "revisore" })).toEqual({ rules: [], agent: "revisore" });
  expect(unattendedOf({ rules: [], agent: "plugin:sub:revisore" })?.agent).toBe("plugin:sub:revisore");
  for (const agent of ["", "--model", "a b", "x\n", 3]) expect(unattendedOf({ agent })?.agent).toBeUndefined();
  expect(unattendedOptions({}, { rules: [], agent: "revisore" }).agent).toBe("revisore");
  expect("agent" in unattendedOptions({}, { rules: [] })).toBe(false);
});

test("il primo hook del filo principale verifica l'agente: un altro, o nessuno, ferma il turno", async () => {
  const hook = (extra: object) => ({ ...base, hook_event_name: "UserPromptSubmit", prompt: "x", ...extra }) as never;
  const right = new MainAgent("revisore");
  // Un subagent non conta: ha `agent_id`.
  expect(await right.hook(hook({ agent_id: "a1", agent_type: "altro" }))).toEqual({});
  expect(await right.hook(hook({ agent_type: "revisore" }))).toEqual({});
  expect(right.isWrong).toBe(false);
  const missing = new MainAgent("revisore");
  expect(await missing.hook(hook({}))).toEqual({ continue: false, stopReason: wrongAgent });
  expect(missing.isWrong).toBe(true);
  // Una volta deciso, resta: un hook più tardi non rimette in moto il turno.
  expect(await missing.hook(hook({ agent_type: "revisore" }))).toEqual({ continue: false, stopReason: wrongAgent });
});

test("i dinieghi del filo principale non hanno agente; quelli di un subagent sì, anche da permission_denied", () => {
  const denials = new Denials();
  denials.gate({ ...base, hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: { command: "rm -rf ~" }, tool_use_id: "g1",
                 agent_type: "revisore" } as PreToolUseHookInput);
  denials.denied({ type: "system", subtype: "permission_denied", tool_name: "Bash", tool_use_id: "s1", agent_id: "a1" } as SDKPermissionDeniedMessage,
                 "esploratore");
  const found = denials.result([{ tool_name: "Bash", tool_use_id: "s1", tool_input: { command: "npm test" } }]);
  expect(found.find((denial) => denial.toolUseID === "g1")?.agent).toBeUndefined();
  expect(found.find((denial) => denial.toolUseID === "s1")?.agent).toBe("esploratore");
});
