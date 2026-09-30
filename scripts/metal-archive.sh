#!/bin/zsh
# Archivio binario Metal 4 delle Forme: una pipeline per Forma (function constant FORMA), compilata
# da metal-tt a build time, così l'app non compila le pipeline a runtime.
# Uso: metal-archive.sh <default.metallib> <Orb.metal> <archivio in uscita>
# Le Forme si leggono dai `case N:` di forma() in Orb.metal; lo 0 è il Blob.
# Le pipeline qui descritte devono combaciare con OrbPipelines.makeDescriptor(for:).
set -euo pipefail

metallib=${1:A}
source=$2
archive=$3
script=${DERIVED_FILE_DIR:-${TMPDIR:-/tmp}}/orb-pipelines.$$.mtl4-json
trap 'rm -f "$script"' EXIT

formas=(0 ${(f)"$(sed -nE 's/^[[:space:]]*case ([0-9]+):.*/\1/p' "$source")"})

specialized=() pipelines=()
for forma in $formas; do
  specialized+=("{\"label\":\"fragment-$forma\",\"function_descriptor\":\"fnd:fragment\",\"constant_values\":[{\"id_type\":\"FunctionConstantIndex\",\"id\":{\"data\":0},\"value_type\":\"ConstantInt\",\"value\":{\"data\":$forma}}]}")
  pipelines+=("{\"vertex_function_descriptor\":\"fnd:vertex\",\"fragment_function_descriptor\":\"fnd:fragment-$forma\",\"color_attachments\":[{\"pixel_format\":\"BGRA8Unorm\",\"blending_state\":\"Enabled\",\"destination_alpha_blend_factor\":\"OneMinusSourceAlpha\",\"destination_rgb_blend_factor\":\"OneMinusSourceAlpha\"}]}")
done

cat > "$script" <<EOF
{
  "version": {"major": 0, "minor": 1, "sub_minor": 0},
  "generator": "MetalFramework",
  "libraries": [{"label": "orb", "path": "$metallib"}],
  "function_descriptors": {
    "library_function_descriptors": [
      {"label": "vertex", "name": "orbVertex", "library": "orb"},
      {"label": "fragment", "name": "orbFragment", "library": "orb"}
    ],
    "specialized_function_descriptors": [${(j:,:)specialized}]
  },
  "pipeline_descriptors": {"render_pipeline_descriptors": [${(j:,:)pipelines}]}
}
EOF

xcrun metal-tt -gpu-family apple7 "$script" -o "$archive"
