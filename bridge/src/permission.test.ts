import { expect, test } from "bun:test";
import { clean, deniedByUser, isAllowed, needsItsOwnCard, permissionRequest, permissionResult, isTooLong, subjectLength } from "./permission";

const options = (extra: object = {}) =>
  ({ signal: new AbortController().signal, toolUseID: "toolu_1", requestId: "r1", ...extra }) as Parameters<typeof permissionRequest>[3];

test("solo la stringa esatta allow approva", () => {
  expect(isAllowed("allow")).toBe(true);
  for (const answer of ["Allow", "allow ", true, 1, { behavior: "allow" }, ["allow"], null, undefined, "deny", ""]) {
    expect(isAllowed(answer)).toBe(false);
  }
});

test("approvato, gira l'input mostrato; negato, Claude legge il perché", () => {
  const input = { command: "npm test" };
  expect(permissionResult(true, input)).toEqual({ behavior: "allow", updatedInput: input, decisionClassification: "user_temporary" });
  expect(permissionResult(false, input)).toEqual({ behavior: "deny", message: deniedByUser, decisionClassification: "user_reject" });
});

test("la Richiesta porta comando, percorso e testo ripulito", () => {
  const request = permissionRequest("p1", "Bash", { command: "rm -rf build", description: "x" }, options({
    title: "Claude wants to run \x1b[31mrm\x1b[0m", agentID: "a1", suppressAlwaysAllowRule: true,
    mcpServer: { name: "evil\x07", source: "project" }, blockedPath: "/etc",
  }));
  expect(request).toEqual({
    type: "permission", request: "p1", tool: "Bash", command: "rm -rf build", path: undefined, url: undefined,
    title: "Claude wants to run rm", description: undefined, blockedPath: "/etc", mcpSource: "project",
    fromSubagent: true, defaultToNo: undefined, suppressAlwaysAllowRule: true,
  });
  expect(permissionRequest("p2", "Edit", { file_path: "/p/a.swift" }, options()).path).toBe("/p/a.swift");
  expect(permissionRequest("p3", "WebFetch", { url: "https://x.dev" }, options()).url).toBe("https://x.dev");
  expect(permissionRequest("p4", "Bash", { command: 42 }, options()).command).toBeUndefined();
});

test("il testo lungo si tronca", () => {
  expect(clean("x".repeat(5000))?.length).toBe(4000);
});

test("le domande all'utente non diventano una Richiesta", () => {
  expect(needsItsOwnCard("AskUserQuestion", options())).toBe(true);
  expect(needsItsOwnCard("mcp__x__y", options({ requiresUserInteraction: true }))).toBe(true);
  expect(needsItsOwnCard("Bash", options())).toBe(false);
});

test("comando, percorso e URL arrivano interi; troppo lunghi si negano", () => {
  const options = { signal: new AbortController().signal, toolUseID: "t" } as unknown as Parameters<typeof permissionRequest>[3];
  const long = "x".repeat(5000);
  expect(permissionRequest("r", "Bash", { command: long }, options).command).toBe(long);
  expect(permissionRequest("r", "Bash", { command: "a\rb‮c" }, options).command).toBe("a\rb‮c");
  expect(isTooLong(permissionRequest("r", "Bash", { command: "x".repeat(subjectLength + 1) }, options))).toBe(true);
  expect(isTooLong(permissionRequest("r", "Bash", { command: long }, options))).toBe(false);
});
