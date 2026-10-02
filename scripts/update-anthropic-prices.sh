#!/bin/zsh
# Rifà la tabella prezzi Anthropic di Bubo (spec 18, #163), con cui la Cronologia CLI ha una stima a listino.
# È nostra e sta in un file a parte da Prezzi.json, che l'aggiornamento da models.dev riscrive: models.dev non ha
# la scrittura in cache a 1 h, che qui è il doppio dell'input (pagina prezzi di Anthropic: 2× il prezzo base).
# Va riletta a mano contro https://platform.claude.com/docs/en/about-claude/pricing quando esce un modello.
set -euo pipefail
cd "${0:A:h}/.."
work=$(mktemp -d)
trap 'rm -rf $work' EXIT
curl -sSf -o $work/api.json https://models.dev/api.json
jq --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
    date: $date,
    models: (.anthropic.models | map_values(select(.cost.input != null and .cost.output != null) | .cost | {
        input, output,
        cache_read: (.cache_read // (.input / 10)),
        cache_write_5m: (.cache_write // (.input * 1.25)),
        cache_write_1h: (.input * 2)
    }))
}' $work/api.json > Bubo/Resources/PrezziAnthropic.json
print "PrezziAnthropic.json: $(jq '.models | length' Bubo/Resources/PrezziAnthropic.json) modelli"
