import { expect, test } from "bun:test";
import { existsSync, mkdtempSync, readFileSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { CopilotTurns, copiedEntry, copiedMessages, copilotEnvironment, copilotProject, decision, permissionRequest, reasoningEffortOf, toolActivity, withFolderFirst, type CopilotEvent } from "./copilot";
import { deniedByUser } from "./permission";
import { ConversationStore } from "./store";

// Il `copilot` finto: JSON-RPC del Copilot SDK su stdio, nessun turno pagato.
const fake = join(import.meta.dir, "fakeCopilot.mjs");

function harness(environment: Record<string, string> = copilotEnvironment(process.env), copy?: ConversationStore) {
  const events: CopilotEvent[] = [];
  const waiting: Array<{ match: (event: CopilotEvent) => boolean; resolve: (event: CopilotEvent) => void }> = [];
  const turns = new CopilotTurns((event) => {
    events.push(event);
    for (const wait of waiting.splice(0)) {
      if (wait.match(event)) wait.resolve(event);
      else waiting.push(wait);
    }
  }, environment, copy);
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

test("i token del turno, subagenti compresi, arrivano prima di done, senza cifra", async () => {
  const { turns, events } = harness();
  await turns.run({ id: "t", prompt: "token", cwd: folder(), copilot: fake });
  const usage = events.findIndex((event) => event.type === "usage");
  expect(events[usage]).toEqual({ type: "usage", id: "t", mode: "apiKey", basis: "unknown", complete: true,
    models: [{ model: "gpt-6", inputTokens: 150, outputTokens: 30, cacheReadTokens: 20, cacheWriteTokens: 0, thinkingTokens: 0 }] });
  expect(usage).toBeLessThan(events.findIndex((event) => event.type === "done"));
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

test("la cartella di copilot va prima nel PATH", () => {
  expect(withFolderFirst({ PATH: "/usr/bin:/bin" }, "/Users/u/.npm-global/bin/copilot").PATH).toBe("/Users/u/.npm-global/bin:/usr/bin:/bin");
  expect(withFolderFirst({}, "/opt/homebrew/bin/copilot").PATH).toBe("/opt/homebrew/bin");
});

// ADR 0006: la conversazione Copilot nella copia di Bubo, ripresa con `resumeSession` da un altro `copilot`.
const copyIn = (cwd: string) => new ConversationStore(join(cwd, "conversazioni.sqlite"));
const copied = async (copy: ConversationStore, keep: string) =>
  copiedMessages(await copy.load({ projectKey: copilotProject, sessionId: keep }) ?? []).map(({ role, text }) => ({ role, text }));

test("la conversazione si copia e un nuovo copilot la riprende dal punto giusto", async () => {
  const cwd = folder();
  const copy = copyIn(cwd);
  await harness(undefined, copy).turns.run({ id: "i", prompt: "ciao", cwd, copilot: fake, keep: "k1" });
  // Un'altra istanza, come dopo un riavvio di Bubo: un altro processo `copilot`.
  const { turns, events } = harness(undefined, copy);
  await turns.run({ id: "j", prompt: "ricordi", cwd, copilot: fake, keep: "k1", resume: true });
  expect(texts(events)).toBe("Prima: ciao");
  expect(await copied(copy, "k1")).toEqual([
    { role: "user", text: "ciao" }, { role: "assistant", text: "Ciao mondo" },
    { role: "user", text: "ricordi" }, { role: "assistant", text: "Prima: ciao" },
  ]);
  expect(copy.entries("k1").every((entry) => typeof entry.timestamp === "string")).toBe(true);
});

test("se copilot non ha più la sessione, il turno riparte dalla copia di Bubo", async () => {
  const cwd = folder();
  const copy = copyIn(cwd);
  await harness(undefined, copy).turns.run({ id: "l", prompt: "ciao", cwd, copilot: fake, keep: "k2" });
  rmSync(join(cwd, ".copilot-state"), { recursive: true });
  const { turns, events } = harness(undefined, copy);
  await turns.run({ id: "m", prompt: "ricordi", cwd, copilot: fake, keep: "k2", resume: true });
  expect(texts(events)).toBe("Dalla copia");
  expect(events.at(-1)).toEqual({ type: "done", id: "m" });
  expect((await copied(copy, "k2")).map((message) => message.text)).toEqual(["ciao", "Ciao mondo", "ricordi", "Dalla copia"]);
});

test("i messaggi copiati hanno il formato di quelli di Claude, con la data", () => {
  const entries = [copiedEntry("user", "ciao", "u1", "2026-10-03T10:00:00.000Z"), copiedEntry("assistant", "  ", "a1")];
  expect(copiedMessages(entries)).toEqual([{ id: "u1", role: "user", text: "ciao", date: Date.parse("2026-10-03T10:00:00.000Z") }]);
});

test("riassunto, letture, scritture e comandi arrivano come quelli di Claude", async () => {
  const cwd = folder();
  const { turns, events } = harness();
  await turns.run({ id: "n", prompt: "attività", cwd, copilot: fake });
  const activity = events.filter((event) => ["summary", "read", "edit", "ran"].includes(event.type));
  expect(activity).toEqual([
    { type: "read", id: "n", files: [join(cwd, "a.txt")] },
    { type: "edit", id: "n", file: join(cwd, "a.txt"), lines: ["uno", "due"] },
    { type: "edit", id: "n", file: join(cwd, "b.txt"), lines: ["nuovo"] },
    { type: "read", id: "n", files: [join(cwd, "c.txt")] },
    { type: "ran", id: "n" },
    { type: "summary", id: "n", text: "Ho letto e scritto" },
  ]);
});

test("gli strumenti senza percorso o senza testo non sono Attività", () => {
  expect(toolActivity("view", {})).toBeUndefined();
  expect(toolActivity("grep", { path: "/a", pattern: "x" })).toBeUndefined();
  expect(toolActivity("str_replace_editor", { command: "insert", path: "/a", new_str: "x" })).toEqual({ type: "edit", file: "/a", lines: ["x"] });
});
