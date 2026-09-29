# Design system di Bubo

Direzione **Notte** (vedi ADR 0004). Confronto vivo: `reference/direzioni.html`. Solo scuro.

## Principio

Il contenitore è acromatico; il colore è dell'**Orb**. Una vista non usa mai una tinta per dire «selezionato» o «importante»: usa luminosità, peso, bordo. Le eccezioni sono tre ruoli semantici (segnale, successo, pericolo) e i punti che richiamano la **Tinta** di un fornitore.

## Colore

| Ruolo | Token | Valore | Uso |
|---|---|---|---|
| Fondo | `ink` | `#0A0B0D` | dietro tutto |
| Vetro | `surface` | `#E8ECF2` @ 3,5% | pannelli (sopra: Liquid Glass di sistema quando c'è) |
| Filo | `line` | `#E2E8F0` @ 9% | bordi |
| Filo forte | `lineStrong` | `#E2E8F0` @ 24% | focus, selezione, anelli HUD |
| Testo | `textPrimary` | `#ECEEF1` | |
| Testo secondario | `textSecondary` | `#8E939B` | etichette (≥ 4,5:1 su `ink`) |
| Testo debole | `textFaint` | `#5A5F66` | suggerimenti, disabilitato; mai testo da leggere |
| Selezione | `accent` | = `textPrimary` | pulsante primario pieno, voce attiva; testo sopra in `ink` |
| Segnale (Lume) | `attention` | `#D6F26B` | solo «Attende te» e Richieste di permesso |
| Successo | `success` | `#7FC8A0` | aggiunte, verifiche passate |
| Pericolo | `danger` | `#F2555A` | errori, rimozioni, Livello di rischio 4–5 |
| Tinta | per fornitore | vedi Tinte | Orb, pallino accanto al nome del fornitore; mai sul contenitore |

Regole: niente gradienti di marca, niente alone colorato dietro i pannelli (l'unico alone è quello dell'Orb, nella sua Tinta). Il fondo può riprendere la Tinta attiva al massimo al 6%, in un solo radiale attorno all'Orb.

## Tipografia

- Interfaccia: SF Pro (sistema), dimensioni dinamiche di macOS. Titoli in semibold con tracking leggermente negativo.
- Dati, etichette in maiuscolo, costi, durate: SF Mono, cifre tabulari.
- Il logotipo BUBO resta l'unico punto con un carattere display; da definire con il marchio.

## Forma e materiale

- Raggi: 8 (controlli), 14 (pannelli), capsula per prompt e chip. Niente raggi enormi ovunque.
- Vetro: Liquid Glass di macOS 26 per pannelli dell'HUD e Panel; nessuna ombra colorata.
- Filo di 1 px come separatore principale; ombre solo per l'elevazione del Panel.

## Movimento

- Il contenitore si muove poco e in fretta (150–250 ms); l'Orb è l'unica cosa che respira.
- `prefers-reduced-motion` / Riduci movimento: anelli fermi, Morph in dissolvenza.

## Da fare

- Aggiornare `Bubo/Design/Palette.swift` e i punti che usano `accent` come tinta (HUDBackground, HUDHeader, HUDRings, OrbPlaceholder).
- `reference/bubo.html` è ancora nella palette vecchia: la struttura resta di riferimento, i colori no.
- Marchio e logotipo.
