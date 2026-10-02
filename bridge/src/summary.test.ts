import { expect, test } from "bun:test";
import type { Options, Query, SDKMessage } from "@anthropic-ai/claude-agent-sdk";
import { summarize, summaryOptions, type SummaryEvent } from "./summary";

test("un riassunto non ha strumenti, impostazioni, server MCP né persistenza", async () => {
  const options = summaryOptions("/tmp/vuota", "haiku", { PATH: "/bin" }, "/usr/local/bin/claude");
  expect(options.maxTurns).toBe(1);
  expect(options.tools).toEqual([]);
  expect(options.allowedTools).toEqual([]);
  expect(options.mcpServers).toEqual({});
  expect(options.strictMcpConfig).toBe(true);
  expect(options.settingSources).toEqual([]);
  expect(options.persistSession).toBe(false);
  expect(options.model).toBe("haiku");
  expect(options.env?.CLAUDE_CODE_DISABLE_AUTO_MEMORY).toBe("1");
  const verdict = await options.canUseTool!("Bash", {}, { signal: new AbortController().signal } as never);
  expect(verdict.behavior).toBe("deny");
});

test("il testo dell'assistente arriva, poi la fine", async () => {
  const messages = [
    { type: "assistant", message: { id: "m", model: "haiku", content: [{ type: "text", text: "## Fatto\n- a" }],
      usage: { input_tokens: 1, output_tokens: 1 } } },
    { type: "result", subtype: "success", is_error: false, result: "", session_id: "s" },
  ] as unknown as SDKMessage[];
  const events: SummaryEvent[] = [];
  let received: Options | undefined;
  await summarize("r1", "riassumi", summaryOptions("/tmp", undefined, {}, undefined), ({ options }) => {
    received = options;
    return (async function* () { yield* messages; })() as unknown as Query;
  }, (event) => events.push(event));
  expect(received?.tools).toEqual([]);
  expect(events).toContainEqual({ type: "text", id: "r1", text: "## Fatto\n- a" });
  expect(events.at(-1)).toEqual({ type: "done", id: "r1" });
});
