// Smoke notturno del ponte contro un `claude` vero (spec 27, #226). Uso, da bridge/:
//   BUBO_CLAUDE_PATH=… ANTHROPIC_API_KEY=… bun smoke/smoke.ts
// SMOKE_MINIMUM sostituisce la minima di compat.json (per provare il fallimento con una minima finta).
// Passi: versione ≥ minima → init con versione e capabilities → turno con Haiku che usa Read →
// interruzione e ripresa della stessa conversazione → una Domanda attraverso il ponte compilato dai sorgenti.
import { query, type Options, type SDKMessage } from "@anthropic-ai/claude-agent-sdk";
import { spawn, spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { checkMinimum, minimumClaudeVersion } from "./version";

const claudePath = process.env.BUBO_CLAUDE_PATH;
if (!claudePath) fail("BUBO_CLAUDE_PATH mancante");
const model = process.env.SMOKE_MODEL ?? "haiku";
const turnTimeout = 120_000;

function fail(message: string): never {
  console.error(`smoke: ${message}`);
  process.exit(1);
}

function step(name: string) {
  console.log(`smoke: ${name}`);
}

async function withTimeout<T>(promise: Promise<T>, what: string): Promise<T> {
  let timer: Timer | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${what}: oltre ${turnTimeout / 1000} s`)), turnTimeout);
  });
  try {
    return await Promise.race([promise, timeout]);
  } finally {
    clearTimeout(timer);
  }
}

// Repository finto: un file con un segreto che il modello può conoscere solo leggendolo.
function fakeRepository() {
  const directory = mkdtempSync(join(tmpdir(), "bubo-smoke-"));
  const token = `bubo-${crypto.randomUUID().slice(0, 8)}`;
  writeFileSync(join(directory, "nota.txt"), `${token}\n`);
  for (const args of [["init", "--quiet"], ["add", "."], ["-c", "user.name=smoke", "-c", "user.email=smoke@example.com", "commit", "--quiet", "-m", "nota"]]) {
    const git = spawnSync("git", args, { cwd: directory });
    if (git.status !== 0) fail(`git ${args[0]}: ${git.stderr}`);
  }
  return { directory, token };
}

const baseOptions = (cwd: string): Options => ({
  cwd,
  model,
  pathToClaudeCodeExecutable: claudePath,
  // Come il ponte: niente hook, env o MCP del repo (#266).
  settingSources: ["user"],
  allowedTools: ["Read"],
  maxTurns: 4,
});

async function collect(messages: AsyncIterable<SDKMessage>) {
  const seen: SDKMessage[] = [];
  for await (const message of messages) seen.push(message);
  return seen;
}

// 1. Versione
const version = spawnSync(claudePath, ["--version"], { encoding: "utf8" });
if (version.status !== 0) fail(`claude --version: ${version.stderr}`);
const installed = version.stdout.trim();
const minimum = process.env.SMOKE_MINIMUM || minimumClaudeVersion();
try {
  checkMinimum(installed, minimum);
} catch (error) {
  fail((error as Error).message);
}
step(`claude ${installed}, minima ${minimum}`);

// 2–3. Init e turno con uno strumento
const { directory, token } = fakeRepository();
const first = await withTimeout(collect(query({
  prompt: "Leggi il file nota.txt con lo strumento Read e rispondi solo con il suo contenuto, senza altro testo.",
  options: baseOptions(directory),
})), "turno con Read");

const init = first.find((m) => m.type === "system" && m.subtype === "init");
if (!init || init.type !== "system" || init.subtype !== "init") fail("nessun messaggio system/init");
if (!installed.startsWith(init.claude_code_version)) fail(`init riporta ${init.claude_code_version}, --version ${installed}`);
const capabilities = init.capabilities ?? [];
step(`init: ${init.claude_code_version}, capabilities [${capabilities.join(", ")}]`);

const usedRead = first.some((m) => m.type === "assistant"
  && m.message.content.some((block) => block.type === "tool_use" && block.name === "Read"));
if (!usedRead) fail("il modello non ha usato Read");
const result = first.find((m) => m.type === "result");
if (!result || result.type !== "result" || result.subtype !== "success" || result.is_error) fail(`turno fallito: ${JSON.stringify(result)}`);
if (!result.result.includes(token)) fail(`risposta senza il contenuto del file: ${result.result}`);
step("turno con Read: ok");

// 4. Interruzione e ripresa
const long = query({
  prompt: "Conta da 1 a 300, un numero per riga, senza usare strumenti.",
  options: { ...baseOptions(directory), includePartialMessages: true },
});
let sessionId: string | undefined;
let interrupted = false;
await withTimeout((async () => {
  try {
    for await (const message of long) {
      if (message.type === "system" && message.subtype === "init") sessionId = message.session_id;
      if (message.type === "stream_event" && !interrupted) {
        interrupted = true;
        await long.interrupt();
      }
    }
  } catch (error) {
    // Dopo l'interruzione l'SDK chiude il turno con un risultato di errore: è l'esito atteso.
    if (!interrupted) throw error;
  }
})(), "interruzione");
if (!interrupted || !sessionId) fail("interruzione non avvenuta");
step("interruzione: ok");

const resumed = await withTimeout(collect(query({
  prompt: "Rispondi solo con la parola ripreso.",
  options: { ...baseOptions(directory), resume: sessionId },
})), "ripresa");
const resumedResult = resumed.find((m) => m.type === "result");
if (!resumedResult || resumedResult.type !== "result" || resumedResult.subtype !== "success" || resumedResult.is_error)
  fail(`ripresa fallita: ${JSON.stringify(resumedResult)}`);
if (!resumed.some((m) => m.type === "system" && m.subtype === "init" && m.session_id === sessionId))
  fail("la ripresa ha aperto un'altra conversazione");
step("ripresa: ok");

// 5. Una Domanda attraverso il ponte, con il suo protocollo su stdio
await withTimeout(new Promise<void>((resolve, reject) => {
  const bridge = spawn(process.execPath, [join(import.meta.dir, "..", "src", "main.ts")], {
    env: { ...process.env, BUBO_CLAUDE_PATH: claudePath, ANTHROPIC_MODEL: model },
    stdio: ["pipe", "pipe", "inherit"],
  });
  let text = "";
  createInterface({ input: bridge.stdout }).on("line", (line) => {
    const event = JSON.parse(line);
    if (event.type === "ready") {
      // La versione del protocollo la dice il ponte stesso, in ogni evento.
      bridge.stdin.write(JSON.stringify({ v: event.v, type: "ask", id: "smoke", prompt: "Rispondi solo con la parola pronto.", cwd: directory }) + "\n");
    } else if (event.type === "text") {
      text += event.text;
    } else if (event.type === "done") {
      bridge.stdin.end();
      text.trim() ? resolve() : reject(new Error("ponte: done senza testo"));
    } else if (event.type === "error" && (event.id === "smoke" || event.id === undefined && /versione/.test(event.message))) {
      bridge.kill();
      reject(new Error(`ponte: ${event.message}`));
    }
  });
  bridge.on("exit", (code) => { if (code) reject(new Error(`ponte uscito con ${code}`)); });
}), "Domanda nel ponte").catch((error) => fail((error as Error).message));
step("ponte: ok");
console.log("smoke: ok");
