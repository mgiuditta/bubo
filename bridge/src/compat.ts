import type { SDKMessage } from "@anthropic-ai/claude-agent-sdk";
import compat from "../compat.json";

// La minima di Bubo per il `claude` dell'utente, la stessa che legge l'app (spec 27, #225).
export const minimumClaudeVersion: string = compat.minimumClaudeVersion;

// Il `claude` di una Conversazione, dal suo `init`: versione e `capabilities` (assenti sulle CLI vecchie: vuote).
export type ClaudeInfo = { version: string; capabilities: string[] };

// Le prime tre cifre di `text` ("2.1.286 (Claude Code)", "v2.1.286"); `undefined` se non ce ne sono.
// Una prerelease ("2.1.275-beta.1") vale meno della sua versione, come in semver.
export function parseVersion(text: string): { core: number[]; prerelease: boolean } | undefined {
  const match = /^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?(-[0-9A-Za-z.-]+)?/.exec(text.trim());
  if (!match) return undefined;
  return { core: [match[1], match[2], match[3]].map((part) => Number(part ?? 0)), prerelease: match[4] !== undefined };
}

// Se `version` è sotto `minimum`. Una versione illeggibile non lo è: senza massima, decide `claude`.
export function isBelowMinimum(version: string, minimum = minimumClaudeVersion): boolean {
  const found = parseVersion(version);
  const least = parseVersion(minimum);
  if (!found || !least) return false;
  for (let index = 0; index < 3; index += 1) {
    if (found.core[index] !== least.core[index]) return found.core[index] < least.core[index];
  }
  return found.prerelease && !least.prerelease;
}

// Il `claude` che ha mandato `message`, se è un `init`; `capabilities` solo stringhe.
export function claudeInfo(message: SDKMessage): ClaudeInfo | undefined {
  if (message.type !== "system" || message.subtype !== "init") return undefined;
  const capabilities = Array.isArray(message.capabilities)
    ? message.capabilities.filter((capability): capability is string => typeof capability === "string") : [];
  return { version: message.claude_code_version, capabilities };
}

// Se `message` è il rifiuto di partire di un `claude` sotto la minima di Anthropic.
export function isTooOldForAnthropic(message: SDKMessage) {
  return message.type === "result" && message.subtype !== "success" && message.startup_failure_reason === "cli_version_too_old";
}
