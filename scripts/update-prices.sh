#!/bin/zsh
# Rifà l'istantanea dei prezzi nel bundle (spec 18, Prezzi): models.dev ridotto ai fornitori che Bubo stima
# a tabella, solo il campo `cost` dei modelli che ce l'hanno. Lo stesso taglio lo fa PriceTable all'aggiornamento.
set -euo pipefail
cd "${0:A:h}/.."
work=$(mktemp -d)
trap 'rm -rf $work' EXIT
curl -sSf -D $work/headers -o $work/api.json https://models.dev/api.json
etag=$(awk 'tolower($1)=="etag:" { sub(/\r$/, "", $2); print $2 }' $work/headers)
jq --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg etag "$etag" '{
    date: $date,
    etag: $etag,
    providers: (with_entries(select(.key == ("openai", "google", "xai")))
        | map_values({models: (.models | map_values(select(.cost != null) | {cost}))}))
}' $work/api.json > Bubo/Resources/Prezzi.json
print "Prezzi.json: $(jq '[.providers[].models | length] | add' Bubo/Resources/Prezzi.json) modelli"
