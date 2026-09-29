#!/bin/bash
# Misura git worktree add, cp -Rc (clonefile per file) e clonefile(2) sull'intera cartella,
# su un repo finto con ~1 GB di dipendenze ignorate.
# Uso: bench-worktree.sh <sorgente-repo-reale> <base-dir-scratch> [ripetizioni]
# Dal repo reale si LEGGONO solo i file versionati (git archive) e node_modules (cp -Rc).
set -euo pipefail
export LC_ALL=C
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${1:?repo sorgente}; BASE=${2:?base}; N=${3:-3}
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
dt() { perl -e "printf '%.2f', $2-$1"; }
rm -rf "$BASE" && mkdir -p "$BASE/main"
git -C "$SRC" archive HEAD | tar -x -C "$BASE/main"
cd "$BASE/main"
grep -qx 'node_modules' .gitignore 2>/dev/null || echo node_modules >> .gitignore
git init -q -b main && git add -A && git -c user.name=b -c user.email=b@e.com commit -qm init
t=$(now); cp -Rc "$SRC/node_modules" node_modules; echo "setup: cp -Rc dal repo reale $(dt $t $(now)) s"
echo "file versionati: $(git ls-files | wc -l | tr -d ' ')"
echo "node_modules: $(du -sh node_modules | cut -f1), $(find node_modules -type f | wc -l | tr -d ' ') file, $(find node_modules | wc -l | tr -d ' ') voci"
for i in $(seq 1 "$N"); do
  W="$BASE/wt-$i"
  t0=$(now); git worktree add -q -b "s-$i" "$W"; t1=$(now)
  cp -Rc node_modules "$W/node_modules"; t2=$(now)
  python3 "$HERE/clonefile.py" node_modules "$W/node_modules-cf"; t3=$(now)
  echo "run $i: worktree add $(dt $t0 $t1) s | cp -Rc $(dt $t1 $t2) s | clonefile(2) cartella $(dt $t2 $t3) s"
done
echo "spazio libero dopo le copie: $(df -h "$BASE" | tail -1 | awk '{print $4}')"
t=$(now); for i in $(seq 1 "$N"); do git worktree remove --force "$BASE/wt-$i"; done
echo "git worktree remove --force x$N: $(dt $t $(now)) s"
cd / && rm -rf "$BASE"
echo "pulito"
