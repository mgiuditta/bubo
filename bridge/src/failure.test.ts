import type { SDKAPIRetryMessage } from "@anthropic-ai/claude-agent-sdk";
import { expect, test } from "bun:test";
import { turnFailure } from "./failure";

// Forma di `api_retry` da sdk.d.ts dell'SDK 0.3.286: nessun turno vero lanciato per costruirlo.
const retry = (error_status: number | null, no_response?: SDKAPIRetryMessage["no_response"]): SDKAPIRetryMessage => ({
  type: "system", subtype: "api_retry", attempt: 1, max_retries: 10, retry_delay_ms: 500, error_status,
  error: error_status === null ? "unknown" : "server_error", ...(no_response && { no_response }),
  uuid: "9b36b9e5-4623-4b71-93de-a8891336408d", session_id: "8064abf5-eedd-4db3-8a7c-1176ab6d6107",
});

test("il codice dell'SDK passa a Bubo", () => {
  expect(turnFailure("billing_error", undefined)).toEqual({ reason: "billing_error" });
});

test("l'ultimo tentativo porta il codice HTTP", () => {
  expect(turnFailure("server_error", retry(529))).toEqual({ reason: "server_error", status: 529 });
});

test("senza risposta dall'API niente codice HTTP", () => {
  expect(turnFailure(undefined, retry(null))).toEqual({});
  expect(turnFailure(undefined, retry(null, { waited_ms: 30000, retry_wait_ms: 60000 }))).toEqual({ noResponse: true });
});
