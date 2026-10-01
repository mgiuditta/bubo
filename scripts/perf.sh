#!/bin/zsh
# Prestazioni sul Mac di riferimento (spec 25): esegue lo schema BuboPerf in Release, legge il tempo GPU dell'Orb dal
# Metal HUD e scrive in .build/perf/<data>/ report.md e report.json contro i budget di BuboPerfTests/PerfBudgets.swift.
# Esce con 1 se un budget è superato o un invariante è rotto; le righe non misurate non bloccano.
#
#   scripts/perf.sh            test di prestazione, memoria a riposo, tempo GPU dell'Orb
#   scripts/perf.sh --freddo   misura prima l'avvio freddo: va lanciato subito dopo un riavvio del Mac
#   scripts/perf.sh --live     apre anche una Sessione vera (claude e rete) per l'intervallo sul main thread
#   scripts/perf.sh --ci       per .github/workflows/perf.yml: esce con 1 solo oltre 2× un budget o con un invariante
#                              rotto, e scrive gli avvisi di GitHub Actions
#
# La build non è firmata (CODE_SIGNING_ALLOWED=NO): basta un Mac con Xcode, senza profili né certificati.
set -euo pipefail
cd "${0:A:h}/.."

cold=0 live=0 ci=0
for option in "$@"; do
  case $option in
    --freddo) cold=1 ;;
    --live) live=1 ;;
    --ci) ci=1 ;;
    *) print -u2 "uso: scripts/perf.sh [--freddo] [--live] [--ci]"; exit 64 ;;
  esac
done

if pgrep -x Bubo >/dev/null; then
  print -u2 "perf: chiudi Bubo prima di misurare"
  exit 1
fi

out=.build/perf/$(date +%Y-%m-%d-%H%M%S)
readings=$out/letture
# Stessa cartella di check.sh: il permesso di Accessibilità del runner dei UI test è legato al suo percorso.
derived=.build/DerivedData
mkdir -p "$readings"

reading() { # id, motivo: una riga non misurata
  jq -n --arg id "$1" --arg note "$2" '{id: $id, note: $note}' > "$readings/$1.json"
}

xcodegen generate --quiet
xcodebuild -project Bubo.xcodeproj -scheme BuboPerf -destination "platform=macOS,arch=arm64" -derivedDataPath "$derived" -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= -quiet build-for-testing
xcrun swiftc -swift-version 6 -O -o "$out/perf-report" \
  BuboPerfTests/PerfBudgets.swift BuboPerfTests/PerfMeasurement.swift BuboPerfTests/FrameLog.swift scripts/perf/*.swift

if (( cold )); then
  app=("$derived"/Build/Products/Release/Bubo.app)
  start=$(perl -MTime::HiRes=time -e 'printf "%.6f", time')
  logStart=$(date '+%Y-%m-%d %H:%M:%S')
  open -n "$app"
  sleep 5
  /usr/bin/log show --start "$logStart" --signpost --style ndjson \
    --predicate 'subsystem == "com.mgiuditta.bubo" AND signpostName == "HUD interattivo"' > "$out/avvio.ndjson"
  "$out/perf-report" launch-time "$start" "$out/avvio.ndjson" > "$readings/avvio-freddo.json"
  osascript -e 'tell application id "com.mgiuditta.bubo" to quit' || true
  sleep 2
else
  reading avvio-freddo "Solo con --freddo, subito dopo un riavvio"
fi

logStart=$(date '+%Y-%m-%d %H:%M:%S')
tests=ok
TEST_RUNNER_BUBO_METAL_HUD=1 TEST_RUNNER_BUBO_LIVE=$live \
  xcodebuild -project Bubo.xcodeproj -scheme BuboPerf -destination "platform=macOS,arch=arm64" -derivedDataPath "$derived" -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= -resultBundlePath "$out/BuboPerf.xcresult" -quiet test-without-building || tests=falliti

xcrun xcresulttool export attachments --path "$out/BuboPerf.xcresult" --output-path "$out/allegati" >/dev/null
jq -r '.[].attachments[] | select(.suggestedHumanReadableName | startswith("perf-")) | .exportedFileName' \
  "$out/allegati/manifest.json" | while read -r file; do
  cp "$out/allegati/$file" "$readings/test-$file"
done

/usr/bin/log show --start "$logStart" --style ndjson --predicate 'subsystem == "com.apple.metal.hud" AND process == "Bubo"' \
  | jq -r '.eventMessage // empty' > "$out/metal-hud.txt"
"$out/perf-report" metal-hud "$out/metal-hud.txt" > "$readings/orb-tempo-gpu.json"

reading sessione-pronta "Non ancora automatizzata: segnali Apertura Sessione → Sessione pronta in Instruments"
reading ripresa-sessione "La sospensione delle Sessioni non c'è ancora (spec 25, passo 7)"
reading memoria-10-sessioni "Serve Bubo con 10 Sessioni aperte: footprint a mano"
reading cpu-10-sessioni "Serve Bubo con 10 Sessioni aperte: top a mano"
reading memoria-ponte "bubo-agent parte al primo uso: footprint a mano con una Sessione aperta"
reading totale-10-sessioni "Serve Bubo con 10 Sessioni aperte: footprint a mano"
reading memoria-10-sessioni-sospese "La sospensione delle Sessioni non c'è ancora (spec 25, passo 7)"
reading galassia-ferma "La Galassia non c'è ancora (#119)"
(( live )) || reading intervallo-main-thread "Solo con --live: apre una Sessione vera"

verdict=0
gate=()
(( ci )) && gate=(--ci)
"$out/perf-report" report "$readings" "$out" "${gate[@]}" || verdict=$?
print "\nperf: report in $out/report.md, test $tests"
if [[ $tests != ok ]] && (( ci )); then
  failed=$(xcrun xcresulttool get test-results tests --path "$out/BuboPerf.xcresult" \
    | jq -r '[.. | objects | select(.nodeType? == "Test Case" and .result? == "Failed") | .name] | unique | join(", ")') || true
  print "::error title=Prestazioni::Test falliti: ${failed:-vedi BuboPerf.xcresult nell'artefatto prestazioni}"
fi
[[ $tests == ok ]] || exit 1
exit $verdict
