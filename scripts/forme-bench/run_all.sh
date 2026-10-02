#!/bin/zsh
# Le misure dell'ADR 0010 con Forme finte: dimensioni e tempi di build (build.sh), primo Morph,
# memoria e GPU (bench.swift) per le alternative A, B, C, D, a ogni N.
# Uso: scripts/forme-bench/run_all.sh [N...]   (default 13 50 200 500; uscita in $FORME_BENCH_DIR)
# Serve spazio: a 200 Forme l'archivio di A pesa circa 1,8 GB; da 200 in su si archivia un campione.
# Ogni giro usa semi nuovi, così la cache degli shader di Metal è fredda per il primo Morph.
set -euo pipefail
here=${0:A:h}
out=${FORME_BENCH_DIR:-${TMPDIR:-/tmp}/forme-bench}
mkdir -p $out
swiftc -O $here/bench.swift -o $out/bench 2>/dev/null
cd $out
salt=${SALT:-$RANDOM}
for n in ${@:-13 50 200 500}; do
  dir=n$n
  rm -rf $dir
  seed=$(( n * 7 + salt )); python3 $here/gen.py $dir $n $seed >/dev/null
  echo "## N=$n build"
  subset="" psubset=""
  if (( n >= 200 )); then subset="0 ${(j: :)$(seq 1 $(( n / 20 )) $n)}"; fi
  if (( n >= 500 )); then psubset="$dir/perfile/orb.metal ${(j: :)$(ls $dir/perfile/fake*.metal | awk 'NR % 25 == 1')}"; fi
  ARCHIVE_SUBSET=$subset PERFILE_SUBSET=$psubset FULL_PERFILE_ARCHIVE=1 $here/build.sh $dir $n
  [[ -n $subset ]] && echo "(A archived $(( ${#${=subset}} )) of $(( n + 1 )) pipelines)"
  [[ -n $psubset ]] && echo "(A' archived $(( ${#${=psubset}} )) of $(( n + 1 )) pipelines)"
  picks=(${(f)"$(python3 -c "import random; r=random.Random($n); print('\n'.join(str(i) for i in r.sample(range(1, $n + 1), 5)))")"})
  fns=(); for i in $picks; do fns+=(forma_fake${seed}_$(( i - 1 ))); done
  echo "## N=$n C cold (per-function, never compiled)"
  ./bench compile $dir/perfile.metallib $fns
  echo "## N=$n C warm (second launch, system shader cache)"
  ./bench compile $dir/perfile.metallib $fns
  echo "## N=$n C with the Blob from its own small library + archive (fresh forme)"
  fns2=(); for i in $picks; do fns2+=(forma_fake${seed}_$(( i % n ))); done
  ./bench blobarchive $dir/perfile.metallib $dir/blobonly.metallib $dir/blobonly.mtl4archive $fns2
  echo "## N=$n B cold (FORMA function constant, runtime)"
  ./bench fc $dir/fc.metallib $picks
  echo "## N=$n A (archive)"
  apicks=($picks); [[ -n $subset ]] && apicks=(${${=subset}[2,6]})
  ./bench archive $dir/fc.metallib $dir/fc.mtl4archive $apicks
  echo "## N=$n GPU C (forma ${fns[1]})"
  ./bench gpu $dir/perfile.metallib ${fns[1]} 0 700
  echo "## N=$n GPU B/A (FORMA ${picks[1]})"
  ./bench gpu $dir/fc.metallib orbFragment 0 700 ${picks[1]}
  echo "## N=$n GPU D (uber, index ${picks[1]})"
  ./bench gpu $dir/uber.metallib orbFragment ${picks[1]} 700
  echo "## N=$n D warm second launch"
  ./bench gpu $dir/uber.metallib orbFragment ${picks[1]} 130
  echo "## N=$n app size"
  du -sk $dir/*.metallib $dir/*.mtl4archive
  rm -f $dir/fc.mtl4archive $dir/all.mtl4archive
done
