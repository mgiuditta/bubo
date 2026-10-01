#!/bin/zsh
# Archivio binario Metal 4 della pipeline del Blob, compilata da metal-tt a build time: il primo
# fotogramma dell'Orb non aspetta il compilatore. Le altre Forme si compilano a runtime alla prima
# richiesta e restano nella cache degli shader di Metal (ADR 0010), così l'archivio non cresce col Catalogo.
# L'archivio ha una libreria sua, Orb.metallib, fatta del solo Orb.metal: metal-tt compila ogni funzione
# della libreria che riceve, e a runtime l'archivio trova la pipeline solo con quella stessa libreria.
# Uso: metal-archive.sh <Orb.metal> <cartella delle risorse>, che riceve Orb.metallib e Orb.mtl4archive.
# La pipeline qui descritta deve combaciare con OrbPipelines.makeDescriptor(for:).
set -euo pipefail

source=$1
resources=${2:A}
metallib=$resources/Orb.metallib
archive=$resources/Orb.mtl4archive
script=${DERIVED_FILE_DIR:-${TMPDIR:-/tmp}}/orb-pipelines.$$.mtl4-json
trap 'rm -f "$script"' EXIT

cat > "$script" <<JSON
{
  "version": {"major": 0, "minor": 1, "sub_minor": 0},
  "generator": "MetalFramework",
  "libraries": [{"label": "orb", "path": "$metallib"}],
  "function_descriptors": {
    "library_function_descriptors": [
      {"label": "vertex", "name": "orbVertex", "library": "orb"},
      {"label": "blob", "name": "forma_blob", "library": "orb"}
    ]
  },
  "pipeline_descriptors": {"render_pipeline_descriptors": [{
    "vertex_function_descriptor": "fnd:vertex",
    "fragment_function_descriptor": "fnd:blob",
    "color_attachments": [{"pixel_format": "BGRA8Unorm", "blending_state": "Enabled",
      "destination_alpha_blend_factor": "OneMinusSourceAlpha", "destination_rgb_blend_factor": "OneMinusSourceAlpha"}]
  }]}
}
JSON

xcrun metal ${MACOSX_DEPLOYMENT_TARGET:+-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET} "$source" -o "$metallib"
xcrun metal-tt -gpu-family apple7 "$script" -o "$archive"
