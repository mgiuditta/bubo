import { expect, test } from "bun:test";
import type { McpServerConfig, McpSetServersResult } from "@anthropic-ai/claude-agent-sdk";
import { allowedPreviewTools, offerPreview, PreviewCalls, previewResult, turnServers, type PreviewCall } from "./preview";

const bubo = { type: "sdk", name: "bubo" } as unknown as McpServerConfig;
const preview = { type: "sdk", name: "anteprima" } as unknown as McpServerConfig;

test("senza server rilevato il turno ha solo bubo: nessuno strumento dell'Anteprima", () => {
  expect(Object.keys(turnServers(bubo))).toEqual(["bubo"]);
  expect(Object.keys(turnServers(bubo, preview))).toEqual(["bubo", "anteprima"]);
});

test("solo gli strumenti di Lettura girano senza Richiesta", () => {
  expect(allowedPreviewTools).toEqual(["mcp__anteprima__screenshot", "mcp__anteprima__dom", "mcp__anteprima__console", "mcp__anteprima__rete"]);
});

test("a turno in corso setMcpServers riceve sempre anche bubo", async () => {
  const payloads: Record<string, McpServerConfig>[] = [];
  const conversation = {
    setMcpServers: async (servers: Record<string, McpServerConfig>): Promise<McpSetServersResult> => {
      payloads.push(servers);
      return { added: [], removed: [], errors: {} };
    },
  };
  await offerPreview(conversation, bubo, preview);
  await offerPreview(conversation, bubo);
  expect(payloads).toEqual([{ bubo, anteprima: preview }, { bubo }]);
});

test("un setMcpServers che fallisce non rompe il turno", async () => {
  await offerPreview({ setMcpServers: async () => { throw new Error("chiuso"); } }, bubo, preview);
});

test("la risposta di Bubo diventa testo, immagine o errore", () => {
  expect(previewResult({ text: "ok" })).toEqual({ content: [{ type: "text", text: "ok" }] });
  expect(previewResult({ image: "AAAA" })).toEqual({ content: [{ type: "image", data: "AAAA", mimeType: "image/jpeg" }] });
  expect(previewResult({ error: "l'utente ha preso il controllo" }))
    .toEqual({ content: [{ type: "text", text: "l'utente ha preso il controllo" }], isError: true });
  expect(previewResult({ text: 3 }).isError).toBe(true);
});

test("ogni chiamata va a Bubo con la sua conversazione e torna con la sua risposta", async () => {
  const sent: [string, PreviewCall][] = [];
  const calls = new PreviewCalls((conversation, call) => sent.push([conversation, call]));
  const result = calls.call("t1", { tool: "clicca", selector: "#invia" });
  const [conversation, call] = sent[0]!;
  expect(conversation).toBe("t1");
  expect(call).toMatchObject({ type: "previewCall", tool: "clicca", selector: "#invia" });
  calls.answer("altra", { text: "no" });
  calls.answer(call.call, { text: "cliccato" });
  calls.answer(call.call, { text: "di nuovo" });
  expect(await result).toEqual({ content: [{ type: "text", text: "cliccato" }] });
});

test("senza risposta di Bubo la chiamata fallisce allo scadere", async () => {
  const calls = new PreviewCalls(() => {}, 10);
  expect((await calls.call("t1", { tool: "screenshot" })).isError).toBe(true);
});

test("se Bubo non si raggiunge la chiamata fallisce subito", async () => {
  const calls = new PreviewCalls(() => { throw new Error("EPIPE"); });
  expect((await calls.call("t1", { tool: "screenshot" })).isError).toBe(true);
});
