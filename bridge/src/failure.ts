import type { SDKAPIRetryMessage, SDKAssistantMessageError } from "@anthropic-ai/claude-agent-sdk";

// Perché un turno non è andato, oltre al testo: il codice dell'SDK e l'ultimo tentativo di `claude` verso l'API.
// Con questi Bubo sceglie il rimedio del primo turno (spec 26, `AuthFailure`) senza cercare frasi nel testo.
// `status` è il codice HTTP dell'ultimo `api_retry`, assente se l'API non ha risposto; `noResponse` dice che non è
// arrivato nemmeno il primo byte.
export type TurnFailure = { reason?: SDKAssistantMessageError; status?: number; noResponse?: true };

export function turnFailure(reason: SDKAssistantMessageError | undefined,
                            retry: SDKAPIRetryMessage | undefined): TurnFailure {
  return {
    ...(reason && { reason }),
    ...(retry?.error_status != null && { status: retry.error_status }),
    ...(retry?.no_response && { noResponse: true as const }),
  };
}
