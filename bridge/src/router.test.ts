import { expect, test } from "bun:test";
import type { HookInput, ModelInfo, SDKMessage } from "@anthropic-ai/claude-agent-sdk";
import { AnswerWitness, catalogOf, effortOf } from "./router";

test("effortOf: solo i livelli dell'SDK", () => {
  expect(effortOf("medium")).toBe("medium");
  expect(effortOf("xhigh")).toBe("xhigh");
  expect(effortOf("altissimo")).toBeUndefined();
  expect(effortOf(3)).toBeUndefined();
});

test("catalogOf: Haiku senza sforzo resta senza livelli", () => {
  const models: ModelInfo[] = [
    { value: "haiku", resolvedModel: "claude-haiku-4-5-20251001", displayName: "Haiku", description: "", supportsEffort: false },
    { value: "opus", resolvedModel: "claude-opus-5-5", displayName: "Opus", description: "", supportsEffort: true,
      supportedEffortLevels: ["low", "medium", "high", "xhigh", "max"] },
  ];
  expect(catalogOf(models)).toEqual([
    { value: "haiku", resolvedModel: "claude-haiku-4-5-20251001", displayName: "Haiku" },
    { value: "opus", resolvedModel: "claude-opus-5-5", displayName: "Opus", supportedEffortLevels: ["low", "medium", "high", "xhigh", "max"] },
  ]);
});

const assistant = (model: string, parent: string | null) =>
  ({ type: "assistant", parent_tool_use_id: parent, message: { model } }) as unknown as SDKMessage;
const stop = (level?: string, agent?: string) =>
  ({ hook_event_name: "Stop", stop_hook_active: false, session_id: "s", transcript_path: "", cwd: "/",
     ...(agent && { agent_id: agent }), ...(level && { effort: { level } }) }) as unknown as HookInput;
const options = { signal: new AbortController().signal };

test("AnswerWitness: modello del thread principale e sforzo effettivo dall'hook Stop", async () => {
  const witness = new AnswerWitness();
  expect(witness.answeredBy()).toBeUndefined();
  witness.read(assistant("claude-sonnet-5-5", null));
  witness.read(assistant("claude-haiku-4-5-20251001", "toolu_1"));
  await witness.stopHook.hooks[0]!(stop("low", "agent_1"), undefined, options);
  await witness.stopHook.hooks[0]!(stop("high"), undefined, options);
  expect(witness.answeredBy()).toEqual({ model: "claude-sonnet-5-5", effort: "high" });
});

test("AnswerWitness: un modello senza sforzo non ha sforzo", async () => {
  const witness = new AnswerWitness();
  witness.read(assistant("claude-haiku-4-5-20251001", null));
  await witness.stopHook.hooks[0]!(stop(), undefined, options);
  expect(witness.answeredBy()).toEqual({ model: "claude-haiku-4-5-20251001" });
});
