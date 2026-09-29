#!/bin/zsh
# Rigenera Bubo.xcodeproj da project.yml e lo apre in Xcode.
set -euo pipefail
cd "${0:A:h}/.."
xcodegen generate --quiet
open Bubo.xcodeproj
