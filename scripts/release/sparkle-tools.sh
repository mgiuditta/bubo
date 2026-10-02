#!/bin/zsh
# Strumenti di Sparkle (generate_appcast, sign_update) della versione fissata, verificati con SHA-256.
# Uso: sparkle-tools.sh <cartella>   stampa la cartella bin/
set -euo pipefail

version=2.10.0
sha256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
directory=${1:?uso: sparkle-tools.sh <cartella>}

if [[ ! -x $directory/bin/generate_appcast ]]; then
    mkdir -p $directory
    archive=$directory/Sparkle-$version.tar.xz
    curl -sSfL -o $archive https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz
    [[ $(shasum -a 256 $archive | cut -d' ' -f1) == $sha256 ]] \
        || { print -u2 "sparkle: SHA-256 di Sparkle-$version.tar.xz diverso da quello fissato"; exit 1 }
    tar -xf $archive -C $directory
fi
echo $directory/bin
