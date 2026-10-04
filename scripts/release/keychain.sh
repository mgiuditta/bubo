#!/bin/zsh
# Portachiavi temporaneo del CI con il certificato Developer ID Application (spec 27).
# Uso: keychain.sh create   (legge DEVELOPER_ID_P12_BASE64 e DEVELOPER_ID_P12_PASSWORD)
#      keychain.sh delete
set -euo pipefail

keychain=${RUNNER_TEMP:?serve RUNNER_TEMP}/bubo-release.keychain-db
case ${1:-} in
create)
    : ${DEVELOPER_ID_P12_BASE64:?segreto mancante} ${DEVELOPER_ID_P12_PASSWORD:?segreto mancante}
    password=$(uuidgen)
    certificate=$RUNNER_TEMP/developer-id.p12
    print -rn -- $DEVELOPER_ID_P12_BASE64 | base64 --decode > $certificate
    security create-keychain -p $password $keychain
    security set-keychain-settings -lut 21600 $keychain
    security unlock-keychain -p $password $keychain
    security import $certificate -k $keychain -P $DEVELOPER_ID_P12_PASSWORD -T /usr/bin/codesign -T /usr/bin/security
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k $password $keychain >/dev/null
    security list-keychains -d user -s $keychain $(security list-keychains -d user | tr -d '"')
    rm -f $certificate
    security find-identity -v -p codesigning $keychain | grep -q 'Developer ID Application' \
        || { print -u2 "keychain: nessuna identità Developer ID Application nel .p12"; exit 1 }
    ;;
delete)
    security delete-keychain $keychain 2>/dev/null || true
    ;;
*)
    print -u2 "uso: keychain.sh create|delete"; exit 2
    ;;
esac
