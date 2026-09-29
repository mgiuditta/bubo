// Quota del piano senza turno di modello: nessun prompt inviato.
// Stampa solo numeri e nomi di campo, niente email né identificativi.
import { query } from '@anthropic-ai/claude-agent-sdk';
const [cwd] = process.argv.slice(2);
let release; const idle = new Promise((r) => (release = r));
async function* noPrompt() { await idle; }
const t0 = Date.now();
const q = query({ prompt: noPrompt(), options: { cwd, model: 'haiku', persistSession: false } });
const u = await q.usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET({ skipBehaviors: true });
const ms = Date.now() - t0;
const acc = await q.accountInfo();
release(); q.close();
console.log(JSON.stringify({
  ms,
  subscription_type: u.subscription_type,
  rate_limits_available: u.rate_limits_available,
  rate_limits: u.rate_limits,
  session_cost_usd: u.session.total_cost_usd,
  accountInfoKeys: Object.keys(acc),
}, null, 1));
