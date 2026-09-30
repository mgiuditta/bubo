#!/bin/zsh
# Verifica completa: progetto rigenerato, build Debug, Swift Testing, build Release con warning come errori.
set -euo pipefail
cd "${0:A:h}/.."

derived=.build/DerivedData
xcodegen generate --quiet
xcodebuild -project Bubo.xcodeproj -scheme Bubo -configuration Debug -destination "platform=macOS,arch=arm64" -derivedDataPath "$derived" -quiet build
xcodebuild -project Bubo.xcodeproj -scheme Bubo -configuration Debug -destination "platform=macOS,arch=arm64" -derivedDataPath "$derived" -quiet test
xcodebuild -project Bubo.xcodeproj -scheme Bubo -configuration Release -destination "platform=macOS,arch=arm64" -derivedDataPath "$derived" -quiet build
# I test di prestazione (UI test, Release) si compilano qui e si eseguono a parte con lo schema BuboPerf.
xcodebuild -project Bubo.xcodeproj -scheme BuboPerf -destination "platform=macOS,arch=arm64" -derivedDataPath "$derived" -quiet build-for-testing
echo "check: ok"
