import { expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { copilotEnvironment, CopilotPermissions, type IsDangerous } from "./copilot";
import { buboTools, CopilotQuestions, hiddenToolDenial, questionSession, type AskBubo, type CopilotQuestionEvent } from "./copilot-question";
import type { RiskQuestion } from "./gate";
import type { BuboToolCall } from "./tools";

// Il `copilot` finto: JSON-RPC del Copilot SDK su stdio, nessun turno pagato.
const fake = join(import.meta.dir, "fakeCopilotQuestion.mjs");

function harness(environment: Record<string, string> = copilotEnvironment(process.env), askBubo?: AskBubo,
                 isDangerous?: IsDangerous) {
  const events: CopilotQuestionEvent[] = [];
  const waiting: Array<{ match: (event: CopilotQuestionEvent) => boolean; resolve: (event: CopilotQuestionEvent) => void }> = [];
  const send = (event: CopilotQuestionEvent) => {
    events.push(event);
    for (const wait of waiting.splice(0)) {
      if (wait.match(event)) wait.resolve(event);
      else waiting.push(wait);
    }
  };
  const questions = new CopilotQuestions(send, environment, askBubo, new CopilotPermissions(send, isDangerous));
  const next = (match: (event: CopilotQuestionEvent) => boolean) => new Promise<CopilotQuestionEvent>((resolve) => {
    const seen = events.find(match);
    if (seen) resolve(seen);
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

test("la sessione ha gli strumenti e la configurazione di copilot; modello e sforzo arrivano, i token di gh no", async () => {
  const { questions, events } = harness(copilotEnvironment({ ...process.env, GH_TOKEN: "x", GITHUB_TOKEN: "y", COPILOT_GITHUB_TOKEN: "z" }));
  await questions.ask({ id: "b", prompt: "sessione", copilot: fake, cwd: folder(), model: "gpt-6", effort: "high" });
  expect(JSON.parse(texts(events))).toEqual({ availableTools: null, hooks: false, enableConfigDiscovery: true, tools: [],
    systemMessage: null, model: "gpt-6", effort: "high", tokens: [] });
});

test("una lettura passa senza Richiesta: il cancello chiede a Bubo il livello, e sotto il 4 approva da sé", async () => {
  const asked: RiskQuestion[] = [];
  const { questions, events } = harness(undefined, undefined, async (id, question) => {
    expect(id).toBe("c");
    asked.push(question);
    return false;
  });
  await questions.ask({ id: "c", prompt: "leggi /etc/hosts", copilot: fake, cwd: folder() });
  expect(texts(events)).toBe("approve-once");
  expect(asked).toEqual([{ tool: "Read", command: undefined, path: "/etc/hosts", url: undefined }]);
  expect(events.some((event) => event.type === "permission")).toBe(false);
});

test("un'azione di livello 4–5 apre la stessa Richiesta di una Domanda Claude, e rifiutarla blocca lo strumento", async () => {
  for (const allowed of [false, true]) {
    const { questions, events, next } = harness(undefined, undefined, async () => true);
    const asking = questions.ask({ id: "k", prompt: "strumento", copilot: fake, cwd: folder() });
    const request = await next((event) => event.type === "permission");
    expect(request).toMatchObject({ type: "permission", id: "k", tool: "Bash", command: "rm -rf /", description: "Pulisce" });
    expect(questions.answer((request as { request: string }).request, allowed)).toBe(true);
    await asking;
    expect(texts(events)).toBe(allowed ? "approve-once" : "reject");
  }
});

test("senza risposta sul livello, ogni azione conta come 4–5 e chiede", async () => {
  const { questions, events, next } = harness();
  const asking = questions.ask({ id: "m", prompt: "scrivi /tmp/nota.md", copilot: fake, cwd: folder() });
  const request = await next((event) => event.type === "permission");
  expect(request).toMatchObject({ tool: "Edit", path: "/tmp/nota.md" });
  questions.answer((request as { request: string }).request, false);
  await asking;
  expect(texts(events)).toBe("reject");
});

test("le cartelle escluse restano chiuse a copilot: l'hook nega prima dello strumento, senza chiedere", async () => {
  const cwd = folder();
  mkdirSync(join(cwd, "Privato"));
  const hidden = [join(cwd, "Privato")];
  let gated = false;
  const { questions, events } = harness(undefined, undefined, async () => { gated = true; return false; });
  await questions.ask({ id: "n", prompt: `leggi ${join(cwd, "Privato/diario.md")}`, copilot: fake, cwd, hidden });
  expect(texts(events)).toBe("negato: Questa cartella è esclusa dal Secondo cervello: Bubo non la legge.");
  expect(gated).toBe(false);
  const { questions: other, events: seen } = harness(undefined, undefined, async () => false);
  await other.ask({ id: "o", prompt: `leggi ${join(cwd, "pubblica.md")}`, copilot: fake, cwd, hidden });
  expect(texts(seen)).toBe("approve-once");
});

test("anche una Richiesta di lettura o scrittura in una cartella esclusa è respinta, senza passare da Bubo", async () => {
  let asked = false;
  const config = questionSession({ id: "p", cwd: "/vault", hidden: ["/vault/Privato"] }, async () => {
    asked = true;
    return { kind: "approve-once" };
  });
  for (const request of [{ kind: "read", path: "/vault/Privato/a.md" }, { kind: "write", fileName: "/vault/Privato/b.md" }]) {
    expect(await config.onPermissionRequest?.(request as never, { sessionId: "s" })).toMatchObject({ kind: "reject" });
  }
  expect(asked).toBe(false);
  expect(await config.onPermissionRequest?.({ kind: "read", path: "/vault/a.md" } as never, { sessionId: "s" }))
    .toEqual({ kind: "approve-once" });
});

test("grep e glob non attraversano una cartella esclusa; i nomi di copilot valgono come quelli di Claude", () => {
  const hidden = ["/vault/Privato"];
  expect(hiddenToolDenial("view", { path: "/vault/Privato/a.md" }, "/vault", hidden)).toBeDefined();
  expect(hiddenToolDenial("edit", { path: "Privato/a.md" }, "/vault", hidden)).toBeDefined();
  expect(hiddenToolDenial("grep", { pattern: "x", path: "/vault" }, "/vault", hidden)).toBeDefined();
  expect(hiddenToolDenial("glob", { pattern: "../**" }, "/vault", hidden)).toBeDefined();
  expect(hiddenToolDenial("view", { path: "/vault/a.md" }, "/vault", hidden)).toBeUndefined();
  expect(hiddenToolDenial("bash", { command: "ls" }, "/vault", hidden)).toBeUndefined();
});

test("con il Secondo cervello la sessione ha anche cerca e ricorda di Bubo, e Profilo e Regole in coda al prompt", async () => {
  const { questions, events } = harness(undefined, async () => "");
  await questions.ask({ id: "g", prompt: "sessione", copilot: fake, cwd: folder(), brain: "## Bubo/Profilo.md\nMatteo",
                       hidden: ["/vault/Privato"] });
  const session = JSON.parse(texts(events));
  expect(session.availableTools).toBeNull();
  expect(session.hooks).toBe(true);
  expect(session.tools).toEqual([{ name: "cerca", skipPermission: true }, { name: "ricorda", skipPermission: true }]);
  expect(session.systemMessage).toEqual({ mode: "append", content: "## Bubo/Profilo.md\nMatteo" });
});

test("senza Profilo e Regole, o senza Bubo che risponde, nessuno strumento di Bubo né nota", () => {
  const askPermission = async () => ({ kind: "approve-once" as const });
  for (const config of [questionSession({ id: "h", cwd: "/tmp" }, askPermission, async () => ""),
                        questionSession({ id: "h", cwd: "/tmp", brain: "## Bubo/Regole.md" }, askPermission)]) {
    expect(config.availableTools).toBeUndefined();
    expect(config.tools).toBeUndefined();
    expect(config.systemMessage).toBeUndefined();
    expect(config.hooks).toBeUndefined();
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

test("con il Secondo cervello le Richieste passano dallo stesso cancello", async () => {
  const { questions, events } = harness(undefined, async () => "", async () => false);
  await questions.ask({ id: "j", prompt: "strumento", copilot: fake, cwd: folder(), brain: "## Bubo/Regole.md" });
  expect(texts(events)).toBe("approve-once");
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
