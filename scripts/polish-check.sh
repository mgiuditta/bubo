#!/bin/zsh
# Controlli automatici della rifinitura (spec 27). Va lanciato dopo la build Debug di check.sh,
# perché legge le stringhe estratte dal compilatore (.stringsdata) in DerivedData.
set -euo pipefail
cd "${0:A:h}/.."

derived=${1:-.build/DerivedData}
catalog=Bubo/Resources/Localizable.xcstrings
failures=0
fail() { print -u2 "polish: $1"; failures=$((failures + 1)) }

# 1. Il build non modifica il String Catalog: le stringhe del codice sono tutte dentro, nessuna è stale.
objects=$derived/Build/Intermediates.noindex/Bubo.build/Debug/Bubo.build/Objects-normal/arm64
stringsdata=()
for file in $objects/*.stringsdata(N); do
    # Un file sorgente cancellato lascia il suo .stringsdata in DerivedData: si salta.
    [[ -f $(jq -r .source $file) ]] && stringsdata+=$file
done
(( ${#stringsdata} )) || { fail "nessun .stringsdata in $objects: prima la build Debug"; exit 1 }
work=$(mktemp -d)
trap 'rm -rf $work' EXIT
cp $catalog $work/Localizable.xcstrings
xcrun xcstringstool sync $work/Localizable.xcstrings --stringsdata $stringsdata >/dev/null
if ! diff -q <(jq -S . $catalog) <(jq -S . $work/Localizable.xcstrings) >/dev/null; then
    fail "$catalog non è allineato al codice; aprilo in Xcode dopo una build. Differenze:"
    diff <(jq -S . $catalog) <(jq -S . $work/Localizable.xcstrings) >&2 || true
fi

# 2. Ogni lingua di ogni String Catalog ha tutte le voci tradotte, niente "da rivedere".
# Anche i cataloghi dell'app iPhone e della sua estensione delle notifiche (#505).
catalogs=(Bubo/**/*.xcstrings BuboRemote/*.xcstrings RemoteNotificationService/*.xcstrings)
languages=($(jq -r '.sourceLanguage as $source | .strings[].localizations // {} | keys[] | select(. != $source)' $catalogs | sort -u))
for file in $catalogs; do
    for language in $languages; do
        jq -r --arg l $language '.strings | to_entries[]
            | select(.value.shouldTranslate != false)
            | select(.value.localizations[$l].stringUnit.state != "translated"
                     and .value.localizations[$l].variations == null)
            | .key' $file | while IFS= read -r key; do
            fail "$file: \"$key\" non tradotta in $language"
        done
    done
done

# 3. L'icona ha tutte e 10 le misure, ciascuna con i pixel giusti; il glifo della barra dei menu è
# un'immagine modello a 1× e 2× (18 e 36 px).
glyph=Bubo/Resources/Assets.xcassets/MenuBarGlyph.imageset
[[ $(jq -r '.properties["template-rendering-intent"]' $glyph/Contents.json) == template ]] \
    || fail "$glyph non è un'immagine modello"
for scale in 1 2; do
    name=$(jq -r --arg s "${scale}x" '.images[] | select(.scale == $s) | .filename // empty' $glyph/Contents.json)
    actual=$(sips -g pixelWidth $glyph/${name:-assente} 2>/dev/null | awk '/pixelWidth/ { print $2 }')
    [[ $actual == $(( 18 * scale )) ]] || fail "$glyph a ${scale}× è ${actual:-assente} px, servono $(( 18 * scale ))"
done
icon=Bubo/Resources/Assets.xcassets/AppIcon.appiconset
(( $(jq '[.images[] | select(.filename != null)] | length' $icon/Contents.json) == 10 )) \
    || fail "$icon non ha 10 immagini"
jq -r '.images[] | select(.filename != null) | "\(.filename) \(.size) \(.scale)"' $icon/Contents.json |
    while read -r name size scale; do
        expected=$(( ${size%%x*} * ${scale%x} ))
        actual=$(sips -g pixelWidth $icon/$name 2>/dev/null | awk '/pixelWidth/ { print $2 }')
        [[ $actual == $expected ]] || fail "$icon/$name è ${actual:-assente} px, servono $expected"
    done

# 4. Nessun ProgressView fuori da Design/LoadingLabel, che dopo 1 s mostra un testo.
grep -rn --include='*.swift' '\bProgressView\b' Bubo | grep -v '^Bubo/Design/LoadingLabel.swift:' |
    while IFS= read -r line; do fail "ProgressView fuori da LoadingLabel: $line"; done

# 5. Nessuna durata o curva di animazione scritta a mano fuori dai token di Design/Motion.
# .linear solo come curva ((.linear), .linear, value:, .linear(duration:)): è anche la fonte Linear delle issue.
pattern='\.(easeIn|easeOut|easeInOut|spring|interpolatingSpring|bouncy|snappy|smooth|timingCurve)\b|\.linear([[:space:]]*\)|[[:space:]]*,[[:space:]]*value:|\(duration)|\b(duration|response|dampingFraction|bounce|blendDuration|delay)[[:space:]]*[:=][[:space:]]*[0-9.]'
grep -rnE --include='*.swift' $pattern Bubo | grep -v '^Bubo/Design/' |
    while IFS= read -r line; do fail "animazione fuori da Design/Motion: $line"; done

(( failures == 0 )) || { print -u2 "polish: $failures problemi"; exit 1 }
echo "polish: ok"
