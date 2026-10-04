#!/bin/zsh
# Notarizza il solo DMG, stampa il log anche se riesce, graffa e verifica (spec 27).
# Uso: notarize.sh <file.dmg>   (legge ASC_API_KEY_PATH, ASC_API_KEY_ID, ASC_API_ISSUER_ID)
# Rifiuto o oltre 30 minuti: uscita diversa da zero, così il workflow non pubblica niente.
set -euo pipefail

dmg=${1:?uso: notarize.sh <file.dmg>}
auth=(--key ${ASC_API_KEY_PATH:?} --key-id ${ASC_API_KEY_ID:?} --issuer ${ASC_API_ISSUER_ID:?})

result=$(xcrun notarytool submit $dmg $auth --wait --timeout 30m --output-format json) || true
print -r -- $result
id=$(jq -r '.id // empty' <<< $result)
notarystatus=$(jq -r '.status // empty' <<< $result)
[[ -n $id ]] || { print -u2 "notarize: invio fallito"; exit 1 }
xcrun notarytool log $id $auth || true
[[ $notarystatus == Accepted ]] || { print -u2 "notarize: esito ${notarystatus:-nessuno}"; exit 1 }

xcrun stapler staple $dmg
xcrun stapler validate $dmg
spctl -a -t open --context context:primary-signature -v $dmg

# L'app montata dal DMG deve risultare "Notarized Developer ID".
mount=$(mktemp -d)
hdiutil attach -nobrowse -readonly -mountpoint $mount $dmg >/dev/null
trap 'hdiutil detach $mount -quiet || true' EXIT
assessment=$(spctl -a -vv $mount/Bubo.app 2>&1)
print -r -- $assessment
[[ $assessment == *'source=Notarized Developer ID'* ]] || { print -u2 "notarize: l'app montata non è Notarized Developer ID"; exit 1 }
