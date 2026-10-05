import type { PermissionResult } from "@anthropic-ai/claude-agent-sdk";
import { clean } from "./permission";

// Le domande dell'agente (`AskUserQuestion`) come Bubo le mostra: testo ripulito, opzioni per posizione.
// Tipi dell'input in `sdk-tools.d.ts` (`AskUserQuestionInput`, SDK 0.3.286): 1–4 domande, 2–4 opzioni, `multiSelect`.
export type ShownQuestion = {
  question: string;
  header: string;
  options: { label: string; description?: string; preview?: string }[];
  multiSelect: boolean;
  /** `false` quando l'agente non accetta una risposta scritta: Bubo non mostra «Altro». */
  freeform?: false;
};

export type AgentQuestion = { type: "question"; request: string; questions: ShownQuestion[] };

// La risposta di Bubo a una domanda: le opzioni scelte per posizione e, se c'è, la risposta scritta.
export type Reply = { options: number[]; text?: string };

type Question = { question: string; options: { label: string }[]; multiSelect: boolean };

// Una risposta scritta resta sotto il limite che la CLI accetta per ciascuna (8192) e per tutte insieme (32768).
export const replyLength = 4000;

export const declined = "L'utente ha scelto di non rispondere alle domande in Bubo: continua senza, con la scelta più prudente.";
export const notShown = "Bubo non ha potuto mostrare queste domande all'utente: continua senza, con la scelta più prudente.";

// Le domande dell'input del modello, se hanno la forma che `AskUserQuestion` promette; altrimenti `undefined`.
function questionsOf(input: Record<string, unknown>): Question[] | undefined {
  const questions = input.questions;
  if (!Array.isArray(questions) || questions.length < 1 || questions.length > 4) return undefined;
  const valid = questions.every((item) => {
    if (typeof item !== "object" || item === null) return false;
    const { question, options } = item as Record<string, unknown>;
    return typeof question === "string" && Array.isArray(options) && options.length >= 1 && options.length <= 4
      && options.every((option) => typeof option === "object" && option !== null
        && typeof (option as Record<string, unknown>).label === "string");
  });
  if (!valid) return undefined;
  const texts = questions.map((item) => (item as Question).question);
  if (new Set(texts).size !== texts.length) return undefined;
  return questions as Question[];
}

// Le domande da mostrare a Bubo; `undefined` se l'input non ha la forma attesa e Bubo non può mostrarle.
export function agentQuestion(request: string, input: Record<string, unknown>): AgentQuestion | undefined {
  const questions = questionsOf(input);
  if (!questions) return undefined;
  return {
    type: "question",
    request,
    questions: questions.map((item) => {
      const { header, multiSelect } = item as unknown as Record<string, unknown>;
      return {
        question: clean(item.question) ?? "",
        header: clean(header) ?? "",
        options: item.options.map((option) => ({
          label: clean(option.label) ?? "",
          description: clean((option as Record<string, unknown>).description),
          preview: clean((option as Record<string, unknown>).preview),
        })),
        multiSelect: multiSelect === true,
      };
    }),
  };
}

// Le risposte nel formato della CLI: testo della domanda → etichetta, oppure etichette scelte più la risposta scritta
// unite da ", " per `multiSelect` (l'SDK vuole una stringa); con una risposta scritta, a scelta singola vale quella. Le etichette e le domande sono quelle
// originali, mai il testo ripulito. `undefined` se `replies` non è una risposta valida a ogni domanda.
export function answersOf(input: Record<string, unknown>, replies: unknown): Record<string, string> | undefined {
  const questions = questionsOf(input);
  if (!questions || !Array.isArray(replies) || replies.length !== questions.length) return undefined;
  const answers: Record<string, string> = {};
  for (const [index, question] of questions.entries()) {
    const reply = replies[index] as Partial<Reply> | null;
    if (typeof reply !== "object" || reply === null || !Array.isArray(reply.options)) return undefined;
    const chosen = reply.options;
    if (!chosen.every((option) => Number.isInteger(option) && option >= 0 && option < question.options.length)
        || new Set(chosen).size !== chosen.length) return undefined;
    const text = typeof reply.text === "string" ? reply.text.trim().slice(0, replyLength) : "";
    const labels = chosen.map((option) => question.options[option].label);
    if (question.multiSelect) {
      const all = text ? [...labels, text] : labels;
      if (all.length === 0) return undefined;
      answers[question.question] = all.join(", ");
    } else if (text) {
      answers[question.question] = text;
    } else if (labels.length === 1) {
      answers[question.question] = labels[0];
    } else {
      return undefined;
    }
  }
  return answers;
}

// Con le risposte, `AskUserQuestion` gira con l'input mostrato più `answers`; senza, è negata e Claude lo sa.
export function questionResult(input: Record<string, unknown>, answers?: Record<string, string>,
                               message = declined): PermissionResult {
  return answers
    ? { behavior: "allow", updatedInput: { ...input, answers }, decisionClassification: "user_temporary" }
    : { behavior: "deny", message, decisionClassification: "user_reject" };
}
