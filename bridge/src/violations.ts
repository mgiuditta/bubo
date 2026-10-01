import type { HookInput } from "@anthropic-ai/claude-agent-sdk";
import { clean } from "./permission";

// I blocchi della Sandbox di un comando (spec 22). Non stanno in `permission_denials`: la CLI li aggiunge in coda
// all'output del comando, in un blocco non documentato che si legge qui (stringhe del binario 2.1.286):
//
//   <sandbox_violations>
//   touch(25195) deny(1) file-write-create /Users/u/fuori/a.txt      ← riga di Seatbelt, dal log del kernel
//   deny network-outbound example.com:443 (reason)                    ← riga del proxy della rete
//   </sandbox_violations>
//
// `violations.test.ts` si rompe se nome o forma cambiano.

/** Un blocco della Sandbox: cosa ha negato e su quale percorso o host. */
export type SandboxBlock = {
  kind: "write" | "read" | "network" | "other";
  /** Il percorso, o l'host per la rete; per una riga che non si sa leggere, la riga intera. */
  target: string;
  /** L'operazione negata, come la scrive Seatbelt (`file-write-create`), solo per `other`. */
  operation?: string;
};

/** Al più tanti blocchi per comando: oltre, la riga di Bubo non li mostrerebbe comunque. */
const maxBlocks = 20;

const seatbelt = /^(?:\S+\(\d+\)\s+)?deny(?:\(\d+\))?\s+(\S+)\s+(.+)$/;
const proxy = /^deny network-outbound (.+):(\d+)(?: \(.*\))?$/;

/**
 * I blocchi dell'ultimo `<sandbox_violations>` di `text`: la CLI lo mette in coda, quindi uno prima l'ha scritto il
 * comando stesso. Ogni riga dà un blocco, anche quella che non si sa leggere: nessun blocco resta nascosto.
 */
export function sandboxBlocks(text: string): SandboxBlock[] {
  const found = [...text.matchAll(/<sandbox_violations>([\s\S]*?)<\/sandbox_violations>/g)].at(-1)?.[1];
  if (found === undefined) return [];
  const blocks = new Map<string, SandboxBlock>();
  for (const raw of found.split("\n")) {
    const line = clean(raw.trim());
    if (!line) continue;
    const block = parsed(line);
    blocks.set(`${block.kind}\0${block.operation ?? ""}\0${block.target}`, block);
  }
  return [...blocks.values()].slice(0, maxBlocks);
}

function parsed(line: string): SandboxBlock {
  const network = proxy.exec(line);
  if (network) return { kind: "network", target: network[1]!.replace(/^\[(.*)\]$/, "$1") };
  const denial = seatbelt.exec(line);
  if (!denial) return { kind: "other", target: line };
  const [, operation, target] = denial as unknown as [string, string, string];
  if (operation.startsWith("file-write")) return { kind: "write", target };
  if (operation.startsWith("file-read")) return { kind: "read", target };
  return { kind: "other", target, operation };
}

/** La riga che vedono l'utente e l'agente per un blocco. */
export function blockedLine(block: SandboxBlock): string {
  switch (block.kind) {
    case "write": return `Bloccato dalla sandbox: scrittura in ${block.target}`;
    case "read": return `Bloccato dalla sandbox: lettura di ${block.target}`;
    case "network": return `Bloccato dalla sandbox: rete verso ${block.target}`;
    case "other": return `Bloccato dalla sandbox: ${block.operation ? `${block.operation} su ` : ""}${block.target}`;
  }
}

/** I blocchi di un Bash finito, dall'hook `PostToolUse` (l'output) o `PostToolUseFailure` (l'errore). */
export function blocksOf(input: HookInput): SandboxBlock[] {
  if (input.hook_event_name === "PostToolUse") return sandboxBlocks(texts(input.tool_response).join("\n"));
  if (input.hook_event_name === "PostToolUseFailure") return sandboxBlocks(input.error);
  return [];
}

/** Tutte le stringhe dentro `value`: l'output di Bash è un oggetto (`stdout`, `stderr`…) o già testo. */
function texts(value: unknown, depth = 0): string[] {
  if (typeof value === "string") return [value];
  if (depth > 4 || typeof value !== "object" || value === null) return [];
  return Object.values(value).flatMap((item) => texts(item, depth + 1));
}
