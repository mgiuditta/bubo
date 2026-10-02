import { expect, test } from "bun:test";
import { agentQuestion, answersOf, declined, notShown, questionResult, replyLength } from "./question";

const input = () => ({
  questions: [
    {
      question: "Quale libreria \x1b[31muso\x1b[0m?",
      header: "Libreria",
      options: [{ label: "date-fns", description: "Leggera" }, { label: "Luxon", description: "Fusi orari" }],
      multiSelect: false,
    },
    {
      question: "Cosa abilito?",
      header: "Funzioni",
      options: [{ label: "Cache", description: "" }, { label: "Log", description: "" }, { label: "Metriche", description: "" }],
      multiSelect: true,
    },
  ],
});

test("le domande arrivano a Bubo ripulite, con le opzioni in ordine", () => {
  expect(agentQuestion("q1", input())).toEqual({
    type: "question",
    request: "q1",
    questions: [
      {
        question: "Quale libreria uso?", header: "Libreria", multiSelect: false,
        options: [{ label: "date-fns", description: "Leggera" }, { label: "Luxon", description: "Fusi orari" }],
      },
      {
        question: "Cosa abilito?", header: "Funzioni", multiSelect: true,
        options: [{ label: "Cache", description: "" }, { label: "Log", description: "" }, { label: "Metriche", description: "" }],
      },
    ],
  });
});

test("un input senza la forma di AskUserQuestion non si mostra", () => {
  for (const questions of [undefined, [], "x", [{ question: 1, options: [] }], [{ question: "a", options: "b" }],
    Array(5).fill({ question: "a", options: [{ label: "x" }] }),
    [{ question: "a", options: [{ label: "x" }] }, { question: "a", options: [{ label: "y" }] }]]) {
    expect(agentQuestion("q", { questions })).toBeUndefined();
  }
});

test("le risposte usano domanda ed etichette originali, non il testo ripulito", () => {
  const original = input();
  expect(answersOf(original, [{ options: [1] }, { options: [0, 2] }])).toEqual({
    "Quale libreria \x1b[31muso\x1b[0m?": "Luxon",
    "Cosa abilito?": ["Cache", "Metriche"],
  });
});

test("la risposta scritta vale da sola a scelta singola e si aggiunge a scelta multipla", () => {
  expect(answersOf(input(), [{ options: [], text: "  Temporal  " }, { options: [1], text: "Tracce" }])).toEqual({
    "Quale libreria \x1b[31muso\x1b[0m?": "Temporal",
    "Cosa abilito?": ["Log", "Tracce"],
  });
  const long = answersOf(input(), [{ options: [], text: "x".repeat(10_000) }, { options: [0] }]);
  expect((long?.["Quale libreria \x1b[31muso\x1b[0m?"] as string).length).toBe(replyLength);
});

test("una risposta storta o incompleta non risponde", () => {
  for (const replies of [undefined, null, "Luxon", [], [{ options: [1] }],
    [{ options: [0, 1] }, { options: [0] }], [{ options: [2] }, { options: [0] }], [{ options: [-1] }, { options: [0] }],
    [{ options: [0] }, { options: [0, 0] }], [{ options: [0] }, { options: [] }], [{ options: [] }, { options: [0] }],
    [{ options: ["0"] }, { options: [0] }], [null, { options: [0] }]]) {
    expect(answersOf(input(), replies)).toBeUndefined();
  }
});

test("con le risposte la domanda gira; senza, è negata con il perché", () => {
  const original = input();
  const answers = { "Cosa abilito?": ["Log"] };
  expect(questionResult(original, answers)).toEqual({
    behavior: "allow", updatedInput: { ...original, answers }, decisionClassification: "user_temporary",
  });
  expect(questionResult(original)).toEqual({ behavior: "deny", message: declined, decisionClassification: "user_reject" });
  expect(questionResult(original, undefined, notShown)).toMatchObject({ behavior: "deny", message: notShown });
});
