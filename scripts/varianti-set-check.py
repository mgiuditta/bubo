#!/usr/bin/env python3
"""Controlla il set etichettato con la Variante dell'elenco (#381).

Legge `BuboTests/Fixtures/richieste-varianti.json`, `docs/catalogo-elenco.json` (#377),
il set di #85 (`BuboTests/Fixtures/richieste-etichettate.json`), i Tipi da `RequestType.swift`
e le Categorie da `Categoria.swift`. Solo libreria standard. Uso: python3 scripts/varianti-set-check.py
Esce con 1 se un controllo fallisce.
"""
import json
import re
import sys
import unicodedata
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SET = "BuboTests/Fixtures/richieste-varianti.json"
ELENCO = "docs/catalogo-elenco.json"
SET_85 = "BuboTests/Fixtures/richieste-etichettate.json"
MINIMO_RIGHE = 300
PRIMI_BLOCCHI = 5        # le prime 120 Varianti
MINIMO_PER_VARIANTE = 2
TOLLERANZA_TIPO = 2.0    # punti percentuali di scarto ammessi rispetto a #85


def leggi(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def normalizza(testo):
    """Minuscole, senza accenti, punteggiatura e spazi doppi: due richieste uguali a meno di questo sono doppie."""
    testo = unicodedata.normalize("NFKD", testo.lower())
    testo = "".join(c for c in testo if not unicodedata.combining(c))
    return " ".join(re.sub(r"[^\w\s]", " ", testo).split())


def main():
    errori = []
    fallisci = errori.append

    tipi = re.findall(r'case \w+ = "([^"]+)"', (ROOT / "Bubo/Router/RequestType.swift").read_text())
    riga = re.search(r"^\s*case (.+)$", (ROOT / "Bubo/Catalogo/Categoria.swift").read_text(), re.M)
    categorie = {c.strip() for c in riga.group(1).split(",")} if riga else set()
    if len(tipi) != 10:
        fallisci(f"{len(tipi)} Tipi letti da RequestType.swift, attesi 10")

    elenco = leggi(ELENCO)
    varianti = [v for b in elenco["blocchi"] for v in b["varianti"]]
    categoria_di = {v["nome"]: v["categoria"] for v in varianti}
    primi = [v["nome"] for b in elenco["blocchi"][:PRIMI_BLOCCHI] for v in b["varianti"]]
    esempi = {normalizza(t) for v in varianti for t in v["esempi"].values()}

    dati = leggi(SET)
    richieste = dati["richieste"]
    if dati.get("tipi") != tipi:
        fallisci("`tipi` del set diversi da RequestType.swift")
    if len(richieste) < MINIMO_RIGHE:
        fallisci(f"{len(richieste)} richieste, almeno {MINIMO_RIGHE}")

    ids, testi = set(), {}
    for r in richieste:
        rid = r.get("id", "?")
        if not re.fullmatch(r"v\d{3}", rid) or rid in ids:
            fallisci(f"{rid}: id non valido o doppio")
        ids.add(rid)
        if r.get("lingua") != "it":
            fallisci(f"{rid}: lingua {r.get('lingua')}, attesa it")
        testo = r.get("testo", "")
        chiave = normalizza(testo)
        if not chiave:
            fallisci(f"{rid}: testo vuoto")
        elif chiave in testi:
            fallisci(f"{rid}: stessa richiesta di {testi[chiave]}")
        testi.setdefault(chiave, rid)
        if chiave in esempi:
            fallisci(f"{rid}: copia un esempio dell'elenco, che serve a misurare")
        if r.get("tipo") not in tipi:
            fallisci(f"{rid}: Tipo sconosciuto {r.get('tipo')}")
        if r.get("categoria") not in categorie:
            fallisci(f"{rid}: Categoria sconosciuta {r.get('categoria')}")
        variante = r.get("variante")
        if variante not in categoria_di:
            fallisci(f"{rid}: Variante fuori dall'elenco {variante}")
        elif categoria_di[variante] != r.get("categoria"):
            fallisci(f"{rid}: {variante} è di {categoria_di[variante]}, non di {r.get('categoria')}")
        seconda = r.get("seconda")
        if seconda is not None and (seconda not in categoria_di or seconda == variante):
            fallisci(f"{rid}: seconda Variante non valida {seconda}")
        allegati = r.get("allegati")
        if allegati is not None and (not isinstance(allegati, list) or not all(a.strip() for a in allegati)):
            fallisci(f"{rid}: allegati non validi")

    per_variante = Counter(r.get("variante") for r in richieste)
    for nome in primi:
        if per_variante[nome] < MINIMO_PER_VARIANTE:
            fallisci(f"{nome}: {per_variante[nome]} righe, almeno {MINIMO_PER_VARIANTE} (blocchi 1–{PRIMI_BLOCCHI})")

    # Copertura per Categoria.
    print("Copertura per Categoria (righe · Varianti coperte / totali · prime 120 coperte / totali)")
    righe_cat = Counter(r.get("categoria") for r in richieste)
    for cat in sorted(categorie, key=lambda c: -righe_cat[c]):
        tutte = [n for n, c in categoria_di.items() if c == cat]
        coperte = sum(1 for n in tutte if per_variante[n])
        prime = [n for n in primi if categoria_di[n] == cat]
        prime_ok = sum(1 for n in prime if per_variante[n] >= MINIMO_PER_VARIANTE)
        print(f"  {cat:<9} {righe_cat[cat]:>4} · {coperte:>3}/{len(tutte):<3} · {prime_ok:>2}/{len(prime)}")
    ambigue = sum(1 for r in richieste if r.get("seconda"))
    print(f"  totale    {len(richieste):>4} righe, {len(per_variante)} Varianti usate, {ambigue} con seconda Variante")

    # Distribuzione per Tipo contro #85.
    set85 = leggi(SET_85)["richieste"]
    tipo85, tipo = Counter(r["tipo"] for r in set85), Counter(r.get("tipo") for r in richieste)
    print("\nDistribuzione per Tipo (questo set · #85)")
    for t in tipi:
        qui, la = 100 * tipo[t] / len(richieste), 100 * tipo85[t] / len(set85)
        segno = "" if abs(qui - la) <= TOLLERANZA_TIPO else "  <- fuori tolleranza"
        print(f"  {t:<28} {tipo[t]:>3} {qui:5.1f}% · {la:5.1f}%{segno}")
        if segno:
            fallisci(f"{t}: {qui:.1f}% contro {la:.1f}% di #85, scarto oltre {TOLLERANZA_TIPO} punti")

    if errori:
        print("\n" + "\n".join(errori), file=sys.stderr)
        sys.exit(1)
    print(f"\nvarianti: ok ({len(richieste)} richieste)")


if __name__ == "__main__":
    main()
