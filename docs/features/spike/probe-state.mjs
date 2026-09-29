// Un turno minimo (haiku, maxTurns 1): quali messaggi system arrivano?
// Uso: node probe-state.mjs <cwd>   (con o senza CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS=1)
import { query } from '@anthropic-ai/claude-agent-sdk';
const [cwd] = process.argv.slice(2);
const seen = [];
const t0 = Date.now();
for await (const m of query({ prompt: 'Rispondi solo: ok', options: {
  cwd, model: 'haiku', maxTurns: 1, persistSession: false, env: { ...process.env },
} })) {
  const ms = Date.now() - t0;
  if (m.type === 'system' && m.subtype === 'session_state_changed')
    seen.push(`${ms}ms session_state_changed:${m.state}${m.sdk_host_only ? ' (sdk_host_only)' : ''}`);
  else if (m.type === 'rate_limit_event')
    seen.push(`${ms}ms rate_limit_event status=${m.rate_limit_info.status} type=${m.rate_limit_info.rateLimitType ?? '-'} util=${m.rate_limit_info.utilization ?? '-'}`);
  else seen.push(`${ms}ms ${m.type}${m.subtype ? ':' + m.subtype : ''}`);
}
console.log(`EMIT=${process.env.CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS ?? '(non impostata)'}`);
console.log(seen.join('\n'));
