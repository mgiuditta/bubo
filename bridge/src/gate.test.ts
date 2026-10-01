import type { HookInput, McpServerStatus, SandboxSettings } from "@anthropic-ai/claude-agent-sdk";
import { expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, readdirSync, realpathSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { blockedWrite, isLocal, outsideSandbox, realPath, sandboxGate, verdict, type Gate, type RiskQuestion } from "./gate";

// Un worktree finto con una cartella fuori, un symlink che esce, uno che punta nel vuoto e una cache ammessa.
function folders() {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "bubo-gate-")));
  const worktree = join(root, "worktree");
  const outside = join(root, "fuori");
  const cache = join(root, "cache");
  for (const folder of [worktree, outside, cache]) mkdirSync(folder);
  symlinkSync(outside, join(worktree, "uscita"));
  symlinkSync(join(outside, "nuovo.txt"), join(worktree, "vuoto.txt"));
  symlinkSync("../fuori", join(worktree, "relativa"));
  return { root, worktree, outside, cache };
}

const sandbox = (cache: string): SandboxSettings => ({ enabled: true, filesystem: { allowWrite: [cache] } });

function gate(cwd: string, overrides: Partial<Gate> = {}): Gate {
  return { cwd, sandbox: sandbox(join(cwd, "..", "cache")), isDangerous: async () => false, isLocalServer: async () => true, ...overrides };
}

function call(tool: string, input: Record<string, unknown>, mode = "auto", mcpServer?: { name: string; source: string }): HookInput {
  return {
    hook_event_name: "PreToolUse", session_id: "s", transcript_path: "/t", cwd: "/", permission_mode: mode,
    tool_name: tool, tool_input: input, tool_use_id: "u", mcp_server: mcpServer,
  } as HookInput;
}

test("il percorso reale segue i symlink, anche verso file che non esistono ancora", () => {
  const { root, worktree, outside } = folders();
  expect(realPath("uscita/a.txt", worktree)).toBe(join(outside, "a.txt"));
  expect(realPath(join(worktree, "vuoto.txt"), worktree)).toBe(join(outside, "nuovo.txt"));
  expect(realPath("relativa/x/../y.txt", worktree)).toBe(join(outside, "y.txt"));
  expect(realPath("nuova/cartella/f.txt", worktree)).toBe(join(worktree, "nuova/cartella/f.txt"));
  // `..` dopo un symlink sale dalla destinazione, come sul disco, non dal nome scritto.
  expect(realPath("uscita/../worktree/f.txt", worktree)).toBe(join(root, "worktree", "f.txt"));
});

test("un symlink in ciclo non ha un percorso reale", () => {
  const { worktree } = folders();
  symlinkSync(join(worktree, "giro2"), join(worktree, "giro1"));
  symlinkSync(join(worktree, "giro1"), join(worktree, "giro2"));
  expect(realPath("giro1", worktree)).toBeUndefined();
});

// Criterio di accettazione: in Modalità autonoma, Edit, Write e NotebookEdit fuori, symlink compresi → 0 file creati.
test("in Modalità autonoma, Edit, Write e NotebookEdit fuori dal worktree sono negati con la riga del blocco", async () => {
  const { worktree, outside } = folders();
  const tries: [string, Record<string, unknown>][] = [];
  for (const target of [join(outside, "a.txt"), "uscita/b.txt", join(worktree, "vuoto.txt"), "relativa/c.txt", "/tmp/altro/d.txt",
                        "../fuori/e.txt", join(tmpdir(), "..", "f.txt"), "uscita/../fuori/g.txt"]) {
    tries.push(["Write", { file_path: target, content: "x" }], ["Edit", { file_path: target, old_string: "a", new_string: "b" }],
               ["NotebookEdit", { notebook_path: target, new_source: "x" }]);
  }
  for (const [tool, input] of tries) {
    const output = await sandboxGate(gate(worktree))(call(tool, input), "u", { signal: new AbortController().signal });
    const target = (input.file_path ?? input.notebook_path) as string;
    expect(output).toEqual({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: blockedWrite(target) } });
  }
  expect(readdirSync(outside)).toEqual([]);
});

test("dentro il worktree e nelle cartelle della Sandbox le scritture passano al flusso normale", async () => {
  const { worktree, cache } = folders();
  for (const target of ["src/nuovo.swift", join(worktree, "README.md"), join(cache, "pacchetto.tgz"), "./a/../b.txt"]) {
    expect(await verdict(call("Write", { file_path: target }), gate(worktree))).toBeUndefined();
  }
});

test("senza percorso, la scrittura è negata", async () => {
  const { worktree } = folders();
  expect((await verdict(call("Edit", {}), gate(worktree)))?.decision).toBe("deny");
});

test("a Sandbox spenta il cancello non tocca le scritture", async () => {
  const { worktree, outside } = folders();
  expect(await verdict(call("Write", { file_path: join(outside, "a") }, "default"), gate(worktree, { sandbox: undefined })))
    .toBeUndefined();
});

// Criterio di accettazione: 0 ritentativi fuori sandbox approvati senza Richiesta, in ogni modalità.
test("un Bash che chiede di uscire dalla sandbox chiede sempre", async () => {
  const { worktree } = folders();
  for (const mode of ["auto", "default", "acceptEdits", "bypassPermissions"]) {
    expect(await verdict(call("Bash", { command: "npm install", dangerouslyDisableSandbox: true }, mode), gate(worktree)))
      .toEqual({ decision: "ask", reason: outsideSandbox });
  }
  expect(await verdict(call("Bash", { command: "npm install", dangerouslyDisableSandbox: false }), gate(worktree))).toBeUndefined();
});

// Criterio di accettazione: strumento MCP stdio senza Regola → Richiesta, mai approvazione automatica.
test("in Modalità autonoma con la Sandbox, gli strumenti dei Server MCP locali chiedono", async () => {
  const { worktree } = folders();
  const local = gate(worktree, { isLocalServer: async (name) => name === "locale" });
  expect((await verdict(call("mcp__locale__scrivi", {}, "auto", { name: "locale", source: "project" }), local))?.decision).toBe("ask");
  expect((await verdict(call("mcp__ignoto__scrivi", {}, "auto"), gate(worktree)))?.decision).toBe("ask");
  expect(await verdict(call("mcp__remoto__leggi", {}, "auto", { name: "remoto", source: "user" }), local)).toBeUndefined();
  expect(await verdict(call("mcp__bubo__cerca", {}, "auto", { name: "bubo", source: "sdk" }), gate(worktree))).toBeUndefined();
  // Fuori dalla Modalità autonoma decidono già Regole e Richieste.
  expect(await verdict(call("mcp__locale__scrivi", {}, "default", { name: "locale", source: "project" }), local)).toBeUndefined();
});

test("un Server MCP è locale se è stdio o se la sua configurazione non si conosce", () => {
  const status = (config?: unknown) => ({ name: "s", status: "connected", config }) as McpServerStatus;
  expect(isLocal(undefined)).toBe(true);
  expect(isLocal(status())).toBe(true);
  expect(isLocal(status({ command: "node" }))).toBe(true);
  expect(isLocal(status({ type: "stdio", command: "node" }))).toBe(true);
  expect(isLocal(status({ type: "http", url: "https://x" }))).toBe(false);
  expect(isLocal(status({ type: "sse", url: "https://x" }))).toBe(false);
});

test("i livelli 4–5 chiedono con la Sandbox o in Modalità autonoma, con i campi della chiamata", async () => {
  const { worktree } = folders();
  const asked: RiskQuestion[] = [];
  const dangerous = { isDangerous: async (question: RiskQuestion) => { asked.push(question); return true; } };
  expect((await verdict(call("Bash", { command: "rm -rf build" }, "default"), gate(worktree, dangerous)))?.decision).toBe("ask");
  expect((await verdict(call("Read", { file_path: "/Users/u/.ssh/id_ed25519" }, "auto"), gate(worktree, { ...dangerous, sandbox: undefined })))?.decision)
    .toBe("ask");
  expect(asked).toEqual([{ tool: "Bash", command: "rm -rf build", path: undefined, url: undefined, mcpSource: undefined },
                         { tool: "Read", command: undefined, path: "/Users/u/.ssh/id_ed25519", url: undefined, mcpSource: undefined }]);
  // Sandbox spenta, modalità manuale: decide già la Richiesta, nessuna domanda a Bubo.
  expect(await verdict(call("Bash", { command: "rm -rf build" }, "default"), gate(worktree, { ...dangerous, sandbox: undefined }))).toBeUndefined();
  expect(asked.length).toBe(2);
  expect(await verdict(call("Bash", { command: "ls" }, "auto"), gate(worktree))).toBeUndefined();
});

test("un cancello che si rompe nega", async () => {
  const { worktree } = folders();
  const broken = gate(worktree, { isDangerous: async () => { throw new Error("rotto"); } });
  const output = await sandboxGate(broken)(call("Bash", { command: "ls" }), "u", { signal: new AbortController().signal });
  expect((output as { hookSpecificOutput: { permissionDecision: string } }).hookSpecificOutput.permissionDecision).toBe("deny");
});
