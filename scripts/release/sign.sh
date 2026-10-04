#!/bin/zsh
# Firma Developer ID dall'interno verso l'esterno, senza --deep (spec 27): prima ogni eseguibile annidato
# con i suoi entitlement, poi l'app con i propri (profilo compreso), infine la verifica.
# Uso: sign.sh <Bubo.app>
set -euo pipefail
cd "${0:A:h}/../.."

app=${1:?uso: sign.sh <Bubo.app>}
identity=${BUBO_SIGN_IDENTITY:-Developer ID Application}
sign=(codesign --force --timestamp --options runtime --sign $identity)

# Entitlement dei figli; gli eseguibili e i bundle non elencati tengono quelli che ha messo l'export (l'estensione
# Quick Look: sandbox e App Group). "nessuno" toglie quelli della firma originale: Autoupdate di Sparkle arriva con
# com.apple.application-identifier, che senza un profilo non gli serve (#595).
typeset -A entitlements
entitlements=(
    Contents/Helpers/bubo-agent bridge/entitlements.plist
    Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate nessuno
)

# Codice annidato (eseguibili e bundle), dal più profondo: il contenuto di un bundle prima del bundle.
nested=()
while IFS= read -r -d '' item; do
    if [[ -d $item ]] || { [[ $item != $app/Contents/MacOS/Bubo ]] && file -b $item | grep -q 'Mach-O' }; then
        nested+=$item
    fi
done < <(find $app/Contents \( -type d \( -name '*.app' -o -name '*.framework' -o -name '*.xpc' -o -name '*.appex' \) -o -type f -perm -u+x \) -print0)
nested=(${(f)"$(for item in $nested; do print -r -- "${#${(s:/:)item}} $item"; done | sort -rn -s -k1,1 | cut -d' ' -f2-)"})
for item in $nested; do
    relative=${item#$app/}
    if [[ ${entitlements[$relative]:-} == nessuno ]]; then
        $sign $item
    elif [[ -n ${entitlements[$relative]:-} ]]; then
        $sign --entitlements ${entitlements[$relative]} $item
    else
        $sign --preserve-metadata=entitlements $item
    fi
done

# L'app tiene gli entitlement dell'export, che vengono dal profilo Developer ID.
$sign --preserve-metadata=entitlements $app

codesign --verify --strict --verbose=2 $app
for item in $nested; do codesign --verify --strict $item; done
scripts/release/verify-entitlements.sh $app
