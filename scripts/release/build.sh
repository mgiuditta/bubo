#!/bin/zsh
# Archivio Release e export Developer ID di Bubo.app (spec 27). Solo arm64 (ADR 0001).
# Uso: build.sh <versione X.Y.Z> <numero di build> <cartella di uscita>
# Legge ASC_API_KEY_PATH, ASC_API_KEY_ID, ASC_API_ISSUER_ID: l'export crea da sé il profilo (project.yml).
set -euo pipefail
cd "${0:A:h}/../.."

version=${1:?versione} build=${2:?numero di build} out=${3:?cartella di uscita}
team=${BUBO_TEAM_ID:-U38D796ZBJ}
auth=(-allowProvisioningUpdates
      -authenticationKeyPath ${ASC_API_KEY_PATH:?} -authenticationKeyID ${ASC_API_KEY_ID:?} -authenticationKeyIssuerID ${ASC_API_ISSUER_ID:?})
mkdir -p $out

xcodegen generate --quiet
xcodebuild -project Bubo.xcodeproj -scheme Bubo -configuration Release \
    -destination 'generic/platform=macOS' -archivePath $out/Bubo.xcarchive \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO MARKETING_VERSION=$version CURRENT_PROJECT_VERSION=$build \
    $auth -quiet archive

cat > $out/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>developer-id</string>
	<key>signingStyle</key><string>automatic</string>
	<key>teamID</key><string>$team</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath $out/Bubo.xcarchive -exportPath $out/export \
    -exportOptionsPlist $out/ExportOptions.plist $auth -quiet

app=$out/export/Bubo.app
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $app/Contents/Info.plist) == $version ]] \
    || { print -u2 "build: CFBundleShortVersionString diverso da $version"; exit 1 }
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' $app/Contents/Info.plist) == $build ]] \
    || { print -u2 "build: CFBundleVersion diverso da $build"; exit 1 }
echo $app
