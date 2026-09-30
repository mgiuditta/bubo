#!/bin/zsh
# Verifica completa: progetto rigenerato, build Debug, test (anche audit di accessibilità), controlli della rifinitura, build Release con warning come errori.
set -euo pipefail
cd "${0:A:h}/.."

derived=.build/DerivedData
xcodegen generate --quiet
xcodebuild -project Bubo.xcodeproj -scheme Bubo -configuration Debug -destination "platform=macOS,arch=arm64" -derivedDataPath "$derived" -quiet build
xcodebuild -project Bubo.xcodeproj -scheme Bubo -configuration Debug -destination "platform=macOS,arch=arm64" -derivedDataPath "$derived" -quiet test
scripts/polish-check.sh "$derived"
xcodebuild -project Bubo.xcodeproj -scheme Bubo -configuration Release -destination "platform=macOS,arch=arm64" -derivedDataPath "$derived" -quiet build
echo "check: ok"
