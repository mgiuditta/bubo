import { expect, test } from "bun:test";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { limitFromRateLimit, quotaFromRateLimit, quotaFromUsage, readQuota } from "./quota";

// Campioni registrati con Claude Code 2.1.286 e SDK 0.3.286 il 01/10/2026, account Max.
const rateLimitEvent = {
  type: "rate_limit_event",
  rate_limit_info: {
    status: "allowed", resetsAt: 1790852400, rateLimitType: "five_hour", overageStatus: "allowed",
    overageResetsAt: 1793491200, isUsingOverage: false,
    unifiedWindows: { five_hour: { utilization: 0.19, resetsAt: 1790852400 }, seven_day: { utilization: 0.02, resetsAt: 1791428400 } },
  },
  uuid: "9b36b9e5-4623-4b71-93de-a8891336408d",
  session_id: "8064abf5-eedd-4db3-8a7c-1176ab6d6107",
} as const;

const usage = {
  subscription_type: "max",
  rate_limits_available: true,
  rate_limits: {
    five_hour: { utilization: 20, resets_at: "2026-10-01T10:59:59.859758+00:00" },
    seven_day: { utilization: 2, resets_at: "2026-10-08T02:59:59.859781+00:00" },
    seven_day_oauth_apps: null, seven_day_opus: null, seven_day_sonnet: null,
    model_scoped: [{ display_name: "Fable", utilization: 0, resets_at: "2026-10-08T03:00:00+00:00" }],
  },
};

test("rate_limit_event registrato: entrambe le finestre da unifiedWindows", () => {
  expect(quotaFromRateLimit(rateLimitEvent.rate_limit_info as never)).toEqual({
    fiveHour: { used: 0.19, resetsAt: 1790852400 },
    sevenDay: { used: 0.02, resetsAt: 1791428400 },
  });
});

test("rate_limit_event con solo i campi dei tipi: vale la finestra nominata", () => {
  expect(quotaFromRateLimit({ status: "allowed_warning", rateLimitType: "seven_day", utilization: 0.8, resetsAt: 1791428400 }))
    .toEqual({ sevenDay: { used: 0.8, resetsAt: 1791428400 } });
});

test("rate_limit_event senza utilizzo: nessuna Quota inventata", () => {
  expect(quotaFromRateLimit({ status: "rejected", rateLimitType: "five_hour", resetsAt: 1790852400 })).toEqual({});
  expect(quotaFromRateLimit({ status: "allowed" })).toEqual({});
});

test("rate_limit_event rifiutato: finestra e reset del limite", () => {
  expect(limitFromRateLimit({ ...rateLimitEvent.rate_limit_info, status: "rejected" } as never))
    .toEqual({ window: "five_hour", resetsAt: 1790852400 });
  expect(limitFromRateLimit({ status: "rejected" })).toEqual({});
});

test("rate_limit_event consentito o in avviso: nessun limite", () => {
  expect(limitFromRateLimit(rateLimitEvent.rate_limit_info as never)).toBeUndefined();
  expect(limitFromRateLimit({ status: "allowed_warning", rateLimitType: "seven_day", utilization: 0.9 })).toBeUndefined();
});

test("metodo di uso registrato: percentuali in 0–1 e reset in secondi", () => {
  expect(quotaFromUsage(usage)).toEqual({
    fiveHour: { used: 0.2, resetsAt: Date.parse("2026-10-01T10:59:59.859758Z") / 1000 },
    sevenDay: { used: 0.02, resetsAt: Date.parse("2026-10-08T02:59:59.859781Z") / 1000 },
  });
});

test("API key o limiti assenti: Quota vuota", () => {
  expect(quotaFromUsage({ rate_limits_available: false, rate_limits: null })).toEqual({});
  expect(quotaFromUsage({ rate_limits_available: true, rate_limits: { five_hour: { utilization: null, resets_at: null } } }))
    .toEqual({});
});

test("metodo di uso sparito dall'SDK: Quota vuota", async () => {
  expect(await readQuota({} as never)).toEqual({});
});

// ADR 0003: Bubo non legge credenziali né chiama endpoint non documentati; lo fa solo il binario `claude`.
test("nessun codice legge credenziali di Claude o chiama endpoint non documentati", () => {
  const forbidden = [/oauth\/usage/i, /api\.anthropic\.com/i, /\.credentials\.json/, /Claude Code-credentials/, /accessToken/,
                     /find-generic-password/];
  const root = join(import.meta.dir, "..", "..");
  const files = (dir: string): string[] => readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? files(path) : /\.(swift|ts)$/.test(name) && !name.endsWith(".test.ts") ? [path] : [];
  });
  const sources = [...files(join(root, "Bubo")), ...files(join(root, "bridge", "src"))];
  expect(sources.length).toBeGreaterThan(10);
  for (const path of sources) {
    const text = readFileSync(path, "utf8");
    for (const pattern of forbidden) expect({ path, found: pattern.test(text) }).toEqual({ path, found: false });
  }
});
