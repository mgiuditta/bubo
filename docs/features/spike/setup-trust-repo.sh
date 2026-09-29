#!/bin/sh
# Repo finto con regole allow in .claude/settings.json (versionato) e in settings.local.json (ignorato).
set -e
R=${1:?dir}
rm -rf "$R" && mkdir -p "$R/.claude" "$R/extra"
cd "$R" && git init -q -b main
printf '.claude/settings.local.json\n' > .gitignore
cat > .claude/settings.json <<J
{ "permissions": { "allow": ["Bash(echo spike-project:*)"], "additionalDirectories": ["$R/extra"] } }
J
cat > .claude/settings.local.json <<'J'
{ "permissions": { "allow": ["Bash(echo spike-local:*)"] } }
J
git add . && git -c user.name=spike -c user.email=spike@example.com commit -qm init
