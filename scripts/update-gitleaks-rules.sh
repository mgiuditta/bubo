#!/bin/zsh
# Rifà le regole dello scanner dei segreti della Consegna (spec 24, Scanner) dal file di gitleaks, licenza MIT
# (Copyright (c) 2019 Zachary Rice). Versione fissata qui sotto e annotata nel JSON: per aggiornarla, cambia
# `version`, rilancia lo script e i test di SecretScannerTests. Le regole solo sui percorsi non servono: si tolgono.
set -euo pipefail
cd "${0:A:h}/.."
version=v8.30.1
work=$(mktemp -d)
trap 'rm -rf $work' EXIT
curl -sSfL -o $work/gitleaks.toml https://raw.githubusercontent.com/gitleaks/gitleaks/$version/config/gitleaks.toml
curl -sSfL -o $work/LICENSE https://raw.githubusercontent.com/gitleaks/gitleaks/$version/LICENSE
python3 - $work/gitleaks.toml $version $work/LICENSE > Bubo/Resources/RegoleGitleaks.json <<'EOF'
import json, sys, tomllib

config = tomllib.load(open(sys.argv[1], "rb"))

def allowlist(entry):
    # Le liste legate ai percorsi in AND non valgono mai sul testo di una Sessione; in OR resta il resto.
    if entry.get("paths") and entry.get("condition", "OR") == "AND":
        return None
    return {"regexTarget": entry.get("regexTarget", "secret"),
            "regexes": entry.get("regexes", []),
            "stopwords": entry.get("stopwords", [])}

rules = []
for rule in config["rules"]:
    if "regex" not in rule:
        continue
    lists = [a for a in map(allowlist, rule.get("allowlists", [])) if a]
    rules.append({"id": rule["id"], "regex": rule["regex"], "secretGroup": rule.get("secretGroup", 0),
                  "entropy": rule.get("entropy", 0), "keywords": rule.get("keywords", []), "allowlists": lists})

json.dump({"source": "https://github.com/gitleaks/gitleaks/blob/%s/config/gitleaks.toml" % sys.argv[2],
           "version": sys.argv[2],
           "license": open(sys.argv[3]).read(),
           "allowlist": {"regexTarget": "secret", "regexes": config["allowlist"].get("regexes", []),
                         "stopwords": config["allowlist"].get("stopwords", [])},
           "rules": rules}, sys.stdout, indent=1, ensure_ascii=False)
print()
EOF
print "RegoleGitleaks.json: $(jq '.rules | length' Bubo/Resources/RegoleGitleaks.json) regole di gitleaks $version"
