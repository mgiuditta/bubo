import { expect, test } from "bun:test";
import { lagDays } from "./sdk-fresh";

const registry = {
  "dist-tags": { latest: "0.3.290" },
  time: {
    created: "2026-01-01T00:00:00Z",
    modified: "2026-09-30T00:00:00Z",
    "0.3.286": "2026-09-01T00:00:00Z",
    "0.3.287-beta.1": "2026-09-02T00:00:00Z",
    "0.3.287": "2026-09-03T00:00:00Z",
    "0.3.290": "2026-09-10T00:00:00Z",
  },
};

test("ultima versione: nessun ritardo", () => {
  expect(lagDays(registry, "0.3.290", new Date("2026-09-30T00:00:00Z"))).toBe(0);
});

test("il ritardo parte dalla prima versione stabile più nuova, non dalla beta", () => {
  expect(lagDays(registry, "0.3.286", new Date("2026-09-10T00:00:00Z"))).toBe(7);
});

test("SDK vecchio di 8 giorni: oltre la soglia", () => {
  expect(lagDays(registry, "0.3.286", new Date("2026-09-11T00:00:00Z"))).toBeGreaterThan(7);
});

test("versione assente dal registro", () => {
  expect(() => lagDays(registry, "0.0.1", new Date())).toThrow("non è nel registro");
});
