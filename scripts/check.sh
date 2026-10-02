#!/bin/zsh
# Verifica completa: progetto rigenerato, build Debug, test (anche audit di accessibilità), controlli della rifinitura, build Release con warning come errori, entitlement e velocità del ponte.
set -euo pipefail
cd "${0:A:h}/.."

derived=.build/DerivedData
# Set etichettato del router coerente con il Catalogo e con Categoria.swift (#85).
bun scripts/richieste-check.ts
xcodegen generate --quiet
xcodebuild -project Bubo.xcodeproj -scheme Bubo -configuration Debug -destination "platform=macOS,arch=arm64" -derivedDataPath "$derived" -skipPackagePluginValidation -allowProvisioningUpdates -quiet build
xcodebuild -project Bubo.xcodeproj -scheme Bubo -configuration Debug -destination "platform=macOS,arch=arm64" -derivedDataPath "$derived" -skipPackagePluginValidation -allowProvisioningUpdates -quiet test
scripts/polish-check.sh "$derived"
# Formato .bubo e HPKE a pezzi (spec 24), anche con le due chiavi nel Secure Enclave se il Mac lo ha.
swift test --package-path Packages/DeliveryKit --quiet
xcodebuild -project Bubo.xcodeproj -scheme Bubo -configuration Release -destination "platform=macOS,arch=arm64" -derivedDataPath "$derived" -skipPackagePluginValidation -allowProvisioningUpdates -quiet build
# Ponte stretto e veloce: entitlement firmati uguali alla lista, carico di prova firmato entro 2× (spec 27).
scripts/release/verify-entitlements.sh --dev "$derived/Build/Products/Release/Bubo.app"
scripts/release/bridge-speed.sh
# I test di prestazione (UI test, Release) si compilano qui e si eseguono a parte con lo schema BuboPerf.
xcodebuild -project Bubo.xcodeproj -scheme BuboPerf -destination "platform=macOS,arch=arm64" -derivedDataPath "$derived" -skipPackagePluginValidation -allowProvisioningUpdates -quiet build-for-testing
echo "check: ok"
