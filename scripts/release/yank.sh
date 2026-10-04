#!/bin/zsh
# Ritira una versione (spec 27): voce tolta dall'appcast, feed rifirmato, release marcata "ritirata",
# DMG tenuto per chi lo scarica a mano. Solo in avanti: poi esce una correzione con numero più alto.
# Uso: yank.sh <tag>   (legge SPARKLE_ED_PRIVATE_KEY e GH_TOKEN)
set -euo pipefail
cd "${0:A:h}/../.."

tag=${1:?uso: yank.sh <tag>}
[[ $tag =~ '^v[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$' ]] || { print -u2 "yank: tag $tag fuori formato"; exit 1 }
repo=${RELEASES_REPO:-mgiuditta/bubo-releases}
pages=${PAGES_URL:-https://${repo%%/*}.github.io/${repo#*/}}
: ${SPARKLE_ED_PRIVATE_KEY:?segreto mancante} ${GH_TOKEN:?segreto mancante}

work=$(mktemp -d)
trap 'rm -rf $work' EXIT
tools=$(scripts/release/sparkle-tools.sh $work/sparkle)
git clone --quiet --depth 1 --branch gh-pages https://x-access-token:$GH_TOKEN@github.com/$repo.git $work/pages
feed=$work/pages/appcast.xml

bun scripts/release/appcast.ts yank $feed $tag
print -rn -- $SPARKLE_ED_PRIVATE_KEY | $tools/sign_update --ed-key-file - $feed
git -C $work/pages -c user.name='Bubo release' -c user.email='release@users.noreply.github.com' \
    commit --quiet -am "Ritirata: $tag"
git -C $work/pages push --quiet origin gh-pages
gh release edit $tag --repo $repo --title "Bubo ${tag#v} (ritirata)"

for attempt in {1..40}; do
    curl -sSfL $pages/appcast.xml 2>/dev/null | cmp -s - $feed && break
    (( attempt == 40 )) && { print -u2 "yank: $pages/appcast.xml non aggiornato dopo 10 minuti"; exit 1 }
    sleep 15
done
bun scripts/release/appcast.ts check $feed
echo "yank: $tag ritirata"
