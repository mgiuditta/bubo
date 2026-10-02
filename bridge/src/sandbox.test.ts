import { query } from "@anthropic-ai/claude-agent-sdk";
import { expect, test } from "bun:test";
import { chmodSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { sandboxSettings, sandboxUnavailableReason } from "./sandbox";

const policy = {
  enabled: true,
  autoAllowBashIfSandboxed: false,
  network: { allowedDomains: ["registry.npmjs.org"], allowLocalBinding: true, strictAllowlist: true },
  filesystem: { allowWrite: ["/Users/u/.npm"] },
  credentials: { files: [{ path: "/Users/u/.ssh", mode: "deny" }], envVars: [{ name: "GH_TOKEN", mode: "deny" }] },
};

test("una Sandbox accesa passa intera, con failIfUnavailable sempre vero", () => {
  expect(sandboxSettings(policy)).toEqual({ ...policy, failIfUnavailable: true } as never);
  expect(sandboxSettings({ ...policy, failIfUnavailable: false })?.failIfUnavailable).toBe(true);
});

test("spenta o storta, nessuna Sandbox", () => {
  for (const requested of [undefined, null, true, "on", [], { enabled: false }, { enabled: "true" }, {}]) {
    expect(sandboxSettings(requested)).toBeUndefined();
  }
});

test("il motivo della Sandbox che non parte si legge dall'errore dell'SDK", () => {
  const error = new Error("Claude Code process exited with code 1. stderr: Error: sandbox required but unavailable: "
    + "sandbox-exec non trovato\n  sandbox.failIfUnavailable is set — refusing to start without a working sandbox.");
  expect(sandboxUnavailableReason(error)).toBe("sandbox-exec non trovato");
  expect(sandboxUnavailableReason(new Error("Claude Code process exited with code 1"))).toBeUndefined();
});

// Una CLI finta che si ferma come `claude` quando la sandbox non parte: scrive i suoi argomenti ed esce prima di tutto.
test("con la CLI simulata: --settings porta tutta la Sandbox, e la Sessione non parte col motivo", async () => {
  const folder = mkdtempSync(join(tmpdir(), "bubo-sandbox-"));
  const argumentsFile = join(folder, "argv");
  const cli = join(folder, "claude");
  writeFileSync(cli, `#!/bin/sh
printf '%s\\0' "$@" > '${argumentsFile}'
echo "Error: sandbox required but unavailable: profilo rifiutato" >&2
echo "  sandbox.failIfUnavailable is set — refusing to start without a working sandbox." >&2
exit 1
`);
  chmodSync(cli, 0o755);
  const conversation = query({
    prompt: "scrivi fuori",
    options: { cwd: folder, pathToClaudeCodeExecutable: cli, settingSources: [], persistSession: false,
               sandbox: sandboxSettings(policy) },
  });
  let messages = 0;
  let failure: unknown;
  try {
    for await (const _ of conversation) messages += 1;
  } catch (error) {
    failure = error;
  }
  expect(messages).toBe(0);
  expect(sandboxUnavailableReason(failure)).toBe("profilo rifiutato");
  const argv = readFileSync(argumentsFile, "utf8").split("\0");
  const settings = JSON.parse(argv[argv.indexOf("--settings") + 1]);
  // `Options.sandbox` sostituisce `settings.sandbox` per intero: credenziali e strictAllowlist devono esserci.
  expect(settings.sandbox).toEqual({ ...policy, failIfUnavailable: true });
});
