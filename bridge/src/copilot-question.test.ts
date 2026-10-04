import { expect, test } from "bun:test";
import { mkdtempSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { copilotEnvironment } from "./copilot";
import { buboTools, CopilotQuestions, questionSession, refused, type AskBubo, type CopilotQuestionEvent } from "./copilot-question";
import type { BuboToolCall } from "./tools";

// Il `copilot` finto: JSON-RPC del Copilot SDK su stdio, nessun turno pagato.
const fake = join(import.meta.dir, "fakeCopilotQuestion.mjs");

function harness(environment: Record<string, string> = copilotEnvironment(process.env), askBubo?: AskBubo) {
  const events: CopilotQuestionEvent[] = [];
  const waiting: Array<{ match: (event: CopilotQuestionEvent) => boolean; resolve: () => void }> = [];
  const questions = new CopilotQuestions((event) => {
    events.push(event);
    for (const wait of waiting.splice(0)) {
      if (wait.match(event)) wait.resolve();
      else waiting.push(wait);
    }
  }, environment, askBubo);
  const next = (match: (event: CopilotQuestionEvent) => boolean) => new Promise<void>((resolve) => {
    if (events.some(match)) resolve();
    else waiting.push({ match, resolve });
  });
  return { questions, events, next };
}

const folder = () => realpathSync(mkdtempSync(join(tmpdir(), "bubo-domanda-copilot-")));
const texts = (events: CopilotQuestionEvent[]) => events.flatMap((event) => (event.type === "text" ? [event.text] : [])).join("");

test("la risposta arriva in streaming, con i token, chi ha risposto e done", async () => {
  const { questions, events } = harness();
  const firstToken = await questions.ask({ id: "a", prompt: "ciao", copilot: fake, cwd: folder() });
  expect(texts(events)).toBe("Ciao mondo");
  expect(events.filter((event) => event.type === "text")).toHaveLength(2);
  expect(events.slice(-3)).toEqual([
    { type: "usage", id: "a", mode: "apiKey", basis: "unknown", complete: true,
      models: [{ model: "gpt-6", inputTokens: 150, outputTokens: 30, cacheReadTokens: 20, cacheWriteTokens: 0, thinkingTokens: 10 }] },
    { type: "answeredBy", id: "a", model: "gpt-6", effort: "low" },
    { type: "done", id: "a" },
  ]);
  expect(firstToken?.sinceAsked).toBeGreaterThanOrEqual(firstToken?.sinceSent ?? Infinity);
});

test("la sessione non ha strumenti; modello e sforzo arrivano a copilot, i token di gh no", async () => {
  const { questions, events } = harness(copilotEnvironment({ ...process.env, GH_TOKEN: "x", GITHUB_TOKEN: "y", COPILOT_GITHUB_TOKEN: "z" }));
  await questions.ask({ id: "b", prompt: "sessione", copilot: fake, cwd: folder(), model: "gpt-6", effort: "high" });
  expect(JSON.parse(texts(events))).toEqual({ availableTools: [], tools: [], systemMessage: null, model: "gpt-6", effort: "high", tokens: [] });
});

test("una Richiesta che arriva comunque è respinta, senza passare da Bubo", async () => {
  const { questions, events } = harness();
  await questions.ask({ id: "c", prompt: "strumento", copilot: fake, cwd: folder() });
  expect(texts(events)).toBe("reject");
  expect(events.some((event) => (event.type as string) === "permission")).toBe(false);
  const config = questionSession({ id: "c", cwd: "/tmp" });
  expect(config.availableTools).toEqual([]);
  expect(config.onPermissionRequest?.({ kind: "shell" } as never, { sessionId: "s" })).toEqual(refused);
});

test("con il Secondo cervello la sessione ha solo cerca e ricorda di Bubo, e Profilo e Regole in coda al prompt", async () => {
  const { questions, events } = harness(undefined, async () => "");
  await questions.ask({ id: "g", prompt: "sessione", copilot: fake, cwd: folder(), brain: "## Bubo/Profilo.md\nMatteo" });
  const session = JSON.parse(texts(events));
  expect(session.availableTools).toEqual(["custom:cerca", "custom:ricorda"]);
  expect(session.tools).toEqual([{ name: "cerca", skipPermission: true }, { name: "ricorda", skipPermission: true }]);
  expect(session.systemMessage).toEqual({ mode: "append", content: "## Bubo/Profilo.md\nMatteo" });
});

test("senza Profilo e Regole, o senza Bubo che risponde, nessuno strumento né nota", () => {
  for (const config of [questionSession({ id: "h", cwd: "/tmp" }, async () => ""),
                        questionSession({ id: "h", cwd: "/tmp", brain: "## Bubo/Regole.md" })]) {
    expect(config.availableTools).toEqual([]);
    expect(config.tools).toBeUndefined();
    expect(config.systemMessage).toBeUndefined();
  }
});

test("cerca e ricorda arrivano a Bubo con la Domanda come conversazione, e la risposta torna a copilot", async () => {
  const calls: BuboToolCall[] = [];
  const { questions, events } = harness(undefined, async (call) => {
    calls.push(call);
    return call.type === "search" ? "Bubo/Note/Gatto.md: un gatto" : "Salvato in [[Gatto]]";
  });
  await questions.ask({ id: "i", prompt: "note", copilot: fake, cwd: folder(), brain: "## Bubo/Regole.md" });
  expect(calls).toEqual([
    { type: "search", query: "gatto", project: undefined, source: "secondo-cervello", conversation: "i" },
    { type: "remember", conversation: "i", mode: "nuova", title: "Gatto", note: undefined, text: "Il gatto si chiama Bubo", confirmed: false },
  ]);
  expect(texts(events)).toBe("Bubo/Note/Gatto.md: un gatto | Salvato in [[Gatto]]");
  expect(events.at(-1)).toEqual({ type: "done", id: "i" });
});

test("con il Secondo cervello ogni Richiesta di copilot resta respinta", async () => {
  const { questions, events } = harness(undefined, async () => "");
  await questions.ask({ id: "j", prompt: "strumento", copilot: fake, cwd: folder(), brain: "## Bubo/Regole.md" });
  expect(texts(events)).toBe("reject");
});

test("Ferma chiude la Domanda senza done né errore", async () => {
  const { questions, events, next } = harness();
  const asking = questions.ask({ id: "d", prompt: "lungo", copilot: fake, cwd: folder() });
  await next((event) => event.type === "text");
  expect(questions.cancel("d")).toBe(true);
  await asking;
  expect(events.map((event) => event.type)).toEqual(["text"]);
  expect(questions.cancel("d")).toBe(false);
});

test("un errore di copilot arriva come error", async () => {
  const { questions, events } = harness();
  await questions.ask({ id: "e", prompt: "errore", copilot: fake, cwd: folder() });
  expect(events).toEqual([{ type: "error", id: "e", message: "Crediti finiti" }]);
});

test("listModels arriva come copilotModels, senza i modelli spenti", async () => {
  const { questions, events } = harness();
  await questions.models("f", fake);
  expect(events).toEqual([{ type: "copilotModels", id: "f", models: [
    { id: "gpt-6", name: "GPT-6", multiplier: 1, supportedEfforts: ["low", "high"], defaultEffort: "low" },
    { id: "grok-5", name: "Grok 5" },
  ] }]);
});

test("un copilot che non parte dà un errore", async () => {
  const { questions, events } = harness();
  await questions.models("g", "/nessuno/copilot");
  expect(events).toHaveLength(1);
  expect(events[0]).toMatchObject({ type: "error", id: "g" });
});

test("Copilot cerca solo nelle note e non riscrive mai le note dell'utente, qualunque cosa dica", async () => {
  const calls: unknown[] = [];
  const [search, remember] = buboTools("c", async (call) => { calls.push(call); return "ok"; });
  await search.handler({ testo: "x", fonte: "conversazioni", progetto: "/p" }, {} as never);
  await remember.handler({ testo: "y", modo: "riscrivi", nota: "Mie/nota.md", confermato: true }, {} as never);
  expect(calls).toEqual([
    { type: "search", query: "x", project: undefined, source: "secondo-cervello", conversation: "c" },
    { type: "remember", conversation: "c", mode: "riscrivi", title: undefined, note: "Mie/nota.md", text: "y", confirmed: false },
  ]);
});
