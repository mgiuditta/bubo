// Avvia il CLI senza turno di modello e guarda cosa carica.
// Uso: node probe-config.mjs <cwd> [projectConfigRoot]
import { query } from '@anthropic-ai/claude-agent-sdk';
import { readdirSync } from 'node:fs';
import { dirname } from 'node:path';

const [cwd, projectConfigRoot] = process.argv.slice(2);
const stderr = [];
let release;
const idle = new Promise((r) => (release = r));
async function* noPrompt() { await idle; }

const q = query({
  prompt: noPrompt(),
  options: {
    cwd,
    ...(projectConfigRoot ? { projectConfigRoot } : {}),
    model: 'haiku',
    persistSession: false,
    stderr: (line) => stderr.push(line.trim()),
  },
});
const init = await q.initializationResult();
const skills = (init.commands ?? []).map((c) => c.name).filter((n) => n.includes('spike'));
const agents = (init.agents ?? []).map((a) => a.name ?? a).filter((n) => String(n).includes('spike'));
// listPermissionRules() esiste a runtime ma non in sdk.d.ts 0.3.284.
const rulesState = await q.listPermissionRules();
const rules = rulesState.state.rules.filter((r) => JSON.stringify(r).includes('spike'));
await new Promise((r) => setTimeout(r, 1500));
release();
q.close();
const base = dirname(cwd);
console.log(JSON.stringify({
  cwd: cwd.split('/').pop(),
  projectConfigRoot: projectConfigRoot ? projectConfigRoot.split('/').pop() : null,
  skills, agents, rules,
  hookMarkers: readdirSync(base).filter((f) => f.startsWith('hook-ran')),
  stderrTrust: stderr.filter((l) => /trust|Ignoring/i.test(l)),
}, null, 1));
