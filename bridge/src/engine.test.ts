import { expect, test } from "bun:test";
import { mkdtempSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { Readable } from "node:stream";

// Il ponte vero, con il `copilot` finto e senza `claude` (#719): niente BUBO_CLAUDE_PATH nell'ambiente.
const fake = join(import.meta.dir, "fakeCopilotQuestion.mjs");

type Event = Record<string, unknown>;

function bridgeWithoutClaude() {
  const { BUBO_CLAUDE_PATH: _claude, ...env } = process.env;
  const child = Bun.spawn(["bun", join(import.meta.dir, "main.ts")], { env, stdin: "pipe", stdout: "pipe", stderr: "ignore" });
  const events: Event[] = [];
  const waiting: Array<{ match: (event: Event) => boolean; resolve: () => void }> = [];
  createInterface({ input: Readable.fromWeb(child.stdout as never) }).on("line", (line) => {
    const event = JSON.parse(line) as Event;
    events.push(event);
    for (const wait of waiting.splice(0)) {
      if (wait.match(event)) wait.resolve();
      else waiting.push(wait);
    }
  });
  const next = (match: (event: Event) => boolean) => new Promise<void>((resolve) => {
    if (events.some(match)) resolve();
    else waiting.push({ match, resolve });
  });
  const command = (body: Event) => {
    child.stdin.write(JSON.stringify({ v: 4, ...body }) + "\n");
    child.stdin.flush();
  };
  return { child, events, next, command };
}

test("senza claude il ponte parte, risponde via Copilot e rifiuta solo i turni Claude", async () => {
  const bridge = bridgeWithoutClaude();
  try {
    await bridge.next((event) => event.type === "ready");
    const cwd = realpathSync(mkdtempSync(join(tmpdir(), "bubo-solo-copilot-")));

    bridge.command({ type: "copilotQuestion", id: "q", prompt: "ciao", cwd, copilot: fake });
    await bridge.next((event) => event.id === "q" && (event.type === "done" || event.type === "error"));
    const answer = bridge.events.filter((event) => event.id === "q" && event.type === "text").map((event) => event.text).join("");
    expect(answer).toBe("Ciao mondo");
    expect(bridge.events.some((event) => event.id === "q" && event.type === "error")).toBe(false);

    bridge.command({ type: "ask", id: "c", prompt: "ciao", cwd });
    await bridge.next((event) => event.id === "c");
    expect(bridge.events.find((event) => event.id === "c")).toMatchObject({ type: "error", message: "claude mancante" });
  } finally {
    bridge.child.kill();
  }
}, 20_000);
