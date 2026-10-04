// Freschezza dell'Agent SDK del ponte (spec 27, #226): la release si ferma se una versione più nuova
// di quella in bridge/package.json è uscita da più di 7 giorni. Uso: bun scripts/release/sdk-fresh.ts
import { readFileSync } from "node:fs";
import { join } from "node:path";

export const sdkPackage = "@anthropic-ai/claude-agent-sdk";
export const maxLagDays = 7;
const day = 86_400_000;

type Registry = { "dist-tags": Record<string, string>; time: Record<string, string> };

/** Giorni da quando esiste una versione stabile più nuova di `pinned`; 0 se è la più recente. */
export function lagDays(registry: Registry, pinned: string, now: Date): number {
  const pinnedTime = registry.time[pinned];
  if (!pinnedTime) throw new Error(`${pinned} non è nel registro npm`);
  const newer = Object.entries(registry.time)
    .filter(([version, time]) => /^\d+\.\d+\.\d+$/.test(version) && time > pinnedTime)
    .map(([, time]) => Date.parse(time));
  if (!newer.length) return 0;
  return (now.getTime() - Math.min(...newer)) / day;
}

if (import.meta.main) {
  const root = join(import.meta.dir, "../..");
  const pinned = JSON.parse(readFileSync(join(root, "bridge/package.json"), "utf8")).dependencies[sdkPackage];
  const response = await fetch(`https://registry.npmjs.org/${sdkPackage}`);
  if (!response.ok) {
    console.error(`sdk: registro npm ${response.status}`);
    process.exit(1);
  }
  const registry = (await response.json()) as Registry;
  const lag = lagDays(registry, pinned, new Date());
  const latest = registry["dist-tags"].latest;
  if (lag > maxLagDays) {
    console.error(`sdk: ${pinned} indietro di ${Math.floor(lag)} giorni rispetto a ${latest}; lancia scripts/release/bump-sdk.sh`);
    process.exit(1);
  }
  console.log(`sdk: ${pinned} ok (ultima ${latest})`);
}
