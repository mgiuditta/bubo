#!/bin/zsh
# Verifica completa: progetto rigenerato, build Debug, Swift Testing, build Release con warning come errori.
set -euo pipefail
cd "${0:A:h}/.."

derived=.build/DerivedData
xcodegen generate --quiet
xcodebuild -project Bubo.xcodeproj -scheme Bubo -configuration Debug -destination "platform=macOS,arch=arm64" -derivedDataPath "$derived" -allowProvisioningUpdates -quiet build
xcodebuild -project Bubo.xcodeproj -scheme Bubo -configuration Debug -destination "platform=macOS,arch=arm64" -derivedDataPath "$derived" -allowProvisioningUpdates -quiet test
xcodebuild -project Bubo.xcodeproj -scheme Bubo -configuration Release -destination "platform=macOS,arch=arm64" -derivedDataPath "$derived" -allowProvisioningUpdates -quiet build
echo "check: ok"
