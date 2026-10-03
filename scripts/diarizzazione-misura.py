#!/usr/bin/env python3
"""Misura la diarizzazione di una Riunione (#549): quanti turni Bubo attribuisce alla voce giusta.

Uso: scripts/diarizzazione-misura.py riferimento.csv "Bubo/Riunioni/2026-10-03 Prova.md"

riferimento.csv, etichettato a mano ascoltando l'audio, una riga per turno nell'ordine della nota:
    0:00:03,Matteo
    0:00:11,Giulia
    0:00:20,Paolo
Il tempo è quello della riga nella nota (**[0:00:11] Parlante 2:**), il nome è chi parlava davvero.

Ogni turno di riferimento si accoppia alla riga della nota con l'orario più vicino (entro 3 s).
Le etichette della nota (Io, Parlante 1, …) si mappano sui nomi veri con l'assegnazione che dà più
turni corretti, una a una. Esce con 0 se almeno l'80% dei turni è corretto, con 1 altrimenti.
"""
import csv
import itertools
import re
import sys

SOGLIA = 0.8
TOLLERANZA = 3


def secondi(orario):
    ore, minuti, sec = (int(parte) for parte in orario.strip().split(":"))
    return ore * 3600 + minuti * 60 + sec


def righe_della_nota(percorso):
    testo = open(percorso, encoding="utf-8").read()
    return [(secondi(orario), etichetta.strip())
            for orario, etichetta in re.findall(r"^\*\*\[(\d+:\d\d:\d\d)\] ([^*]+?):\*\*", testo, re.M)]


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    riferimento = [(secondi(riga[0]), riga[1].strip())
                   for riga in csv.reader(open(sys.argv[1], encoding="utf-8")) if riga and riga[0].strip()]
    nota = righe_della_nota(sys.argv[2])
    if not riferimento or not nota:
        sys.exit("Riferimento o nota senza turni.")

    coppie = []
    for tempo, vero in riferimento:
        vicina = min(nota, key=lambda riga: abs(riga[0] - tempo))
        coppie.append((vero, vicina[1] if abs(vicina[0] - tempo) <= TOLLERANZA else None))

    etichette = sorted({etichetta for _, etichetta in coppie if etichetta})
    nomi = sorted({vero for vero, _ in coppie})
    migliore, mappa = -1, {}
    # Poche voci in una Riunione: provare tutte le assegnazioni basta.
    for scelta in itertools.permutations(nomi + [None] * len(etichette), len(etichette)):
        prova = dict(zip(etichette, scelta))
        giusti = sum(1 for vero, etichetta in coppie if etichetta and prova[etichetta] == vero)
        if giusti > migliore:
            migliore, mappa = giusti, prova

    quota = migliore / len(coppie)
    for etichetta, nome in mappa.items():
        print(f"{etichetta} → {nome or '(nessuno)'}")
    senza = sum(1 for _, etichetta in coppie if etichetta is None)
    if senza:
        print(f"{senza} turni senza una riga della nota entro {TOLLERANZA} s")
    print(f"Turni corretti: {migliore}/{len(coppie)} ({quota:.0%}), soglia {SOGLIA:.0%}")
    sys.exit(0 if quota >= SOGLIA else 1)


if __name__ == "__main__":
    main()
