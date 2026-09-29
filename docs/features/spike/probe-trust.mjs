// Regole di permesso attive in una cartella mai dichiarata fidata. Nessun turno di modello.
// Uso: node probe-trust.mjs <cwd>   (variabili d'ambiente passate così come sono)
import { query } from '@anthropic-ai/claude-agent-sdk';
const [cwd] = process.argv.slice(2);
const stderr = [];
let release; const idle = new Promise((r) => (release = r));
async function* noPrompt() { await idle; }
const q = query({ prompt: noPrompt(), options: {
  cwd, model: 'haiku', persistSession: false,
  env: { ...process.env },
  stderr: (l) => stderr.push(l.trim()),
} });
const { state } = await q.listPermissionRules();
release(); q.close();
console.log(JSON.stringify({
  rules: state.rules.filter((r) => r.rule.includes('spike')).map((r) => ({ source: r.source, rule: r.rule, notInEffect: r.notInEffect })),
  workspaceDirectories: state.workspaceDirectories,
  stderr: stderr.filter((l) => /trust|Ignoring/i.test(l)),
}, null, 1));
