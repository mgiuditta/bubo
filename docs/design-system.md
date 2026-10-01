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

### Tinte

Una per fornitore, non per modello; valori in `Bubo/Design/Tinte.swift`. Il carattere (punte, grana, bande, lucido) è il secondo segnale dopo il colore: sulle Forme le punte sono smorzate a 0,28, quindi nessun fornitore si firma solo con le punte. L'Orb sfuma verso la nuova Tinta in 1,2 s (smoothstep); con Riduci movimento, dissolvenza 0,4 s.

| Fornitore | Colore | Carattere |
|---|---|---|
| Anthropic | `#D97757` | bande morbide |
| Mistral | `#E0A040` | punte leggere, bande |
| DeepSeek | `#8DB548` | grana fine |
| OpenAI | `#3FAE8F` | vetroso, lucido |
| Perplexity | `#36A9C0` | grana e lucido |
| Google | `#4F7FE0` | bande fitte |
| Meta | `#6A62DE` | grana media |
| Alibaba | `#9A66DD` | bande e lucido |
| Cohere | `#D07FB0` | opaco, morbido |
| xAI | `#C8CCD4` | argento freddo: lucido alto, grana leggera, punte |
| Fuori elenco | `#9C918A` | grigio caldo neutro, opaco, senza carattere |

Regole: niente gradienti di marca, niente alone colorato dietro i pannelli (l'unico alone è quello dell'Orb, nella sua Tinta). Il fondo può riprendere la Tinta attiva al massimo al 6%, in un solo radiale attorno all'Orb.

## Tipografia

- Interfaccia: SF Pro (sistema), dimensioni dinamiche di macOS. Titoli in semibold con tracking leggermente negativo.
- Dati, etichette in maiuscolo, costi, durate: SF Mono, cifre tabulari.
- Il logotipo BUBO resta l'unico punto con un carattere display; da definire con il marchio.

## Marchio e logotipo (provvisorio)

Proposta provvisoria e sostituibile ([#228](https://github.com/mgiuditta/bubo/issues/228)), in attesa di un lavoro di design vero.

- **Segno**: l'Orb a riposo che diventa gufo reale (*Bubo bubo*): disco con due ciuffi spinti in fuori, la V del disco facciale tra loro, occhi grandi e un becco piccolo. Nessun riferimento a marchi altrui.
- **Colore**: acromatico come il contenitore. Gufo color luna (da `#F6F7F9` a `textSecondary`, con il volume dell'Orb) su squircle in grafite (da `#1C1F24` a `ink`), filo chiaro sul bordo e un anello dell'HUD attorno al gufo. Le sfumature sono solo di luminosità, per il volume: niente Tinte, Lume o gradienti di marca, il colore resta dell'Orb e dei segnali.
- **Icona**: griglia macOS, tela 1024 con corpo squircle di 824 (superellisse n = 5) e ombra nel margine. Sorgente `design/brand/app-icon.svg`.
- **Glifo della barra dei menu**: la stessa sagoma monocroma in 18 pt, occhi e becco forati, immagine modello (`MenuBarGlyph`, 1× e 2×). Sorgente `design/brand/menu-bar-glyph.svg`; a 1× gli occhi sono allineati ai pixel e il becco è solo un accenno.
- **Rigenerare**: `swift scripts/brand-icons.swift` riscrive le 10 PNG di `AppIcon.appiconset` e le 2 del glifo; `polish-check.sh` controlla misure e modello.
- **Logotipo**: ancora da fare.

## Forma e materiale

- Raggi: 8 (controlli), 14 (pannelli), capsula per prompt e chip. Niente raggi enormi ovunque.
- Vetro: Liquid Glass di macOS 26 per pannelli dell'HUD e Panel; nessuna ombra colorata.
- Filo di 1 px come separatore principale; ombre solo per l'elevazione del Panel.

## Movimento

- Il contenitore si muove poco e in fretta (150–250 ms); l'Orb è l'unica cosa che respira.
- `prefers-reduced-motion` / Riduci movimento: anelli fermi, Morph in dissolvenza.

## Nel codice

- I token sono in `Bubo/Design/Palette.swift`; `PaletteTests` controlla il contrasto AA di ogni testo su `ink` e su `surface`.
- **Solo scuro**: l'HUD forza lo schema scuro (fogli compresi) e dà ai controlli `tint(Palette.accent)`, quindi pulsante predefinito, pieno, segmentati e interruttori sono color luna con testo in `ink`; Galassia, Visore e Terminale hanno `darkAqua`.
- **Anteprima**: la pagina web è dell'utente, non di Bubo. Incorporata nell'HUD o staccata, riceve lo schema del sistema (`prefers-color-scheme`), non quello scuro forzato dell'HUD.
- L'Orb segnaposto dell'HUD e il radiale del fondo prendono la Tinta del fornitore attivo; il segno accanto a BUBO è color luna.
- `reference/bubo.html` è superato nei colori (lo dice in testa): la struttura resta di riferimento.

## Da fare

- La selezione delle liste di sistema (per esempio i file della Galassia) e gli anelli di focus restano nell'accento di sistema: `tint` non li cambia, servirebbe una selezione disegnata da Bubo.
- Marchio definitivo e logotipo (ora c'è la proposta provvisoria sopra).
