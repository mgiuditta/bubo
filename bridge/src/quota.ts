// Adattatore della Quota: l'unico punto che conosce le forme sperimentali dell'SDK.
// Se l'SDK cambia o toglie il metodo di uso, la Quota risulta vuota e Bubo la nasconde.
import type { Query, SDKRateLimitInfo } from "@anthropic-ai/claude-agent-sdk";

/** La parte usata di una finestra (0–1) e il reset in secondi Unix. */
export type QuotaWindow = { used: number; resetsAt: number };
export type Quota = { fiveHour?: QuotaWindow; sevenDay?: QuotaWindow };

type RawWindow = { utilization?: number | null; resetsAt?: number } | null | undefined;

function window(raw: RawWindow): QuotaWindow | undefined {
  return typeof raw?.utilization === "number" && typeof raw.resetsAt === "number"
    ? { used: raw.utilization, resetsAt: raw.resetsAt }
    : undefined;
}

function quota(fiveHour: QuotaWindow | undefined, sevenDay: QuotaWindow | undefined): Quota {
  return { ...(fiveHour && { fiveHour }), ...(sevenDay && { sevenDay }) };
}

/**
 * Da `rate_limit_event`: `utilization` in 0–1, `resetsAt` in secondi.
 * La CLI 2.1.286 manda anche `unifiedWindows` con entrambe le finestre; non è nei tipi dell'SDK,
 * quindi senza di esso vale solo la finestra nominata da `rateLimitType`.
 */
export function quotaFromRateLimit(info: SDKRateLimitInfo): Quota {
  const windows = (info as { unifiedWindows?: Record<string, RawWindow> }).unifiedWindows
    ?? (info.rateLimitType ? { [info.rateLimitType]: info } : {});
  return quota(window(windows.five_hour), window(windows.seven_day));
}

type Usage = {
  rate_limits_available?: boolean;
  rate_limits?: Record<string, { utilization: number | null; resets_at: string | null } | null | undefined> | null;
};

function usageWindow(raw: { utilization: number | null; resets_at: string | null } | null | undefined) {
  if (typeof raw?.utilization !== "number" || !raw.resets_at) return undefined;
  const resetsAt = Date.parse(raw.resets_at) / 1000;
  return Number.isFinite(resetsAt) ? { used: raw.utilization / 100, resetsAt } : undefined;
}

/** Dal metodo di uso dell'SDK: `utilization` in 0–100, `resets_at` in ISO 8601. */
export function quotaFromUsage(usage: Usage): Quota {
  if (!usage.rate_limits_available || !usage.rate_limits) return {};
  return quota(usageWindow(usage.rate_limits.five_hour), usageWindow(usage.rate_limits.seven_day));
}

const usageMethod = "usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET";

/** Legge la Quota da una conversazione senza turni: nessun messaggio al modello, quindi costo 0. */
export async function readQuota(conversation: Query): Promise<Quota> {
  const read = (conversation as unknown as Record<string, unknown>)[usageMethod];
  if (typeof read !== "function") return {};
  return quotaFromUsage(await read.call(conversation, { skipBehaviors: true }) as Usage);
}
