#!/bin/zsh
# Regenerates docs/media/bubo-orb.gif: renders the Orb off screen with the app's own shaders and motion
# code, then encodes the GIF. Needs Xcode (xcrun metal, swiftc) and ffmpeg; no window, no permissions.
# Usage: docs/media/orb-demo/render.sh
set -euo pipefail
cd "${0:A:h}/../../.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# KEEP_FRAMES=<dir> copies the PNG frames there too, to look at single frames.

# Every Forma's shader, one file each as the app builds them (ADR 0010).
xcrun metal -O2 Bubo/Orb/Orb.metal Bubo/Orb/Forme/*.metal -o "$work/orb.metallib"

# The app's own motion and color code, plus the demo's script.
xcrun swiftc -O -swift-version 6 -default-isolation MainActor \
  Bubo/Orb/OrbState.swift Bubo/Orb/OrbAnimation.swift Bubo/Orb/OrbUniforms.swift Bubo/Orb/Forma.swift \
  Bubo/Design/Tinta.swift Bubo/Design/Tinte.swift Bubo/Router/Provider.swift \
  docs/media/orb-demo/main.swift -o "$work/orb-demo"

"$work/orb-demo" "$work/orb.metallib" "$work/frames"
if [[ -n ${KEEP_FRAMES:-} ]]; then mkdir -p "$KEEP_FRAMES" && cp "$work"/frames/*.png "$KEEP_FRAMES"; fi

filters="fps=15,scale=800:-1:flags=lanczos"
ffmpeg -loglevel error -y -framerate 25 -i "$work/frames/frame-%04d.png" \
  -vf "$filters,palettegen=max_colors=64:stats_mode=diff" "$work/palette.png"
ffmpeg -loglevel error -y -framerate 25 -i "$work/frames/frame-%04d.png" -i "$work/palette.png" \
  -lavfi "${filters}"'[x];[x][1:v]'"paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  -loop 0 docs/media/bubo-orb.gif
ls -lh docs/media/bubo-orb.gif
