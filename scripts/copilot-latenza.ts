// Misura la latenza al primo token delle Domande via Copilot (#540, ADR 0011 punto 6): p50 e p95 su N Domande brevi,
// dal comando al primo testo (con l'avvio di `copilot`) e dall'invio del prompt al primo testo.
//
// Spende crediti Copilot veri (circa 1 per Domanda): lo lancia una persona, mai la CI né un agente.
//
// Uso, dalla cartella bridge/ dopo `bun install`:
//   bun ../scripts/copilot-latenza.ts [copilot] [modello] [N]
// Default: /opt/homebrew/bin/copilot, il modello scelto in `copilot`, 20 Domande.
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { copilotEnvironment } from "../bridge/src/copilot";
import { CopilotQuestions, type FirstToken } from "../bridge/src/copilot-question";

const [copilot = "/opt/homebrew/bin/copilot", model, count = "20"] = process.argv.slice(2);
const cwd = mkdtempSync(join(tmpdir(), "bubo-latenza-copilot-"));
const questions = new CopilotQuestions((event) => {
  if (event.type === "error") console.error(`Domanda ${event.id}: ${event.message}`);
}, copilotEnvironment(process.env));

const measured: FirstToken[] = [];
for (let index = 0; index < Number(count); index++) {
  const firstToken = await questions.ask({ id: String(index), prompt: "Rispondi solo: ok", copilot, cwd, model: model || undefined });
  if (firstToken) measured.push(firstToken);
  console.error(`${index + 1}/${count}: ${firstToken ? `${firstToken.sinceAsked} ms` : "nessun testo"}`);
}

function percentile(values: number[], fraction: number) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(fraction * sorted.length) - 1)];
}

for (const [label, key] of [["dal comando", "sinceAsked"], ["dall'invio", "sinceSent"]] as const) {
  const values = measured.map((value) => value[key]);
  if (values.length) console.log(`${label}: p50 ${percentile(values, 0.5)} ms, p95 ${percentile(values, 0.95)} ms (${values.length} Domande)`);
}
