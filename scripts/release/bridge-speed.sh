#!/bin/zsh
# Il ponte firmato con hardened runtime e i suoi entitlement deve restare entro 2× lo stesso binario
# senza hardened runtime: senza allow-jit Bun non va in crash, rallenta di ~50× (spec 27).
# Compila un carico di prova con lo stesso Bun e la stessa firma del ponte (build phase "Ponte agente").
# Uso: bridge-speed.sh [entitlement.plist]   (default bridge/entitlements.plist)
set -euo pipefail
cd "${0:A:h}/../.."

entitlements=${1:-bridge/entitlements.plist}
bun=$(command -v bun || echo "$HOME/.bun/bin/bun")
work=$(mktemp -d)
trap 'rm -rf $work' EXIT

"$bun" build --compile --minify scripts/release/bridge-bench.ts --outfile $work/plain >/dev/null
cp $work/plain $work/hardened
codesign --force --sign - $work/plain
codesign --force --options runtime --entitlements $entitlements --sign - $work/hardened

# Il migliore di 3 giri, per non misurare il rumore della macchina.
best() {
    local fastest= ms
    for _ in 1 2 3; do
        ms=$($1)
        if [[ -z $fastest ]] || (( ms < fastest )); then fastest=$ms; fi
    done
    echo $fastest
}
plain=$(best $work/plain)
hardened=$(best $work/hardened)
typeset -F ratio=$(( 1.0 * hardened / plain ))

printf 'ponte: %.1f ms firmato, %.1f ms senza hardened runtime, %.2f×\n' $hardened $plain $ratio
(( ratio <= 2 )) || { print -u2 "ponte: firmato oltre 2× (entitlement: $entitlements)"; exit 1 }
