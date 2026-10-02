#!/bin/zsh
# Builds one set of fake Forme the four ways and prints sizes and times as TSV.
# Usage: build.sh <dir made by gen.py> <N>
set -euo pipefail
dir=${1:A} n=$2
cd $dir
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time' }
row() { printf "%s\t%s\t%.3f\t%s\n" "$n" "$1" "$2" "$3" }  # N, what, seconds, bytes

# C: one file per Forma, compiled in parallel as Xcode does (14 cores), then linked.
rm -rf air && mkdir -p air
t0=$(now)
ls perfile/*.metal | xargs -P 14 -I{} sh -c 'xcrun metal -c "$1" -o air/$(basename "$1" .metal).air' _ {}
xcrun metal air/*.air -o perfile.metallib
t1=$(now)
row "C build (parallel)" $(( t1 - t0 )) $(stat -f %z perfile.metallib)
# Incremental: one Forma changed.
t0=$(now)
one=$(ls perfile/*.metal | head -1)
xcrun metal -c $one -o air/$(basename $one .metal).air
xcrun metal air/*.air -o perfile.metallib
t1=$(now)
row "C rebuild one Forma" $(( t1 - t0 )) 0

# A/B: one file, FORMA function constant.
t0=$(now)
xcrun metal -c fc.metal -o fc.air && xcrun metal fc.air -o fc.metallib
t1=$(now)
row "FC build" $(( t1 - t0 )) $(stat -f %z fc.metallib)

# D: one file, runtime index.
t0=$(now)
xcrun metal -c uber.metal -o uber.air && xcrun metal uber.air -o uber.metallib
t1=$(now)
row "D build" $(( t1 - t0 )) $(stat -f %z uber.metallib)

# A: the Metal 4 archive of every pipeline, as scripts/metal-archive.sh does today.
color='"color_attachments":[{"pixel_format":"BGRA8Unorm","blending_state":"Enabled","destination_alpha_blend_factor":"OneMinusSourceAlpha","destination_rgb_blend_factor":"OneMinusSourceAlpha"}]'
specialized=() pipelines=()
if [[ -n ${ARCHIVE_SUBSET:-} ]]; then formas=(${=ARCHIVE_SUBSET}); else formas=({0..$n}); fi
for forma in $formas; do
  specialized+=("{\"label\":\"fragment-$forma\",\"function_descriptor\":\"fnd:fragment\",\"constant_values\":[{\"id_type\":\"FunctionConstantIndex\",\"id\":{\"data\":0},\"value_type\":\"ConstantInt\",\"value\":{\"data\":$forma}}]}")
  pipelines+=("{\"vertex_function_descriptor\":\"fnd:vertex\",\"fragment_function_descriptor\":\"fnd:fragment-$forma\",$color}")
done
cat > fc.mtl4-json <<EOF
{"version":{"major":0,"minor":1,"sub_minor":0},"generator":"MetalFramework",
 "libraries":[{"label":"orb","path":"$dir/fc.metallib"}],
 "function_descriptors":{"library_function_descriptors":[{"label":"vertex","name":"orbVertex","library":"orb"},{"label":"fragment","name":"orbFragment","library":"orb"}],
  "specialized_function_descriptors":[${(j:,:)specialized}]},
 "pipeline_descriptors":{"render_pipeline_descriptors":[${(j:,:)pipelines}]}}
EOF
t0=$(now)
xcrun metal-tt -gpu-family apple7 fc.mtl4-json -o fc.mtl4archive
t1=$(now)
row "A archive (${ARCHIVE_SUBSET:+subset }pipelines)" $(( t1 - t0 )) $(stat -f %z fc.mtl4archive)

# Blob-only archive of the per-file library: what C would keep for a fast first frame.
cat > blob.mtl4-json <<EOF
{"version":{"major":0,"minor":1,"sub_minor":0},"generator":"MetalFramework",
 "libraries":[{"label":"orb","path":"$dir/perfile.metallib"}],
 "function_descriptors":{"library_function_descriptors":[{"label":"vertex","name":"orbVertex","library":"orb"},{"label":"blob","name":"forma_blob","library":"orb"}]},
 "pipeline_descriptors":{"render_pipeline_descriptors":[{"vertex_function_descriptor":"fnd:vertex","fragment_function_descriptor":"fnd:blob",$color}]}}
EOF
t0=$(now)
xcrun metal-tt -gpu-family apple7 blob.mtl4-json -o blob.mtl4archive
t1=$(now)
row "C blob-only archive" $(( t1 - t0 )) $(stat -f %z blob.mtl4archive)

# A': the per-file library with every pipeline archived (to compare with A).
if [[ ${FULL_PERFILE_ARCHIVE:-0} == 1 ]]; then
  fns=() pls=()
  if [[ -n ${PERFILE_SUBSET:-} ]]; then files=(${=PERFILE_SUBSET}); else files=(perfile/*.metal); fi
  for file in $files; do
    name=${file:t:r}; [[ $name == orb ]] && name=blob
    fns+=("{\"label\":\"$name\",\"name\":\"forma_$name\",\"library\":\"orb\"}")
    pls+=("{\"vertex_function_descriptor\":\"fnd:vertex\",\"fragment_function_descriptor\":\"fnd:$name\",$color}")
  done
  cat > all.mtl4-json <<EOF2
{"version":{"major":0,"minor":1,"sub_minor":0},"generator":"MetalFramework",
 "libraries":[{"label":"orb","path":"$dir/perfile.metallib"}],
 "function_descriptors":{"library_function_descriptors":[{"label":"vertex","name":"orbVertex","library":"orb"},${(j:,:)fns}]},
 "pipeline_descriptors":{"render_pipeline_descriptors":[${(j:,:)pls}]}}
EOF2
  t0=$(now)
  xcrun metal-tt -gpu-family apple7 all.mtl4-json -o all.mtl4archive
  t1=$(now)
  row "A' archive per-file (all)" $(( t1 - t0 )) $(stat -f %z all.mtl4archive)
fi

# The Blob alone, archived from a library built from Orb.metal only.
t0=$(now)
xcrun metal perfile/orb.metal -o blobonly.metallib
sed "s|$dir/perfile.metallib|$dir/blobonly.metallib|" blob.mtl4-json > blobonly.mtl4-json
xcrun metal-tt -gpu-family apple7 blobonly.mtl4-json -o blobonly.mtl4archive
t1=$(now)
row "C blob archive from Orb.metal alone" $(( t1 - t0 )) $(stat -f %z blobonly.mtl4archive)
