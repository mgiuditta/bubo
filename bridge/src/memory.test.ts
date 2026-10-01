import { expect, test } from "bun:test";
import { withAutoMemory } from "./memory";

test("in una Sessione la memoria automatica resta accesa", () => {
  expect(withAutoMemory({ HOME: "/Users/u" }, true)).toEqual({ HOME: "/Users/u" });
});

test("in una Domanda la memoria automatica si spegne", () => {
  expect(withAutoMemory({ HOME: "/Users/u" }, false)).toEqual({ HOME: "/Users/u", CLAUDE_CODE_DISABLE_AUTO_MEMORY: "1" });
});

test("una variabile ereditata non spegne la memoria di una Sessione", () => {
  expect(withAutoMemory({ CLAUDE_CODE_DISABLE_AUTO_MEMORY: "1" }, true)).toEqual({});
});
