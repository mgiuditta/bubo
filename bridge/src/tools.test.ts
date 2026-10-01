import { expect, test } from "bun:test";
import { allowedBuboTools } from "./tools";

test("ricorda solo quando Bubo lo chiede, cioè nelle Domande", () => {
  expect(allowedBuboTools(true)).toEqual(["mcp__bubo__cerca", "mcp__bubo__ricorda"]);
  expect(allowedBuboTools(false)).toEqual(["mcp__bubo__cerca"]);
});
