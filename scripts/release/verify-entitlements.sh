#!/bin/zsh
# Confronta gli entitlement firmati di ogni eseguibile di Bubo.app con la lista ammessa (spec 27).
# Uso: verify-entitlements.sh [--dev] <Bubo.app>
#   --dev  build locale firmata Apple Development: tollera get-task-allow, che una release non deve avere.
# Un entitlement in più entra solo con un test che mostra il guasto senza: si aggiunge qui, nella lista.
set -euo pipefail

dev=0
[[ ${1:-} == --dev ]] && { dev=1; shift }
app=${1:?uso: verify-entitlements.sh [--dev] <Bubo.app>}
[[ -d $app/Contents/MacOS ]] || { print -u2 "entitlement: $app non è un bundle app"; exit 1 }
team=${BUBO_TEAM_ID:-U38D796ZBJ}

# Percorso nel bundle → entitlement ammessi, in JSON. Gli eseguibili non elencati non devono averne.
typeset -A allowed
# L'App Group dell'app e di BuboQuickLook è la cartella dei Biglietti: senza, l'estensione in sandbox non li legge e
# ogni Consegna in Quick Look ha "mittente sconosciuto" (BuboFileSummaryTests). Senza app-sandbox macOS non carica
# l'estensione Quick Look.
group=$team.com.mgiuditta.bubo
allowed=(
    Contents/MacOS/Bubo "{\"keychain-access-groups\":[\"$group\"],\"com.apple.security.application-groups\":[\"$group\"]}"
    Contents/Helpers/bubo-agent '{"com.apple.security.cs.allow-jit":true}'
    Contents/PlugIns/BuboQuickLook.appex/Contents/MacOS/BuboQuickLook "{\"com.apple.security.app-sandbox\":true,\"com.apple.security.application-groups\":[\"$group\"]}"
)

failures=0
fail() { print -u2 "entitlement: $1"; failures=$((failures + 1)) }

# Tutti i Mach-O del bundle, framework compresi: ognuno va firmato con il runtime rafforzato.
executables=()
while IFS= read -r -d '' file; do
    file -b $file | grep -q 'Mach-O' && executables+=$file
done < <(find $app -type f -perm -u+x -print0)
(( ${#executables} )) || { fail "nessun eseguibile in $app"; exit 1 }

for exe in $executables; do
    relative=${exe#$app/}
    signature=$(codesign -d --verbose=2 $exe 2>&1) || { fail "$relative non firmato"; continue }
    [[ $signature == *'(runtime)'* ]] || fail "$relative senza hardened runtime"

    actual=$(codesign -d --entitlements - --xml $exe 2>/dev/null | plutil -convert json -o - - 2>/dev/null || echo '{}')
    (( dev )) && actual=$(jq -c 'del(.["com.apple.security.get-task-allow"])' <<< $actual)
    expected=${allowed[$relative]:-'{}'}
    if [[ $(jq -S -c . <<< $actual) != $(jq -S -c . <<< $expected) ]]; then
        fail "$relative: firmati $(jq -S -c . <<< $actual), ammessi $(jq -S -c . <<< $expected)"
    fi
done

# Bubo non è in sandbox: nessun servizio XPC, nemmeno quelli di Sparkle (spec 27, fase "Sparkle senza servizi XPC").
while IFS= read -r -d '' service; do
    fail "${service#$app/}: servizio XPC nel bundle"
done < <(find $app -name '*.xpc' -print0)

# Un link simbolico rotto (es. XPCServices del framework di Sparkle) fa fallire codesign --verify --strict.
while IFS= read -r -d '' link; do
    [[ -e $link ]] || fail "${link#$app/}: link simbolico rotto"
done < <(find $app -type l -print0)

for relative in ${(k)allowed}; do
    [[ -f $app/$relative ]] || fail "$relative manca nel bundle"
done

(( failures == 0 )) || { print -u2 "entitlement: $failures problemi"; exit 1 }
echo "entitlement: ok (${#executables} eseguibili)"
