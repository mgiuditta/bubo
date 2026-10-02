#!/bin/zsh
# Appcast di una release (spec 27, #223): delta verso le 3 versioni precedenti del Canale, note per lingua
# da CHANGELOG, canale beta, gradualità di 1 giorno sulla stabile, critico se c'è Sicurezza, URL riscritti
# per tag, feed firmato EdDSA dopo lo stapling, pubblicazione su Pages e controllo di ogni URL.
# Uso: appcast.sh <file.dmg graffato> <tag>
# Legge SPARKLE_ED_PRIVATE_KEY e GH_TOKEN (scrittura su RELEASES_REPO).
set -euo pipefail
cd "${0:A:h}/../.."

dmg=${1:?uso: appcast.sh <file.dmg> <tag>} tag=${2:?tag}
name=${tag#v}
repo=${RELEASES_REPO:-mgiuditta/bubo-releases}
pages=${PAGES_URL:-https://${repo%%/*}.github.io/${repo#*/}}
prefix=https://github.com/$repo/releases/download
: ${SPARKLE_ED_PRIVATE_KEY:?segreto mancante} ${GH_TOKEN:?segreto mancante}
[[ $(basename $dmg) == Bubo-$name.dmg ]] || { print -u2 "appcast: il DMG deve chiamarsi Bubo-$name.dmg"; exit 1 }

work=$(mktemp -d)
trap 'rm -rf $work' EXIT
tools=$(scripts/release/sparkle-tools.sh $work/sparkle)
archives=$work/archives
mkdir -p $archives
git clone --quiet --depth 1 --branch gh-pages https://x-access-token:$GH_TOKEN@github.com/$repo.git $work/pages \
    || { print -u2 "appcast: manca il ramo gh-pages di $repo (#220)"; exit 1 }
[[ -f $work/pages/appcast.xml ]] && cp $work/pages/appcast.xml $archives/appcast.xml

channel=stable
[[ $name == *-beta.* ]] && channel=beta

# Le 3 versioni precedenti del Canale, per i delta; le loro note restano nell'appcast.
cp $dmg $archives/
bun scripts/release/appcast.ts previous $archives/appcast.xml $channel 3 | while IFS= read -r url; do
    file=${url:t}
    curl -sSfL -o $archives/$file $url
    previous=${${file#Bubo-}%.dmg}
    bun scripts/release/appcast.ts notes $previous $archives Bubo-$previous >/dev/null
done

flags=(--maximum-deltas 3 --maximum-versions 0 --embed-release-notes)
critical=$(bun scripts/release/appcast.ts notes $name $archives Bubo-$name)
[[ $critical == critical ]] && flags+=(--critical-update-version '')
if [[ $channel == beta ]]; then flags+=(--channel beta); else flags+=(--phased-rollout-interval 86400); fi

print -rn -- $SPARKLE_ED_PRIVATE_KEY | $tools/generate_appcast --ed-key-file - $flags \
    --download-url-prefix $prefix/__TAG__/ --release-notes-url-prefix $pages/notes/ \
    -o $archives/appcast.xml $archives
bun scripts/release/appcast.ts urls $archives/appcast.xml $prefix
print -rn -- $SPARKLE_ED_PRIVATE_KEY | $tools/sign_update --ed-key-file - $archives/appcast.xml

# I delta della nuova versione vanno nella sua release.
deltas=($(grep -oE "$prefix/$tag/[^\"]+\\.delta" $archives/appcast.xml | sort -u))
for url in $deltas; do
    gh release upload $tag $archives/${url:t} --repo $repo --clobber
done

mkdir -p $work/pages/notes
cp $archives/appcast.xml $work/pages/appcast.xml
for notes in $archives/Bubo-*.??.md(N); do cp $notes $work/pages/notes/; done
git -C $work/pages add appcast.xml notes
git -C $work/pages -c user.name='Bubo release' -c user.email='release@users.noreply.github.com' \
    commit --quiet -m "Appcast: $tag"
git -C $work/pages push --quiet origin gh-pages

# Pages impiega qualche minuto: si aspetta il feed nuovo, poi si controlla ogni URL.
for attempt in {1..40}; do
    curl -sSfL $pages/appcast.xml 2>/dev/null | cmp -s - $archives/appcast.xml && break
    (( attempt == 40 )) && { print -u2 "appcast: $pages/appcast.xml non aggiornato dopo 10 minuti"; exit 1 }
    sleep 15
done
bun scripts/release/appcast.ts check $archives/appcast.xml
