import type { SDKSystemMessage } from "@anthropic-ai/claude-agent-sdk";
import { expect, test } from "bun:test";
import { configuration } from "./config";

const init = {
  type: "system", subtype: "init", skills: ["prova", "review"],
  plugins: [{ name: "figma", path: "/p/figma", version: "1.2.0" }, { name: "locale", path: "/p/locale" }],
  plugin_errors: [{ plugin: "rotto@mercato", type: "dependency-unsatisfied", message: "manca base@mercato" }],
  mcp_servers: [{ name: "db", status: "pending", source: "project" }, { name: "linear", status: "needs-auth", source: "claudeai" }],
} as unknown as SDKSystemMessage;

test("init e mcpServerStatus diventano la configurazione del pannello", () => {
  const result = configuration(init, [{ name: "db", status: "failed", error: "Connection closed", scope: "project" }],
                               [{ path: "/r/CLAUDE.md", type: "Project" }, { path: "/r/CLAUDE.md", type: "Project" }],
                               [{ name: "Explore", description: "Cerca nel codice", model: "haiku" },
                                { name: "revisore", description: "Rivede il codice" }]);
  expect(result).toEqual({
    skills: ["prova", "review"],
    plugins: [{ name: "figma", path: "/p/figma", version: "1.2.0" }, { name: "locale", path: "/p/locale" }],
    pluginErrors: [{ plugin: "rotto@mercato", message: "manca base@mercato" }],
    mcpServers: [
      { name: "db", status: "failed", source: "project", error: "Connection closed" },
      { name: "linear", status: "needs-auth", source: "claudeai" },
    ],
    instructions: [{ path: "/r/CLAUDE.md", type: "Project" }],
    agents: [{ name: "Explore", description: "Cerca nel codice", model: "haiku" }, { name: "revisore", description: "Rivede il codice" }],
  });
});

test("senza plugin_errors, nessun errore", () => {
  const { plugin_errors: _, ...clean } = init as SDKSystemMessage & { plugin_errors?: unknown };
  expect(configuration(clean as SDKSystemMessage, [], [], []).pluginErrors).toEqual([]);
});
