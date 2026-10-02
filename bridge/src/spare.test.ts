import { expect, test } from "bun:test";
import { sameKey, SpareSlot, type SpareKey } from "./spare";

class Fake {
  closed = false;
  constructor(readonly key: SpareKey) {}
  close() { this.closed = true; }
}

function slot(fail = false) {
  const started: Fake[] = [];
  const spares = new SpareSlot<Fake>(async (key) => {
    if (fail) throw new Error("claude mancante");
    const fake = new Fake(key);
    started.push(fake);
    return fake;
  });
  return { spares, started };
}

const user: SpareKey = { sources: ["user"] };
const project: SpareKey = { sources: ["user", "project", "local"], projectConfigRoot: "/r" };

test("stesse fonti e stessa radice sono la stessa riserva", () => {
  expect(sameKey(project, { sources: ["user", "project", "local"], projectConfigRoot: "/r" })).toBe(true);
  expect(sameKey(project, { sources: ["user", "project", "local"] })).toBe(false);
  expect(sameKey(user, { sources: ["user", "project"] })).toBe(false);
  expect(sameKey(project, { sources: ["local", "project", "user"], projectConfigRoot: "/r" })).toBe(false);
});

test("senza warm nessuna riserva: il ponte non ne avvia da sé", async () => {
  const { spares, started } = slot();
  expect(await spares.take(user)).toBeUndefined();
  expect(started).toHaveLength(0);
});

test("la riserva si consegna una volta sola", async () => {
  const { spares, started } = slot();
  spares.warm(user);
  spares.warm(user);
  expect(started).toHaveLength(1);
  expect(await spares.take(user)).toBe(started[0]);
  expect(await spares.take(user)).toBeUndefined();
});

test("una chiave diversa non prende la riserva e la lascia lì", async () => {
  const { spares, started } = slot();
  spares.warm(user);
  expect(await spares.take(project)).toBeUndefined();
  expect(await spares.take(user)).toBe(started[0]);
});

test("warm con un'altra chiave chiude la riserva di prima", async () => {
  const { spares, started } = slot();
  spares.warm(user);
  spares.warm(project);
  await Bun.sleep(0);
  expect(started[0].closed).toBe(true);
  expect(await spares.take(project)).toBe(started[1]);
});

test("cool chiude la riserva", async () => {
  const { spares, started } = slot();
  spares.warm(user);
  spares.cool();
  await Bun.sleep(0);
  expect(started[0].closed).toBe(true);
  expect(await spares.take(user)).toBeUndefined();
});

test("una riserva che non parte vale come nessuna riserva", async () => {
  const { spares } = slot(true);
  spares.warm(user);
  expect(await spares.take(user)).toBeUndefined();
});
