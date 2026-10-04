#!/bin/zsh
# DMG UDIF UDZO in sola lettura con Bubo.app e il collegamento ad Applicazioni, firmato Developer ID (spec 27).
# Uso: dmg.sh <Bubo.app> <file.dmg>
set -euo pipefail

app=${1:?uso: dmg.sh <Bubo.app> <file.dmg>} dmg=${2:?file.dmg}
identity=${BUBO_SIGN_IDENTITY:-Developer ID Application}
staging=$(mktemp -d)
trap 'rm -rf $staging' EXIT

ditto $app $staging/Bubo.app
ln -s /Applications $staging/Applications
rm -f $dmg
hdiutil create -volname Bubo -srcfolder $staging -fs APFS -format UDZO -ov $dmg >/dev/null
codesign --force --timestamp --sign $identity $dmg
codesign --verify --strict $dmg
echo $dmg
