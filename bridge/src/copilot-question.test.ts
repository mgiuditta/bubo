import { expect, test } from "bun:test";
import { mkdtempSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { copilotEnvironment } from "./copilot";
import { CopilotQuestions, questionSession, refused, type CopilotQuestionEvent } from "./copilot-question";

// Il `copilot` finto: JSON-RPC del Copilot SDK su stdio, nessun turno pagato.
const fake = join(import.meta.dir, "fakeCopilotQuestion.mjs");

function harness(environment: Record<string, string> = copilotEnvironment(process.env)) {
  const events: CopilotQuestionEvent[] = [];
  const waiting: Array<{ match: (event: CopilotQuestionEvent) => boolean; resolve: () => void }> = [];
  const questions = new CopilotQuestions((event) => {
    events.push(event);
    for (const wait of waiting.splice(0)) {
      if (wait.match(event)) wait.resolve();
      else waiting.push(wait);
    }
  }, environment);
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
  expect(JSON.parse(texts(events))).toEqual({ availableTools: [], model: "gpt-6", effort: "high", tokens: [] });
});

test("una Richiesta che arriva comunque è respinta, senza passare da Bubo", async () => {
  const { questions, events } = harness();
  await questions.ask({ id: "c", prompt: "strumento", copilot: fake, cwd: folder() });
  expect(texts(events)).toBe("reject");
  expect(events.some((event) => (event.type as string) === "permission")).toBe(false);
  const config = questionSession({ cwd: "/tmp" });
  expect(config.availableTools).toEqual([]);
  expect(config.onPermissionRequest?.({ kind: "shell" } as never, { sessionId: "s" })).toEqual(refused);
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
