// Confronto delle versioni di `claude` per lo smoke notturno; la minima sta in bridge/compat.json.
import { readFileSync } from "node:fs";
import { join } from "node:path";

/** "2.1.286 (Claude Code)" → [2, 1, 286]; undefined se non c'è un X.Y.Z. */
export function parseVersion(text: string): [number, number, number] | undefined {
  const match = /(\d+)\.(\d+)\.(\d+)/.exec(text);
  return match ? [Number(match[1]), Number(match[2]), Number(match[3])] : undefined;
}

export function compareVersions(a: [number, number, number], b: [number, number, number]): number {
  for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] - b[i];
  return 0;
}

export function minimumClaudeVersion(): string {
  const compat = JSON.parse(readFileSync(join(import.meta.dir, "..", "compat.json"), "utf8"));
  if (!parseVersion(compat.minimumClaudeVersion ?? "")) throw new Error("compat.json: minimumClaudeVersion non è X.Y.Z");
  return compat.minimumClaudeVersion;
}

/** Errore se la versione è illeggibile o sotto la minima. */
export function checkMinimum(installed: string, minimum: string) {
  const have = parseVersion(installed);
  const need = parseVersion(minimum);
  if (!need) throw new Error(`minima illeggibile: ${minimum}`);
  if (!have) throw new Error(`versione di claude illeggibile: ${installed}`);
  if (compareVersions(have, need) < 0) throw new Error(`claude ${have.join(".")} sotto la minima ${minimum}`);
}
