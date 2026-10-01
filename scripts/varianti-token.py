#!/usr/bin/env python3
"""Stima i token di ogni rosa del router a due passaggi (#381) contro il contesto di Apple Foundation Models.

Conta `nome: descrizione` per riga da `docs/catalogo-elenco.json`, a 4 caratteri per token
(e, per prudenza, a 3,3 come la stima di #394 per l'italiano). Solo libreria standard.
Uso: python3 scripts/varianti-token.py
Esce con 1 se una rosa supera il budget utile senza preordinamento.

Deciso nella notte, reversibile: contesto 4.096 token, margine 1.200 per istruzioni di sistema,
schema della generazione guidata, richiesta e risposta; budget utile 2.896 token per la rosa.
"""
import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTESTO = 4096
MARGINE = 1200
BUDGET = CONTESTO - MARGINE
CARATTERI_PER_TOKEN = 4.0
CARATTERI_PER_TOKEN_PRUDENTE = 3.3


def token(caratteri, per_token=CARATTERI_PER_TOKEN):
    return round(caratteri / per_token)


def riga(nome, descrizione):
    return f"{nome}: {descrizione}\n"


def main():
    elenco = json.loads((ROOT / "docs/catalogo-elenco.json").read_text(encoding="utf-8"))
    varianti = [v for b in elenco["blocchi"] for v in b["varianti"]]
    gruppi = {(g["categoria"], g["nome"]): g["descrizione"] for g in elenco["gruppi"]}

    per_categoria, per_rosa = defaultdict(list), defaultdict(list)
    for v in varianti:
        testo = riga(v["nome"], v["descrizione"])
        per_categoria[v["categoria"]].append(testo)
        chiave = f"{v['categoria']}/{v['gruppo']}" if v.get("gruppo") else v["categoria"]
        per_rosa[chiave].append(testo)

    oltre = []

    print(f"Budget utile per rosa: {CONTESTO} - {MARGINE} = {BUDGET} token "
          f"({CARATTERI_PER_TOKEN:g} caratteri per token; tra parentesi a {CARATTERI_PER_TOKEN_PRUDENTE:g})\n")
    print("Categoria intera, se non fosse divisa in gruppi")
    for cat, righe in sorted(per_categoria.items(), key=lambda x: -sum(map(len, x[1]))):
        car = sum(map(len, righe))
        stato = "oltre il budget" if token(car) > BUDGET else "ok"
        print(f"  {cat:<9} {len(righe):>3} voci {car:>6} car {token(car):>5} tok "
              f"({token(car, CARATTERI_PER_TOKEN_PRUDENTE):>5}) {stato}")

    print("\nSecondo passaggio: rose effettive (Categorie e gruppi)")
    for chiave, righe in sorted(per_rosa.items(), key=lambda x: -sum(map(len, x[1]))):
        car = sum(map(len, righe))
        tok, tok_prudente = token(car), token(car, CARATTERI_PER_TOKEN_PRUDENTE)
        stato = "oltre il budget: preordinare" if tok > BUDGET else "ok"
        if tok > BUDGET:
            oltre.append(chiave)
        print(f"  {chiave:<22} {len(righe):>3} voci {car:>6} car {tok:>5} tok ({tok_prudente:>5}) "
              f"{100 * tok / BUDGET:4.0f}% del budget  {stato}")

    # Primo passaggio: le 9 Categorie senza gruppi e i 9 gruppi, ciascuno con una descrizione.
    # Le Categorie senza gruppi oggi non hanno una descrizione nell'elenco: si stima con la lunghezza
    # media delle descrizioni dei gruppi (deciso nella notte, reversibile).
    media = sum(len(d) for d in gruppi.values()) / len(gruppi)
    scelte = [riga(f"{c}/{g}", d) for (c, g), d in gruppi.items()]
    con_gruppi = {c for c, _ in gruppi}
    scelte += [riga(c, "x" * round(media)) for c in per_categoria if c not in con_gruppi]
    car = sum(map(len, scelte))
    print(f"\nPrimo passaggio: {len(scelte)} scelte con descrizione, {car} car, {token(car)} tok "
          f"({token(car, CARATTERI_PER_TOKEN_PRUDENTE)}), {100 * token(car) / BUDGET:.0f}% del budget")

    tutto = sum(len(riga(v["nome"], v["descrizione"])) for v in varianti)
    print(f"Un solo passaggio con tutte le {len(varianti)} voci: {tutto} car, {token(tutto)} tok "
          f"({token(tutto, CARATTERI_PER_TOKEN_PRUDENTE)}): non entra in {CONTESTO}")

    if oltre:
        print("\nDa preordinare: " + ", ".join(oltre), file=sys.stderr)
        sys.exit(1)
    print("\nNessuna rosa supera il budget: il preordinamento non serve con l'elenco di oggi.")


if __name__ == "__main__":
    main()
