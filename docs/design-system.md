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

Brand kit (#690): cinque ruoli, tutti con le dimensioni dinamiche di macOS. Le viste nuove usano solo questi token (`Bubo/Design/Typography.swift`).

| Ruolo | Token | Carattere | Misura | Uso |
|---|---|---|---|---|
| Display | `Font.buboDisplay` | Newsreader Medium | 34 (`relativeTo: .largeTitle`) | logotipo, casa vuota («Chiedi al tuo cervello»), titoli delle note |
| Titolo | `Font.buboTitle` | SF Pro semibold | 22 (`.title`) | titolo della conversazione; con `buboTitleStyle()` prende il tracking −0,2 |
| Corpo | `Font.buboBody` | SF Pro | 15 (`.title3`) | testo della conversazione |
| Interfaccia | `Font.buboInterface` | SF Pro | 13 (`.body`) | controlli ed etichette |
| Dati | `Font.buboData` | SF Mono, cifre tabulari | 12 (`.callout`) | costi, durate, etichette in maiuscolo |

- Newsreader è un serif da taccuino: dice «note e memoria», ed è l'unico carattere display. Sta in `Bubo/Resources/Fonts/` (OFL) e lo registra il sistema con `ATSApplicationFontsPath`.
- La conversazione si legge al massimo a 720 pt di larghezza (`Spacing.readingWidth`).
- Unbounded, Manrope e JetBrains Mono (le funzioni di `Typography`) restano nelle viste di prima finché la finestra nuova non le sostituisce.

## Spaziatura

Token `Spacing` (`Bubo/Design/Spacing.swift`): `xxs 4 · xs 8 · s 12 · m 16 · l 24 · xl 32 · xxl 48`.

- Le viste nuove non usano numeri a mano.
- Righe della barra laterale alte almeno 36 pt (`Spacing.sidebarRowMinHeight`); margini dei pannelli `m` dentro, `l` fuori.
- I token di prima (`xxSmall`…) restano per le viste esistenti.

## Marchio e logotipo (provvisorio)

Proposta provvisoria e sostituibile ([#228](https://github.com/mgiuditta/bubo/issues/228)), in attesa di un lavoro di design vero.

- **Segno**: l'Orb a riposo che diventa gufo reale (*Bubo bubo*): disco con due ciuffi spinti in fuori, la V del disco facciale tra loro, occhi grandi e un becco piccolo. Nessun riferimento a marchi altrui.
- **Colore**: acromatico come il contenitore. Gufo color luna (da `#F6F7F9` a `textSecondary`, con il volume dell'Orb) su squircle in grafite (da `#1C1F24` a `ink`), filo chiaro sul bordo e un anello dell'HUD attorno al gufo. Le sfumature sono solo di luminosità, per il volume: niente Tinte, Lume o gradienti di marca, il colore resta dell'Orb e dei segnali.
- **Icona**: griglia macOS, tela 1024 con corpo squircle di 824 (superellisse n = 5) e ombra nel margine. Sorgente `design/brand/app-icon.svg`.
- **Glifo della barra dei menu**: la stessa sagoma monocroma in 18 pt, occhi e becco forati, immagine modello (`MenuBarGlyph`, 1× e 2×). Sorgente `design/brand/menu-bar-glyph.svg`; a 1× gli occhi sono allineati ai pixel e il becco è solo un accenno.
- **Rigenerare**: `swift scripts/brand-icons.swift` riscrive le 10 PNG di `AppIcon.appiconset` e le 2 del glifo; `polish-check.sh` controlla misure e modello.
- **Logotipo**: `bubo` minuscolo in Newsreader Medium, in tracciati, con la sagoma del gufo a sinistra alta quanto la x e poggiata sulla linea di base; color luna (`textPrimary`). Sorgente `design/brand/logotype.svg`, rigenerato da `swift scripts/brand-logotype.swift`.
- **Pagina del brand kit**: `reference/brand.html` (logotipo, costruzione, colore, tipografia, spaziatura, tono, componenti della finestra).
- **Pulsante di vetro**: `GlassCapsuleButton`, capsula Liquid Glass alta 32 pt con icona ed etichetta, per azioni quiete come Impostazioni.

## Finestra

ADR 0013. Due colonne (`NavigationSplitView`): barra laterale in vetro di sistema, a destra la conversazione.

- **Barra laterale**: Cervello, Neuroni, Riunioni; poi le Conversazioni per giorno (Oggi, Ieri, Questa settimana, Prima); poi i Progetti e Lavoro. Righe alte almeno 36 pt. Una Sessione ha il nome del Progetto in una capsula con filo `line` e, solo in «Attende te», il pallino Lume.
- **Impostazioni**: `GlassCapsuleButton` in basso a sinistra.
- **Composer**: larghezza massima `Spacing.readingWidth`. Nel composer di una Sessione il chip del Progetto (capsula con filo `lineStrong`) sta dentro la capsula del campo; nel Cervello nessun chip, perché è il destinatario predefinito.
- **Casa vuota**: Orb a 360 pt senza anelli, «Chiedi al tuo cervello» in `Font.buboDisplay`, tre suggerimenti in capsule con filo `line` presi dalle note cambiate per ultime.

## Forma e materiale

- Raggi: 8 (controlli), 14 (pannelli), capsula per prompt e chip. Niente raggi enormi ovunque.
- Vetro: Liquid Glass di macOS 26 per pannelli dell'HUD e Panel; nessuna ombra colorata.
- Filo di 1 px come separatore principale; ombre solo per l'elevazione del Panel.

## Movimento

- Il contenitore si muove poco e in fretta (150–250 ms); l'Orb è l'unica cosa che respira.
- Le finestre di Bubo (Panel, Bolla, pillola, HUD, Palette) entrano ed escono in dissolvenza di 0,25 s (`Motion.windowFade`, `NSWindow.orderFrontFading`/`orderOutFading`): l'uscita aspetta la dissolvenza, così la transizione della Bolla e della pillola si vede.
- La Bolla cresce dall'Orb e ci rientra; quando la Domanda passa all'HUD cresce oltre la sua misura e svanisce mentre l'HUD entra.
- I numeri che cambiano (costi, quote) scorrono con `contentTransition(.numericText())`.
- `prefers-reduced-motion` / Riduci movimento: anelli fermi, Morph in dissolvenza, finestre che appaiono e spariscono subito, Bolla senza scala.

## Nel codice

- I token sono in `Bubo/Design/Palette.swift`; `PaletteContrastTests` controlla il contrasto AA di ogni testo su `ink`, su `surface` e sul foglio di sistema (`#212527`).
- **Solo scuro**: l'HUD forza lo schema scuro (fogli compresi); HUD, Agenti e Impostazioni danno ai controlli `tint(Palette.accent)`, quindi pulsante predefinito, pieno e segmentati sono color luna con testo in `ink`. Gli interruttori e le caselle hanno `tint(Palette.switchTrack)` (= `textSecondary`): su una traccia color luna il pomello bianco di sistema sparirebbe. Galassia, Visore, Cronologia, Palette ⌘K e Terminale staccato hanno `darkAqua`.
- **Anteprima**: la pagina web è dell'utente, non di Bubo. Incorporata nell'HUD o staccata, riceve lo schema del sistema (`prefers-color-scheme`), non quello scuro forzato dell'HUD: lo legge da `AppleInterfaceStyle` e da `AppleInterfaceThemeChangedNotification`, non da `NSApp`, che lo schema forzato può cambiare.
- L'Orb dell'HUD e il radiale del fondo prendono la Tinta del fornitore attivo; il segno accanto a BUBO è color luna (`markLight`, `markDark`).
- Neuroni: unica vista con un colore per categoria, la cartella in cima della nota. Otto toni smorzati, nessuno vicino a Lume, successo o pericolo, e le note fuori dalle cartelle in `textSecondary` (`NeuronRenderer.folderColors`); il colore non dice mai «selezionato»: la nota scelta e quelle citate hanno un anello color luna, e l'elenco accanto ripete la cartella in testo.
- Visore: parole chiave in grassetto, commenti in corsivo, stringhe e commenti in `textSecondary`; niente `success`, che è delle aggiunte.
- `reference/bubo.html` è superato nei colori (lo dice in testa): la struttura resta di riferimento.

## Da fare

- Restano nell'accento di sistema, perché `tint` non li cambia: la selezione delle liste (i file della Galassia), gli anelli di focus, la scheda scelta nella barra delle Impostazioni e i link. Servirebbe una selezione disegnata da Bubo.
- Marchio definitivo: l'icona resta la proposta provvisoria (#228); il logotipo c'è.
