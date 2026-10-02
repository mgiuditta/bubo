import { expect, test } from "bun:test";
import type { SDKControlReloadPluginsResponse } from "@anthropic-ai/claude-agent-sdk";
import { pluginReload, reloadOptions } from "./reload";

function response(extra: Partial<SDKControlReloadPluginsResponse> = {}): SDKControlReloadPluginsResponse {
  return { commands: [{ name: "review", description: "", argumentHint: "" }], agents: [], plugins: [], mcpServers: [],
           error_count: 0, ...extra } as SDKControlReloadPluginsResponse;
}

test("the first reload holds on cache impact, the forced one does not", () => {
  expect(reloadOptions(undefined)).toEqual({ holdOnCacheImpact: true });
  expect(reloadOptions(true)).toBeUndefined();
});

test("an applied reload brings the commands, without impact", () => {
  expect(pluginReload(response({ held: false }))).toEqual({ commands: ["review"], held: false });
  expect(pluginReload(response())).toEqual({ commands: ["review"], held: false });
});

test("a held reload brings what applying it would change", () => {
  const held = pluginReload(response({
    held: true,
    cache_impact: { mcp_servers_added: ["plugin:linear:linear"], mcp_servers_removed: [], lsp_tool_change: "may-add" },
  }));
  expect(held).toEqual({ commands: ["review"], held: true,
                         cacheImpact: { added: ["plugin:linear:linear"], removed: [], lsp: "may-add" } });
});
