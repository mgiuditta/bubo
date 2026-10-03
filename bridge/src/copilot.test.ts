import { expect, test } from "bun:test";
import { existsSync, mkdtempSync, readFileSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { CopilotTurns, copilotEnvironment, decision, permissionRequest, reasoningEffortOf, type CopilotEvent } from "./copilot";
import { deniedByUser } from "./permission";

// Il `copilot` finto: JSON-RPC del Copilot SDK su stdio, nessun turno pagato.
const fake = join(import.meta.dir, "fakeCopilot.mjs");

function harness(environment: Record<string, string> = copilotEnvironment(process.env)) {
  const events: CopilotEvent[] = [];
  const waiting: Array<{ match: (event: CopilotEvent) => boolean; resolve: (event: CopilotEvent) => void }> = [];
  const turns = new CopilotTurns((event) => {
    events.push(event);
    for (const wait of waiting.splice(0)) {
      if (wait.match(event)) wait.resolve(event);
      else waiting.push(wait);
    }
  }, environment);
  const next = (match: (event: CopilotEvent) => boolean) => new Promise<CopilotEvent>((resolve) => {
    const seen = events.find(match);
    if (seen) resolve(seen);
    else waiting.push({ match, resolve });
  });
  return { turns, events, next };
}

const folder = () => realpathSync(mkdtempSync(join(tmpdir(), "bubo-copilot-")));
const texts = (events: CopilotEvent[]) => events.flatMap((event) => (event.type === "text" ? [event.text] : [])).join("");

test("il testo arriva in streaming e il turno finisce con done", async () => {
  const { turns, events } = harness();
  await turns.run({ id: "a", prompt: "ciao", cwd: folder(), copilot: fake });
  expect(texts(events)).toBe("Ciao mondo");
  expect(events.at(-1)).toEqual({ type: "done", id: "a" });
  expect(events[0]).toEqual({ type: "state", id: "a", state: "running" });
  expect(turns.has("a")).toBe(false);
});

test("cartella, modello e sforzo arrivano a copilot; i token di gh no", async () => {
  const cwd = folder();
  const { turns, events } = harness(copilotEnvironment({ ...process.env, GH_TOKEN: "x", GITHUB_TOKEN: "y", COPILOT_GITHUB_TOKEN: "z" }));
  await turns.run({ id: "b", prompt: "ambiente", cwd, copilot: fake, model: "gpt-6", effort: "high" });
  const seen = JSON.parse(texts(events));
  expect(seen).toMatchObject({ cwd, model: "gpt-6", effort: "high", tokens: [] });
  expect(seen.args).toContain("--stdio");
  expect(seen.args).not.toContain("--no-auto-login");
});

test("la Richiesta arriva a Bubo come quella di Claude; approvata, il file si scrive", async () => {
  const cwd = folder();
  const { turns, events, next } = harness();
  const run = turns.run({ id: "c", prompt: "scrivi", cwd, copilot: fake });
  const asked = await next((event) => event.type === "permission");
  expect(asked).toMatchObject({ type: "permission", id: "c", tool: "Edit", path: join(cwd, "nota.txt"), description: "Scrive la nota" });
  expect(turns.answer((asked as { request: string }).request, true)).toBe(true);
  await run;
  expect(readFileSync(join(cwd, "nota.txt"), "utf8")).toBe("ciao\n");
  expect(events.at(-1)).toEqual({ type: "done", id: "c" });
});

test("negata, il file non si scrive e copilot legge il perché", async () => {
  const cwd = folder();
  const { turns, events, next } = harness();
  const run = turns.run({ id: "d", prompt: "scrivi", cwd, copilot: fake });
  const asked = await next((event) => event.type === "permission");
  turns.answer((asked as { request: string }).request, false);
  await run;
  expect(existsSync(join(cwd, "nota.txt"))).toBe(false);
  expect(texts(events)).toBe(`Rifiutato: ${deniedByUser}`);
});

test("Ferma interrompe entro 2 s, senza done", async () => {
  const { turns, events, next } = harness();
  const run = turns.run({ id: "e", prompt: "lungo", cwd: folder(), copilot: fake });
  await next((event) => event.type === "text");
  const started = performance.now();
  expect(turns.cancel("e")).toBe(true);
  await run;
  expect(performance.now() - started).toBeLessThan(2_000);
  expect(events.some((event) => event.type === "done" || event.type === "error")).toBe(false);
  expect(turns.has("e")).toBe(false);
});

test("Ferma con una Richiesta aperta la ritira e la nega", async () => {
  const cwd = folder();
  const { turns, events, next } = harness();
  const run = turns.run({ id: "f", prompt: "scrivi", cwd, copilot: fake });
  const asked = await next((event) => event.type === "permission") as { request: string };
  turns.cancel("f");
  await run;
  expect(events).toContainEqual({ type: "permissionWithdrawn", id: "f", request: asked.request });
  expect(turns.answer(asked.request, true)).toBe(false);
  expect(existsSync(join(cwd, "nota.txt"))).toBe(false);
});

test("un errore di copilot chiude il turno con error", async () => {
  const { turns, events } = harness();
  await turns.run({ id: "g", prompt: "errore", cwd: folder(), copilot: fake });
  expect(events.at(-1)).toEqual({ type: "error", id: "g", message: "Crediti finiti" });
});

test("un copilot che non c'è è un errore del turno", async () => {
  const { turns, events } = harness();
  await turns.run({ id: "h", prompt: "ciao", cwd: folder(), copilot: "/nessuno/copilot" });
  expect(events.at(-1)?.type).toBe("error");
});

test("i tipi di Richiesta prendono il nome dello strumento di Claude", () => {
  expect(permissionRequest("r", { kind: "shell", fullCommandText: "rm -rf x", intention: "Pulisce", commands: [], canOfferSessionApproval: true, hasWriteFileRedirection: false, possiblePaths: [], possibleUrls: [] }))
    .toEqual({ type: "permission", request: "r", tool: "Bash", command: "rm -rf x", description: "Pulisce" });
  expect(permissionRequest("r", { kind: "url", url: "https://x.it", intention: "Legge" })).toMatchObject({ tool: "WebFetch", url: "https://x.it" });
  expect(permissionRequest("r", { kind: "read", path: "/a", intention: "Legge" })).toMatchObject({ tool: "Read", path: "/a" });
});

test("solo l'approvazione esplicita approva; sforzi validi soltanto", () => {
  expect(decision(true)).toEqual({ kind: "approve-once", approvedInteractively: true });
  expect(decision(false)).toEqual({ kind: "reject", feedback: deniedByUser });
  expect(reasoningEffortOf("high")).toBe("high");
  expect(reasoningEffortOf("ultra")).toBeUndefined();
});
