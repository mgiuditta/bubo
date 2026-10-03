#!/bin/zsh
# Porta l'Agent SDK del ponte all'ultima versione su npm, versione esatta e lockfile aggiornato (spec 27).
# Da lanciare prima del tag: release.yml si ferma se l'SDK è indietro di più di 7 giorni.
set -euo pipefail
cd "${0:A:h}/../../bridge"

package=@anthropic-ai/claude-agent-sdk
before=$(jq -r --arg p $package '.dependencies[$p]' package.json)
bun add --exact $package@latest >/dev/null
bun install --omit=optional >/dev/null
after=$(jq -r --arg p $package '.dependencies[$p]' package.json)
if [[ $before == $after ]]; then
    echo "sdk: già all'ultima ($after)"
else
    echo "sdk: $before → $after; prova il ponte con bun smoke/smoke.ts e fai la commit di package.json e bun.lock"
fi
