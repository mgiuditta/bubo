import type { SandboxSettings } from "@anthropic-ai/claude-agent-sdk";

// La Sandbox di una Sessione la costruisce `SandboxPolicy` in Swift (spec 22): il ponte la passa a `Options.sandbox`
// così com'è, che l'SDK mette per intero nel livello `--settings`. Solo se accesa, e sempre con `failIfUnavailable`:
// mai un comando senza sandbox quando Bubo dice "accesa".
export function sandboxSettings(requested: unknown): SandboxSettings | undefined {
  if (typeof requested !== "object" || requested === null || Array.isArray(requested)) return undefined;
  if ((requested as { enabled?: unknown }).enabled !== true) return undefined;
  return { ...(requested as SandboxSettings), enabled: true, failIfUnavailable: true };
}

// Il motivo per cui `claude` non è partito senza sandbox: la CLI lo scrive su stderr ed esce, e l'SDK mette la coda di
// stderr nel messaggio dell'errore. `undefined` per ogni altro errore.
export function sandboxUnavailableReason(error: unknown): string | undefined {
  const message = error instanceof Error ? error.message : String(error);
  return /sandbox required but unavailable: ([^\n]*)/.exec(message)?.[1]?.trim() || undefined;
}
