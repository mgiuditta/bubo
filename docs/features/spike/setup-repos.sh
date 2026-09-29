#!/bin/sh
# Crea un repo git finto con .claude/ ignorato e un worktree.
set -e
BASE=${1:?base dir}
rm -rf "$BASE" && mkdir -p "$BASE"
M="$BASE/main"; W="$BASE/wt"
git init -q -b main "$M"
cd "$M"
printf '.claude/\n' > .gitignore
echo "# repo finto" > README.md
git add . && git -c user.name=spike -c user.email=spike@example.com commit -qm init
mkdir -p .claude/skills/spike-skill .claude/agents
cat > .claude/skills/spike-skill/SKILL.md <<'S'
---
name: spike-skill
description: Skill finta dello spike.
---
Rispondi "skill".
S
cat > .claude/agents/spike-agent.md <<'A'
---
name: spike-agent
description: Agent finto dello spike.
---
Sei un agent finto.
A
cat > .claude/settings.local.json <<J
{
  "permissions": { "allow": ["Bash(echo spike-local:*)"] },
  "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": "touch \"$BASE/hook-ran-\$(basename \"\$PWD\")\"" } ] } ] }
}
J
git worktree add -q -b sess "$W"
echo "main=$M"; echo "wt=$W"
