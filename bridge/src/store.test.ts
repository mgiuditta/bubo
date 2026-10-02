import { expect, test } from "bun:test";
import type { importSessionToStore } from "@anthropic-ai/claude-agent-sdk";
import { ConversationStore, mirrorOnly } from "./store";

const main = { projectKey: "-p", sessionId: "s" };
const agent = { ...main, subpath: "subagents/agent-a" };

function entries(...uuids: string[]) {
  return uuids.map((uuid) => ({ type: "user", uuid, message: { content: uuid } }));
}

// Un transcript locale finto, letto come lo leggerebbe `importSessionToStore`.
function transcript(...uuids: string[]): typeof importSessionToStore {
  return async (session, store) => {
    await store.append({ projectKey: "-p", sessionId: session }, entries(...uuids));
    await store.append({ projectKey: "-p", sessionId: session, subpath: "subagents/agent-a" }, entries("x"));
  };
}

test("la copia rende quello che ha ricevuto, nell'ordine, senza doppioni", async () => {
  const store = new ConversationStore(":memory:");
  await store.append(main, entries("1", "2"));
  await store.append(main, [...entries("2", "3"), { type: "custom-title", customTitle: "Login" }]);
  expect(await store.load(main)).toEqual([...entries("1", "2", "3"), { type: "custom-title", customTitle: "Login" }]);
  expect(await store.load({ ...main, sessionId: "altra" })).toBeNull();
});

test("i subagent stanno sotto la loro conversazione", async () => {
  const store = new ConversationStore(":memory:");
  await store.append(main, entries("1"));
  await store.append(agent, entries("a"));
  expect(await store.listSubkeys(main)).toEqual(["subagents/agent-a"]);
  expect(await store.load(agent)).toEqual(entries("a"));
  expect((await store.listSessions("-p")).map((session) => session.sessionId)).toEqual(["s"]);
});

test("eliminare una conversazione porta via anche i subagent", async () => {
  const store = new ConversationStore(":memory:");
  await store.append(main, entries("1"));
  await store.append(agent, entries("a"));
  await store.delete(main);
  expect(await store.load(main)).toBeNull();
  expect(await store.listSubkeys(main)).toEqual([]);
});

test("una Sessione eliminata porta via le copie delle sue conversazioni, le altre restano", async () => {
  const store = new ConversationStore(":memory:");
  await store.append(main, entries("1"));
  await store.append({ projectKey: "-q", sessionId: "t" }, entries("1"));
  store.forget(["s"]);
  expect(await store.load(main)).toBeNull();
  expect(await store.load({ projectKey: "-q", sessionId: "t" })).toEqual(entries("1"));
});

test("dopo un mirror_error la copia si rifà dal transcript, senza buchi", async () => {
  const store = new ConversationStore(":memory:");
  await store.append(main, entries("1", "3"));
  await store.replace("s", transcript("1", "2", "3"));
  expect(await store.load(main)).toEqual(entries("1", "2", "3"));
  expect(await store.load(agent)).toEqual(entries("x"));
});

test("se il transcript non si legge, la copia resta com'era", async () => {
  const store = new ConversationStore(":memory:");
  await store.append(main, entries("1"));
  await store.replace("s", async () => {});
  expect(await store.load(main)).toEqual(entries("1"));
  await expect(store.replace("s", async () => { throw new Error("sparito"); })).rejects.toThrow("sparito");
  expect(await store.load(main)).toEqual(entries("1"));
});

test("spegnere la copia della Cronologia CLI cancella solo quelle copie", async () => {
  const store = new ConversationStore(":memory:");
  await store.append(main, entries("1"));
  await store.replace("cli", transcript("c"));
  store.markImported("cli", 42);
  expect(store.importedAt("cli")).toBe(42);
  store.forgetImported();
  expect(store.importedAt("cli")).toBeUndefined();
  expect(await store.load({ projectKey: "-p", sessionId: "cli" })).toBeNull();
  expect(await store.load(main)).toEqual(entries("1"));
});

test("un turno copia nello store ma non riprende dallo store", async () => {
  const store = new ConversationStore(":memory:");
  await store.append(main, entries("1"));
  const seen = mirrorOnly(store);
  await seen.append(main, entries("2"));
  expect(await seen.load(main)).toBeNull();
  expect(await store.load(main)).toEqual(entries("1", "2"));
});
