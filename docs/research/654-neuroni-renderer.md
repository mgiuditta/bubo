# Neuroni: quale renderer per il grafo delle note

Ricerca del 2026-10-03 per [#654](https://github.com/mgiuditta/bubo/issues/654), mappa [#648](https://github.com/mgiuditta/bubo/issues/648), decisione [#653](https://github.com/mgiuditta/bubo/issues/653). Sblocca [#658](https://github.com/mgiuditta/bubo/issues/658). Domanda: il renderer Metal della Galassia (`Bubo/Galaxy`) regge un grafo di note da **5.000 nodi e 20.000 archi** a 60 fps su M-series? Che lavoro serve per passare dai file di codice alle note e ai wikilink? E l'alternativa, SwiftUI Canvas 2D con simulazione a forze, fino a quanti nodi regge?

**In sintesi: sì al renderer Metal, no al layout della Galassia.** 20.000 archi e 5.000 nodi come quad istanziati costano **1,6 ms di GPU** su M4 Max a 2880×1800 [M1]. Su un M1 base, con la stessa stima di 5× della spec 11 [S2], fanno circa 8 ms, sotto i 16,7 ms dei 60 fps. Della Galassia si riusano il **renderer** (pipeline, shader del disco e del segmento, blending), la **vista** che disegna solo su richiesta, la **camera** e le **etichette** a tetto. Vanno scritti da zero il **layout** (a forze, al posto del circle packing per cartelle), il **modello** (`GalaxyModel` è legato a Progetto, git, Sessioni e comete) e la **sorgente** (note e link al posto di `git ls-files`). Canvas 2D non regge 20.000 archi: con CoreGraphics, che disegna sulla CPU, servono **2 s per fotogramma** [M2], e un solo `Path` traslucido con molti archi cresce più che quadraticamente [M3].

## Cosa c'è nella Galassia

| Pezzo | File | Riusabile per i Neuroni? |
|---|---|---|
| Renderer: 6 pipeline, quad istanziati (`drawPrimitives(.triangleStrip, vertexCount: 4, instanceCount:)`), blending premoltiplicato | `GalaxyRenderer.swift` [C1] | **Sì**, quasi tutto |
| Shader: `billboard`, `galaxy_disc_fragment` (disco con bordo morbido), `galaxy_segment_vertex/fragment` (linea con alpha da un capo all'altro), `galaxy_ring_fragment` | `Galaxy.metal` [C2] | **Sì** per disco e segmento. `galaxy_star_vertex` e `galaxy_point_vertex` no: il loro livello di dettaglio dipende dal disco centrale della cartella (`coreRadius`, `starsAppear`) |
| Vista: `MTKView` in pausa che disegna solo su un cambiamento, disegno continuo solo durante un'animazione, zero fotogrammi con la finestra coperta | `GalaxyMapNSView.swift` [C3] | **Sì**, così com'è nel principio |
| Camera ortografica con inclinazione 0,82, pan, zoom attorno a un punto, volo con easing | `GalaxyCamera.swift` [C4] | **Sì**. Per un grafo l'inclinazione va tolta (tilt 1) |
| Etichette in un solo `Canvas` SwiftUI sopra la mappa, al massimo 40 | `GalaxyLabels.swift`, `GalaxyModel.labels()` [C5] | **Sì** come schema |
| Layout: circle packing gerarchico per cartelle (front-chain di d3 e Welzl), deterministico, **senza archi** | `GalaxyLayout.swift` [C6] | **No** |
| Modello: Progetto, `git ls-files`, FSEvents, Sessioni, comete, diff, collisioni | `GalaxyModel.swift` (724 righe), `GalaxyFiles.swift` [C7] | **No**, tranne hit test e ricerca come esempio |

Due vincoli del renderer di oggi:

- **Nessun colore per istanza.** Tutto è disegnato in `starlight` (`Palette.textPrimary`) costante nello shader [C2]. I Neuroni chiedono un colore per cartella e una dimensione per numero di collegamenti [#658]: serve un'istanza nuova con colore e raggio, o un indice in una tabella di colori.
- **Gli archi portano le posizioni.** `GalaxySegment` contiene `from`/`to` già calcolati (32 byte) [C1]. Per un grafo il cui layout si muove conviene un buffer delle posizioni dei nodi, con archi come coppie di indici (8 byte) letti nello shader: a ogni passo della simulazione si riscrive solo il buffer dei nodi (5.000 × 8 byte). Anche riscrivere tutto costa poco: 0,006 ms per 20.000 archi e 5.000 nodi [M1].

## Misure

Script usa-e-getta, fuori dal repo. Mac: **M4 Max, macOS 26.7**. Grafo casuale: 5.000 nodi sparsi in un quadrato di 2000 punti, 20.000 archi tra coppie casuali. È un caso peggiore per il riempimento: gli archi casuali attraversano mezzo schermo, mentre quelli di un layout a forze sono corti.

**[M1] Metal, come il renderer della Galassia.** Quad istanziati per i segmenti (larghezza 3,5 px, alpha 0,15) e per i dischi (8 px), stesso blending premoltiplicato di `GalaxyRenderer`, texture fuori schermo 2880×1800 `bgra8Unorm`, 100 fotogrammi dopo 20 di riscaldamento, tempo GPU da `gpuStartTime`/`gpuEndTime`. Buffer riscritti a ogni fotogramma, come con una simulazione in corso.

| Archi | Nodi | GPU mediana | p95 | Riscrittura dei buffer |
|---|---|---|---|---|
| 20.000 | 5.000 | **1,62 ms** | 1,69 ms | 0,006 ms |
| 100.000 | 25.000 | 7,98 ms | 8,47 ms | 0,027 ms |

Il costo è dominato dal riempimento degli archi lunghi, non dal numero di istanze. 5× il bersaglio sta ancora sotto i 16,7 ms su M4 Max. M1 base non misurato: con la stima di 5× della spec 11 [S2], 20.000 archi stanno intorno agli 8 ms.

**[M2] CoreGraphics, un tratto per arco.** Stesso grafo, contesto bitmap 2880×1800: sfondo, 5.000 dischi in un path, poi 20.000 `strokePath()` separati da 1,5 punti, traslucidi. Mediana **2.062 ms** a fotogramma. È 1.000 volte Metal.

**[M3] CoreGraphics, un solo path per tutti gli archi**, il modo naturale di scrivere un `Canvas` (`context.stroke(path)` una volta). Con tratto traslucido il costo esplode: 250 archi 56 ms, 500 archi 266 ms, 1.000 archi **3,1 s**, 2.000 archi **49 s**. 20.000 archi non finiscono in minuti.

**[M4] Un passo di simulazione a forze**, CPU, un core, 5.000 nodi e 20.000 molle:

| Repulsione | Tempo per passo |
|---|---|
| Ingenua, tutte le coppie, O(n²) | 18,2 ms |
| Solo i vicini, con una griglia (stessa classe di costo di Barnes–Hut) | **1,23 ms** |

d3-force usa Barnes–Hut con `theta` 0,9 per la forza fra i nodi [W1]. La sua simulazione si ferma da sola dopo circa **300 passi** (`alphaDecay` predefinito 0,0228 = 1 − 0,001^(1/300)) [W2]. Con la griglia, 300 passi fanno circa 0,4 s fuori dal main thread. La versione ingenua ne richiede 5,5.

**[M5] Lettura e analisi dei link.** Vault sintetico di 5.000 note da ~3 KB in 50 cartelle, 30.000 link (wikilink con alias e `#sezione`, link Markdown relativi con `%20`). Lettura di tutti i file più due `Regex` di Swift, un core: **1,5 s**. Va fatto una volta e poi solo sui file cambiati, con i `FileStamp` che l'Indice già usa [C8].

## SwiftUI Canvas: dove sta il limite

`Canvas` disegna in modalità immediata dentro un `GraphicsContext` [W3]. Senza `drawingGroup()` il contenuto è rasterizzato come quello di CoreGraphics. Con `drawingGroup()` SwiftUI compone la vista in un'immagine fuori schermo prima di mostrarla e la fa disegnare a Metal [W4]. Le misure [M2] e [M3] usano CoreGraphics direttamente, quindi per `Canvas` sono un'approssimazione, non una misura. Il rendering di `Canvas` dentro SwiftUI non è documentato.

Stima dai numeri sopra, con il bilancio di 16,7 ms per fotogramma:

- **Un tratto per arco**: 2 s per 20.000 archi lunghi [M2], cioè circa 0,1 ms per arco. Il bilancio basta per **~150 archi lunghi**, forse qualche centinaio di archi corti dopo il layout.
- **Un solo path traslucido**: già 56 ms con 250 archi [M3]. Da non usare. Archi opachi o un path per colore cambiano i numeri, ma restano sulla CPU.
- **La simulazione** non dipende dal renderer [M4]: con Canvas pesa come con Metal.

Quindi Canvas regge un grafo di **qualche centinaio di nodi e archi**, come un "vicinato locale" attorno a una nota. Non regge le 5.000 note del criterio di #658.

## Cosa serve per cambiare sorgente

1. **Sorgente delle note.** `SecondBrainNotes.files(at:in:excluding:)` elenca già le note `.md`, salta cartelle nascoste e `Bubo/Sessioni/`, e non scarica i segnaposto di iCloud [C8]. Va riusato al posto di `GalaxyFiles.list` (`git ls-files`) [C7]. `FileEvents.batches` (FSEvents) è già usato sia dalla Galassia sia dall'Indice [C7].
2. **Parser dei link** (criterio di #658). I formati di Obsidian sono: `[[Nota]]`, `[[Nota|alias]]`, `[[Nota#Titolo]]`, `[[Nota#^blocco]]`, l'incorporamento `![[Nota]]`, e i link Markdown `[testo](cartella/Nota%20uno.md)` con spazi codificati [W5]. `NoteCitation(wikilink:)` già toglie alias e `#ancora` [C9]: va riusato per il nome. Manca la **risoluzione**: un nome senza percorso va al file con quel nome, e serve una regola per i nomi doppi (il percorso più vicino, come Obsidian). Un link a una nota che non esiste è un nodo "fantasma" o è scartato: da decidere in #658. I link dentro i blocchi di codice vanno ignorati.
3. **Cache dei link** per nota, aggiornata con i `FileStamp`. Può stare nell'SQLite dell'Indice, o in un file accanto alla cache della Galassia (`GalaxyCache`) [C10]. Senza cache servono 1,5 s a ogni apertura [M5].
4. **Layout a forze**, nuovo. Barnes–Hut o una griglia, fuori dal main actor (`@concurrent` come `GalaxyModel.makeLayout`) [C7]. La Galassia rifiuta il layout a forze perché toglie la memoria spaziale ("Nessun layout a forze") [S2]. Per i Neuroni il grafo ha bisogno delle forze, ma la stabilità si salva così:
   - seme deterministico per le posizioni iniziali, per esempio dall'FNV-1a del percorso, che `GalaxyLayout.phase(of:)` già calcola [C6];
   - posizioni salvate in cache per nota;
   - all'apertura, partire dalle posizioni salvate e simulare solo le note nuove, con le altre ferme.
5. **Modello nuovo** (`NeuronModel` o simile): nodi, archi, grado, cartella, selezione, ricerca, "note citate nell'ultima risposta", filtro per cartella. Lo hit test lineare della Galassia (`hit(at:)`, entro 10 punti) [C7] su 5.000 nodi va bene così.
6. **Renderer.** Istanza con colore e raggio. Archi indicizzati, con alpha bassa e più alta per i vicini della nota selezionata. Durante la simulazione si usa il disegno continuo che la vista ha già per i voli (`onAnimation`/`isAnimating`), poi si torna in pausa [C3]. Per la Tinta delle cartelle valgono `docs/design-system.md` e ADR 0004.
7. **Accessibilità.** Come la Galassia: mappa nascosta a VoiceOver, elenco dei nodi accanto (criterio di #658) [C3][C5].

### Condividere o copiare il renderer

Due scelte reversibili:

- **Estrarre** da `Galaxy.metal` le funzioni `billboard`, disco e segmento, ed estrarre da `GalaxyRenderer` la creazione delle pipeline, in un pezzo comune "piano 2D istanziato", con due modelli sopra.
- **Copiare** il renderer in `Bubo/Neuroni` e adattarlo.

Consiglio l'estrazione solo di **shader e camera**, che sono già generici. Il resto del renderer (`rebuild`, `drawActivity`, `drawComets`) è specifico della Galassia, e due casi d'uso non bastano a disegnare un'astrazione.

## Raccomandazione

1. **Metal**, con il renderer e la vista della Galassia come base. Il bersaglio di 5.000 nodi e 20.000 archi usa circa il 10% del bilancio su M4 Max [M1].
2. **Layout a forze nuovo**, con Barnes–Hut o una griglia, fuori dal main thread, deterministico e salvato in cache. Non si riusa `GalaxyLayout`.
3. **Sorgente** da `SecondBrainNotes` più un parser dei link con risoluzione alla Obsidian e una cache per `FileStamp`.
4. **Canvas 2D scartato** per la vista intera: regge al massimo qualche centinaio di archi [M2][M3]. Resta possibile per un riquadro piccolo "note collegate" attorno a una nota.
5. Da misurare in #658 sul Mac di riferimento: fotogramma p95 col Metal HUD [S1], tempo della simulazione fino all'arresto, e un M1 base se disponibile.

## Rischi

- **Archi illeggibili.** 20.000 linee sovrapposte fanno una macchia. Servono alpha bassa, archi accesi solo attorno alla selezione e un filtro per cartella. È un limite di leggibilità prima che di GPU, come le etichette della Galassia [S2].
- **Stabilità.** Senza posizioni in cache il grafo cambia forma a ogni apertura, che è proprio il difetto per cui la Galassia evita le forze [S2].
- **M1 base non misurato**: la stima di 5× viene dalla spec 11 [S2].
- **Canvas misurato solo per approssimazione** con CoreGraphics [M2][M3], perché il backend di `Canvas` non è documentato.

## Fonti

Codice (branch `main` al 2026-10-03):

- [C1] `Bubo/Galaxy/GalaxyRenderer.swift`
- [C2] `Bubo/Galaxy/Galaxy.metal`
- [C3] `Bubo/Galaxy/GalaxyMapNSView.swift`
- [C4] `Bubo/Galaxy/GalaxyCamera.swift`
- [C5] `Bubo/Galaxy/GalaxyLabels.swift`; `GalaxyModel.labels()`, `labelLimit = 40`
- [C6] `Bubo/Galaxy/GalaxyLayout.swift`
- [C7] `Bubo/Galaxy/GalaxyModel.swift`, `Bubo/Galaxy/GalaxyFiles.swift`
- [C8] `Bubo/Index/SecondBrainNotes.swift`
- [C9] `Bubo/SecondBrain/NoteCitation.swift`
- [C10] `Bubo/Galaxy/GalaxyCache.swift`

Specifiche del repo:

- [S1] `docs/features/25-prestazioni.md`: budget della Galassia, Metal HUD.
- [S2] `docs/features/11-galassia.md`: "Misura C", costi di rendering, "Nessun layout a forze", stima M1 a 5×.

Documentazione:

- [W1] d3-force, Many-body: https://d3js.org/d3-force/many-body (Barnes–Hut, `theta` 0,9)
- [W2] d3-force, Simulation: https://d3js.org/d3-force/simulation (`alphaDecay` 0,0228, circa 300 iterazioni)
- [W3] Apple, `Canvas`: https://developer.apple.com/documentation/swiftui/canvas
- [W4] Apple, `drawingGroup(opaque:colorMode:)`: https://developer.apple.com/documentation/swiftui/view/drawinggroup(opaque:colormode:)
- [W5] Obsidian Help, Internal links: https://help.obsidian.md/links

Misure [M1]–[M5]: script usa-e-getta in Swift, eseguiti su questo Mac (M4 Max, macOS 26.7) e non salvati nel repo. I metodi sono descritti sopra.
