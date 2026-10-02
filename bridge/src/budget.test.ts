import { expect, test } from "bun:test";
import { budgetOf } from "./budget";

test("il residuo del Budget diventa il tetto", () => {
  expect(budgetOf(2.5)).toBe(2.5);
});

test("senza un residuo positivo nessun tetto", () => {
  for (const value of [undefined, 0, -1, Number.NaN, Number.POSITIVE_INFINITY, "3"]) {
    expect(budgetOf(value)).toBeUndefined();
  }
});
