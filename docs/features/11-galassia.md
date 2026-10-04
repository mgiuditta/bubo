# 11 — Galassia: la mappa 2,5D del Progetto con le Sessioni al lavoro

Ticket: [Ricerca: visualizzazioni 3D di repository](https://github.com/mgiuditta/bubo/issues/48), [Prototipo: Galassia del repo](https://github.com/mgiuditta/bubo/issues/49), [Galassia: dove vive nell'HUD](https://github.com/mgiuditta/bubo/issues/56). Mappa: [#42](https://github.com/mgiuditta/bubo/issues/42).
Ricerca del 2026-09-29. Misura su Apple M4 Max, macOS 26.7.

> **Nota sulla ricerca.** È scritta prima delle decisioni e in due punti è superata: le comete **non** hanno la Tinta del fornitore (le Sessioni sono tutte Claude: si distinguono per nome e segno, [#49](https://github.com/mgiuditta/bubo/issues/49)), e la Galassia **non** vive nell'HUD ma in una finestra a sé ([#56](https://github.com/mgiuditta/bubo/issues/56)). Il titolo originale diceva "3D": la scelta è un piano 2,5D. Valgono la Mappa e la Specifica qui sotto.

In sintesi: la 3D di codice ha **una** prova sperimentale solida a favore (CodeCity, +24% correttezza, −12% tempo), ma sulle domande di panoramica ("dove sta", "quanto è sparso"), non su "trova questo file preciso": lì un elenco o un foglio di calcolo resta più veloce [3]. Nessuno dei concorrenti multi-agente mostra il repo come mappa: mostrano liste, diff, grafi di tool o personaggi animati. La metafora che regge 10.000 file è un **piano stabile** (cartelle come ammassi a posizione fissa, file come stelle istanziate), con l'altezza/luce per l'attività e un livello di dettaglio per cartella. Il rendering non è il problema: 10.000 stelle istanziate costano 0,23 ms di GPU. I problemi veri sono il layout stabile, le etichette e la ricerca.

## Ricerca

### Visualizzazioni di repository

| Strumento | Metafora | Stato | Cosa funziona | Limiti |
|---|---|---|---|---|
| **Gource** | Albero animato: la radice al centro, cartelle come rami, file come foglie; gli autori sono avatar che "sparano" sui file che toccano [1]. | Vivo: 0.56 del 2026-03-06, OpenGL + SDL2 [1]. | È l'immagine di riferimento di "agenti al lavoro sul repo". Evidenzia l'utente (`--highlight-user`), la camera lo segue (`--follow-user`), i file inattivi spariscono (`--file-idle-time`) [2]. | È un **filmato**, non uno strumento: il layout è a forze e si sposta di continuo, quindi niente memoria spaziale. Sui repo grandi si difende scartando file (`--max-files`: "i file in eccesso vengono scartati") e nascondendo nomi ed effetti (`--hide`) [2]. |
| **CodeCity** (Wettel, Lanza) | Città 3D: classi = edifici, package = quartieri; altezza = n. metodi, base = n. attributi, colore = LOC [3]. | Ricerca (2008–2011). | L'unico esperimento controllato robusto a favore (vedi sotto). | Pensato per metriche di classi Java, non per file generici né per attività in tempo reale. |
| **GitHub Next repo-visualization** | Circle packing 2D: ogni cartella e file è un cerchio; colore = estensione, area = byte [4]. | Prototipo dell'agosto 2021 [4]; il repo della Action è **archiviato dal 2026-08-06** [5]. | Leggibile a colpo d'occhio, statico, deterministico. `max_depth` predefinito 9, `excluded_paths` per `node_modules` e simili [5]. | Solo SVG statico nel README, nessuna interazione, nessuna attività. |
| **CodeSee** | Mappa delle dipendenze aggiornata a ogni merge, con note del team [6]. | Acquisita da GitKraken il 2024-05-14 [6]; `codesee.io` oggi risponde 404 (verificato 2026-09-29). | L'idea di una mappa "sempre aggiornata". | Prodotto chiuso e assorbito: nessun uso da imitare oggi. |
| **Sourcetrail** | Grafo delle dipendenze navigabile accanto al codice (C, C++, Java, Python) [7]. | Archiviato il 2021-12-14 [7]. | Grafo locale **attorno al simbolo selezionato**, non tutto il sistema. | Indicizzazione per linguaggio: costosa da mantenere, ed è morto per questo. |

### Dashboard multi-agente: cosa mostrano dei file

| App | Vista dei file toccati | Mappa del repo? |
|---|---|---|
| **Claude Code Agent view** (2026-05-11) | Una riga per sessione: se serve input, ultima risposta, ultima interazione [8]. | No. |
| **Superset** | Pannello "changes" (⌘L): file modificati e diff riga per riga, modificabile [9]. Monitoraggio nella barra laterale con badge e suoni [9]. | No. |
| **Sculptor (Imbue)** | Diff per workspace, Pairing Mode che sincronizza il codice dell'agente nell'IDE, gestione conflitti al merge [10]. | No. |
| **agent-flow** | Grafo dei nodi (agenti, subagent, chiamate ai tool) e **heatmap dell'attenzione sui file**, via hook HTTP di Claude Code o JSONL; Next.js + estensione VS Code, 1,7k stelle [11]. | No, ma è il più vicino: la heatmap è per file, non spaziale. |
| **Pixel Agents** | Un personaggio pixel art per terminale Claude Code, animato su lettura/scrittura/comandi; fumetti quando serve un permesso; i subagent come personaggi figli [12]. | No: metafora "ufficio", decorativa. |

Nessuno risponde a "dove, nel repo, sta lavorando questo agente". È lo spazio libero della Galassia. Il rischio è quello di Pixel Agents e Gource: un bello spettacolo che non fa trovare nulla.

### Cosa dicono gli studi

- **CodeCity, esperimento controllato** (ICSE 2011) [3]. 41 partecipanti (21 accademia, 20 industria), due sistemi Java: FindBugs (93k LOC, 1.320 classi) e Azureus (454k LOC, 4.656 classi). Contro Eclipse + Excel: **+24,26% correttezza** (p = .001), **−12,01% tempo**. Il vantaggio cresce col sistema più grande (+29,62% su Azureus). Per task:
  - vince dove serve il **quadro d'insieme**: "quanto è sparso questo termine" (+29–38%), "impatto di una modifica" (+40–50%);
  - **pari o peggio** dove serve la risposta precisa: "le tre classi con più metodi" è pari in correttezza e **Excel è più veloce**. Conclusione degli autori: "CodeCity è più veloce a costruire un quadro approssimativo; un foglio di calcolo è più veloce a trovare risposte precise in grandi insiemi di dati" [3].
- **Città in VR** (IST 2019, Romano et al.) [13]. 42 partecipanti su FindBugs: la città, a schermo o in VR, migliora significativamente la correttezza rispetto a Eclipse; in VR sono più veloci che a schermo.
- **Revisione sistematica sulla 3D** (Müller, Zeckzer 2015) [14]. 155 articoli su 4.386. Le 3D sono valutate per lo più con esempi (53,3%) o per nulla (16,2%); solo il 9,0% con esperimenti controllati. Quasi sempre la terza dimensione è "2D esteso": layout piano, altezza per una metrica.
- **Revisione sulle valutazioni** (Merino et al., JSS 2018) [15]. Su 181 articoli completi di SOFTVIS/VISSOFT, il **62% non ha alcuna valutazione**.
- **Layout stabile e memoria spaziale** (Software Cartography, CODEMAP) [16]. Gli sviluppatori usano bene la mappa per vedere i risultati di ricerca e i grafi di chiamata, ma trovano il layout di base "sorprendente e spesso confuso". Gli autori concludono che l'utente deve poterlo risistemare secondo la propria memoria spaziale.
- **CityVR** (ICSME 2017) [17]. Misura solo il coinvolgimento: curiosità, immersione, tempo percepito più breve. Non l'efficacia. È la prova che "l'effetto" è misurabile e diverso dall'utilità.

**Cosa è utile oltre l'effetto.** Le prove reggono per tre usi: (1) **orientarsi**: dove sta questa cosa nel repo, quanto è sparsa; (2) **impatto**: cosa tocca una modifica; (3) **vedere i risultati di una ricerca sulla mappa**. Non reggono per "trova il file X", dove l'elenco vince. Quindi il criterio della mappa #42 ("trovo il file toccato da un agente più in fretta che nella lista") è raggiungibile solo se la Galassia **non sostituisce** la lista: la lista dei file toccati sta dentro la Galassia, e la mappa aggiunge il contesto (quale zona del repo, quanti agenti nella stessa zona, collisioni).

### Quale metafora regge 10.000 file

| Metafora | 10k file | Stabile tra fotogrammi e commit | Agenti al lavoro | Verdetto |
|---|---|---|---|---|
| Albero a forze (Gource) | Solo scartando file [2] | No: tutto si muove | Ottimo (avatar e raggi) | Da prendere solo l'animazione degli agenti. |
| Città (CodeCity) | Sì (4.656 classi nel test [3]) | Sì, layout a griglia | Serve inventarla | Buona per metriche, pesante da leggere dall'alto. |
| Circle packing / treemap (GitHub Next) | Sì, con `max_depth` [5] | Sì, deterministico | Serve inventarla | La base più leggibile. |
| Grafo delle dipendenze (Sourcetrail, CodeSee) | No, illeggibile tutto insieme | No | — | Solo locale, attorno a un file. |
| Mappa semantica (Software Cartography) | Sì | Sì, ma "confusa" [16] | — | Da scartare come layout base. |

Proposta per la spec (da validare col prototipo richiesto dalla mappa):

- **Piano stabile, 2,5D.** Le cartelle sono ammassi disposti come un circle packing gerarchico sul piano; i file sono stelle dentro l'ammasso. La terza dimensione non codifica la struttura: serve solo per l'attività (una stella toccata si alza e si accende) e per la camera. È il "2D esteso" che la letteratura trova dominante e che CodeCity ha validato [14][3].
- **Posizione deterministica.** La stessa cartella resta nello stesso posto tra aperture e tra commit: ordine per nome, un file nuovo non sposta gli altri ammassi. Nessun layout a forze.
- **Livelli di dettaglio.** Da lontano un punto per cartella (dimensione = numero di file). Avvicinandosi, le stelle; più vicino ancora, le etichette. Le cartelle ignorate da git non entrano.
- **Agenti come comete** con la Tinta del fornitore (una Tinta per fornitore, da `CONTEXT.md`). Scia verso gli ultimi file toccati (Read, Edit, Write dagli eventi dei tool); i file toccati restano accesi finché la Sessione non è Fusa o Archiviata.
- **Ricerca e lista sempre presenti.** Un campo di ricerca che accende i risultati sulla mappa (l'uso che CODEMAP ha visto funzionare [16]) e l'elenco dei file toccati per Sessione; un clic su una riga porta la camera sulla stella, e viceversa.

## Costi di rendering in Metal

**API.** Un solo draw call istanziato per tutte le stelle: `drawIndexedPrimitives(…instanceCount:)` disegna la stessa geometria `instanceCount` volte; lo shader legge posizione, dimensione e colore dal buffer delle istanze tramite `instance_id` [18]. Per scene più grandi Metal permette di togliere dalla GPU gli oggetti invisibili e di generare i draw call direttamente sulla GPU con gli indirect command buffer [19], oppure di contare i frammenti visibili per scegliere il livello di dettaglio [20]. Gli argument buffer riducono il costo CPU di legare le risorse che non cambiano tra i fotogrammi [21].

**Misura C** (questo Mac, M4 Max, macOS 26.7). Script usa-e-getta: icosfere istanziate, un solo draw call, MSAA 4×, 2880×1800, profondità attiva, 100 fotogrammi dopo 20 di riscaldamento, tempo GPU da `gpuStartTime`/`gpuEndTime`.

| Triangoli per stella | Stelle | Triangoli totali | GPU mediana | p95 |
|---|---|---|---|---|
| 80 | 1.000 | 80k | 0,10 ms | 0,11 ms |
| 80 | 10.000 | 800k | **0,23 ms** | 0,46 ms |
| 80 | 50.000 | 4M | 1,03 ms | 1,11 ms |
| 80 | 100.000 | 8M | 2,04 ms | 2,15 ms |
| 320 | 10.000 | 3,2M | 0,82 ms | 0,89 ms |
| 320 | 100.000 | 32M | 7,81 ms | 8,32 ms |

Il budget a 60 fps è 16,7 ms (8,3 ms a 120 Hz ProMotion). Il costo cresce in modo lineare con i triangoli. Stima non misurata: un M1 base ha 8 core GPU contro 40, quindi circa 5 volte più lento; 10.000 stelle da 80 triangoli restano sotto 1,5 ms. Le stelle come quad con sfera disegnata nello shader (2 triangoli) costano ancora meno.

Cosa **non** è misurato, ed è il costo vero:

- **Etichette.** Migliaia di nomi di file sono il limite, di leggibilità prima che di GPU. Serve un atlante di glifi SDF o MSDF e un tetto di etichette visibili, da fissare nel prototipo (ordine di grandezza: decine, non migliaia).
- **Archi** (scie degli agenti, eventuali dipendenze): pochi per agente, trascurabili; un grafo completo delle dipendenze no.
- **Layout.** Circle packing gerarchico su 10k nodi: da misurare, da calcolare fuori dal main thread e da mettere in cache per commit.
- **Scansione del repo.** `git ls-files` e l'osservazione dei cambiamenti (FSEvents) nei worktree delle Sessioni: da misurare nel prototipo.
- **Convivenza con l'Orb.** L'HUD ha già l'Orb in Metal (Blob). Due scene nello stesso HUD si sommano, e vale la regola di `CONTEXT.md`: un solo Orb visibile.

## Il meglio da battere

Oggi, per sapere dove lavora un agente, il riferimento è il **pannello changes di Superset** (⌘L, file modificati + diff) [9] e la **heatmap per file di agent-flow** [11]. Sono liste, veloci per "trova il file", cieche su "dove sta nel repo" e "chi altro è lì". Criteri candidati:

1. **Trovare il file toccato**: dall'apertura della Galassia al diff di un file toccato da una Sessione, tempo mediano ≤ quello della lista dei file modificati della stessa Sessione. Test con 10 file bersaglio su un repo da ≥ 5.000 file. Se la mappa perde, vince la lista integrata.
2. **Orientarsi**: alla domanda "in quale cartella di primo livello lavora ciascun agente?" risposta corretta in ≤ 5 s con 3 Sessioni attive, senza aprire nulla. Nessuna lista lo fa.
3. **Collisioni**: due Sessioni che toccano lo stesso file o la stessa cartella si vedono subito (stesso ammasso acceso da due comete, doppio anello sul file), prima del merge (feature 02).
4. **Stabilità**: la stessa cartella resta nella stessa posizione tra due aperture e dopo un commit che aggiunge file altrove (spostamento 0).
5. **Prestazioni**: 10.000 file a 120 fps sull'M4 Max e 60 fps su un M1 base; p95 di fotogramma < 8 ms; prima immagine < 500 ms su 10k file con layout in cache.
6. **Scala**: 100.000 file senza scartarne nessuno (a differenza di `--max-files` di Gource), grazie ai livelli di dettaglio per cartella.

## Rischi e casi limite

- **Effetto senza utilità.** Il 62% delle visualizzazioni non viene valutato [15], e CityVR misura solo il coinvolgimento [17]. Il criterio 1 va misurato nel prototipo, non dichiarato.
- **Layout che cambia.** Un layout a forze o semantico rompe la memoria spaziale [16]. Serve posizione deterministica per percorso.
- **Repo enormi** (monorepo, `node_modules` versionati). Da escludere con `.gitignore` e un elenco come `excluded_paths` di GitHub Next [5]; livelli di dettaglio per cartella oltre una soglia.
- **Worktree.** Ogni Sessione ha la sua copia (feature 01): i file sono gli stessi a meno delle modifiche. La Galassia mostra il repo della base e sovrappone le modifiche di ogni Sessione, non N galassie.
- **Letture contro scritture.** Gli agenti leggono moltissimi file (Grep, Glob, Read). Accendere tutto è rumore: le letture vanno più tenui e brevi, le scritture forti e persistenti.
- **Accessibilità.** Una scena Metal è muta per VoiceOver. La lista dei file toccati deve essere l'equivalente accessibile, e la Galassia deve rispettare Riduci movimento (niente scie animate).
- **Dove vive nell'HUD** (pannello, finestra, Vista delle Sessioni): aperto nella mappa #42, si decide dopo il prototipo.
- **Dati.** Tutto locale: percorsi e contenuti non escono dal Mac (principio della mappa #42).

## Mappa

### Forma (decisa)

Fonte: [Prototipo: Galassia del repo](https://github.com/mgiuditta/bubo/issues/49), variante A con due pezzi di B; prototipo usa-e-getta sul ramo [`prototype/galassia`](https://github.com/mgiuditta/bubo/tree/prototype/galassia), `prototypes/galassia.html` (SAP/spartacus, 12.476 file, `?variant=A|B|C`, Sfida cronometrata). Scelta delegata dall'utente.

- **Piano 2,5D inclinato.** Cartelle = ammassi a posizione fissa (circle packing gerarchico ordinato per nome); file = stelle istanziate. La terza dimensione serve solo all'attività: le letture sono tenui e restano sul piano, le scritture si alzano e si accendono. Due Sessioni sullo stesso file: doppio anello.
- **Livelli di dettaglio.** Da lontano un punto per cartella (dimensione = numero di file), poi le stelle, poi le etichette. File ignorati da git esclusi. La soglia delle stelle guarda il nucleo, che ha lo stesso raggio in ogni cartella: si accendono quando il nucleo sullo schermo passa da 4 a 10 pt, insieme per tutte le cartelle, mentre i punti di cartella sfumano allo stesso ritmo. Il raggio della cartella non conta, perché crescerebbe con le sottocartelle e falserebbe la soglia (#375).
- **Comete.** Una per Sessione, con scia sugli ultimi file toccati, nome, segno (● ▲ ■ …) e Attività. Colore: nessuno per Sessione, la Tinta resta del fornitore (ADR 0004: il contenitore è acromatico, Lume solo per "Attende te" e le Richieste di permesso).
- **Lista sempre a destra.** File modificati per Sessione con `+n −m`; letture raccolte in "N letture"; campo di ricerca nel Progetto che accende i risultati sulla mappa. Clic su una riga → camera sulla stella, e viceversa. La lista è l'equivalente accessibile della scena.
- **Filtro per Sessione.** Chip in cima alla lista; il clic filtra e fa seguire la cometa dalla camera, trascinare la sgancia (da B).
- **Etichette.** I nomi dei file modificati sono sempre visibili sulla mappa, entro un tetto di etichette (da B).
- **Diff in vetro.** Clic su stella o riga → la camera vola sul file, il diff si apre in un pannello di vetro sopra la mappa con "Apri nella revisione della Sessione" (feature 02).
- **Ricerca.** Per nome e percorso dei file del Progetto, non semantica: l'Indice non contiene codice ([Indice semantico condiviso](https://github.com/mgiuditta/bubo/issues/55)).

### Dove vive (deciso)

Fonte: [Galassia: dove vive nell'HUD](https://github.com/mgiuditta/bubo/issues/56).

- **Finestra a sé**, ridimensionabile, anche su un secondo schermo. Non è una Vista delle Sessioni né un pannello dell'HUD.
- **Un Progetto per finestra**, selettore in cima; più finestre ammesse, una per Progetto. Riaprire la Galassia di un Progetto già aperto porta avanti la finestra esistente.
- **Ingressi**: ⌘⇧G dentro Bubo (nessuna scorciatoia globale); "Mostra nella Galassia" su ogni Sessione (filtro su quella Sessione + cometa seguita); App Intent "Apri Galassia" (voce, Comandi rapidi, Spotlight). Niente voce di menu nel Panel.
- **Orb**: mai nella finestra della Galassia; resta nel Panel o nell'HUD. Con la Galassia a fuoco, lo Stato dell'Orb segue la Sessione filtrata. Il Panel non si sposta da sé.
- **Metal**: due scene indipendenti (Orb e Galassia). Ognuna si ferma quando la sua finestra è coperta del tutto o minimizzata. A mappa ferma la Galassia ridisegna solo su cambiamento, senza frequenza fissa.
- **Memoria per Progetto**: camera e ampiezza della lista. Il filtro no: si riapre su tutte le Sessioni, salvo arrivo da "Mostra nella Galassia".
- **Progetti senza git**: stelle e comete vengono dalle letture e scritture dell'agente; il diff confronta con la versione prima della Sessione se esiste, altrimenti non c'è. Le Domande non compaiono.

### Moduli

Architettura comune in [INDEX.md](INDEX.md#architettura-comune-feature-813).

- `Galaxy/GalaxyModel`: albero dei file del Progetto (`git ls-files`, o scansione della cartella senza git), aggiornato da FSEvents (niente polling); sovrappone le modifiche dei worktree delle Sessioni al checkout principale, una sola Galassia e non N.
- `Galaxy/GalaxyActivity`: letture e scritture per file e per Sessione dagli eventi dei tool del ponte agente (Read, Grep, Glob tenui; Edit, Write forti e persistenti fino a Fusa o Archiviata).
- `Galaxy/GalaxyLayout`: circle packing deterministico per percorso, calcolato fuori dal main thread, in cache per Progetto e commit.
- `Galaxy/GalaxyRenderer`: Metal, un draw call istanziato per le stelle, livelli di dettaglio per cartella, atlante di glifi SDF per le etichette con tetto, rendering su richiesta.
- `Galaxy/GalaxyWindow`: finestra per Progetto (AppKit + SwiftUI), lista e ricerca a destra, chip delle Sessioni, pannello del diff in vetro; stato di camera e lista per Progetto.
- Riuso: `Git/` e la revisione per blocco (feature 02) per il diff; `Sessions/` e Attività (feature 01, 06); App Intent in `System/` (feature 09); Stato dell'Orb (feature 07).

### Flusso

⌘⇧G (o "Mostra nella Galassia", o App Intent) → finestra del Progetto (o quella già aperta portata avanti) → layout dalla cache, stelle, comete delle Sessioni attive → evento di tool dal ponte → stella accesa e scia aggiornata, un ridisegno → clic su stella o riga → camera sul file, diff in vetro → "Apri nella revisione della Sessione".

### Casi limite

- **File nuovo o cancellato**: non deve spostare gli ammassi non coinvolti (vedi criterio di stabilità).
- **Monorepo e cartelle enormi**: esclusioni da `.gitignore`, livelli di dettaglio per cartella oltre soglia; mai scartare file come `--max-files` di Gource.
- **Letture di massa** (Grep, Glob): tenui e brevi, raccolte in "N letture", per non accendere tutto.
- **Collisioni**: stesso file toccato da due Sessioni → doppio anello sulla stella e segnalazione nella lista, prima del merge (feature 02).
- **Riduci movimento**: niente scie animate né voli di camera, salti diretti.
- **VoiceOver**: la scena è muta; lista, chip e ricerca coprono ogni azione della mappa.
- **Finestra coperta o minimizzata**: scena ferma, 0 fotogrammi.
- **Progetto senza git**: niente layout da `git ls-files` ma dalla cartella; diff solo se c'è la versione prima della Sessione.
- **Dati**: percorsi e contenuti restano sul Mac.

### Test

- Layout: stesso albero → stesse posizioni (test deterministico); aggiunta e rimozione di file in una cartella → posizioni delle altre cartelle invariate.
- Sfida cronometrata del prototipo portata nell'app: 10 file bersaglio su un repo ≥ 5.000 file, Galassia contro lista della Sessione, più persone.
- Prestazioni: 10.000 e 100.000 file, tempo GPU e fotogramma p95 con Orb e Galassia aperti insieme; conteggio dei fotogrammi a mappa ferma.
- Accessibilità: audit AppKit e SwiftUI della finestra (lista, chip, ricerca, pannello del diff).

## Specifica "migliore di"

Miglior concorrente: **pannello changes di Superset** (⌘L, file modificati e diff) e **heatmap per file di agent-flow**: liste veloci per trovare un file, cieche su dove sta nel repo e su chi altro lavora lì. Nessun concorrente mostra il repo come mappa; Gource lo fa ma come filmato con layout instabile e file scartati.
Bubo li supera così:
- **Trovare un file toccato**: dall'apertura al diff, tempo mediano **≤ quello della lista** della Sessione (Sfida cronometrata, 10 bersagli, repo ≥ 5.000 file). La lista sta dentro la Galassia, quindi non può perdere.
- **Orientarsi**: "in quale cartella di primo livello lavora ciascuna Sessione?" corretto in **≤ 5 s** con 3 Sessioni attive, senza aprire nulla.
- **Collisioni**: due Sessioni sullo stesso file visibili **subito** (doppio anello + riga nella lista), prima del merge.
- **Stabilità**: la stessa cartella resta nella stessa posizione tra due aperture e dopo un commit che aggiunge file altrove: **spostamento 0**.
- **Scala**: **100.000 file** senza scartarne nessuno, grazie ai livelli di dettaglio.
- **Prestazioni**: 10.000 file a **120 fps** su M4 Max e **60 fps** su M1 base, fotogramma **p95 < 8 ms** con Orb e Galassia aperti insieme; prima immagine **< 500 ms** su 10.000 file con layout in cache; evento di tool → stella accesa **< 100 ms**.
- **Energia**: a mappa ferma e senza eventi **0 fotogrammi** disegnati; finestra coperta o minimizzata: **0 fotogrammi**.
- **Accesso**: ⌘⇧G, "Mostra nella Galassia" e App Intent; **0 permessi** TCC.

## Fonti

1. Gource, sito ufficiale (0.56 del 2026-03-06) — https://gource.io/
2. Gource, README e wiki Controls (`--max-files`, `--file-idle-time`, `--hide`, `--follow-user`) — https://github.com/acaudwell/Gource/blob/master/README.md ; https://github.com/acaudwell/Gource/wiki/Controls
3. Wettel, Lanza, Robbes, "Software Systems as Cities: A Controlled Experiment", ICSE 2011, pp. 551–560 — https://wettel.github.io/download/Wettel11a-icse.pdf
4. GitHub Next, "Visualizing a Codebase" (agosto 2021) — https://githubnext.com/projects/repo-visualization/
5. githubocto/repo-visualizer (archiviato il 2026-08-06) — https://github.com/githubocto/repo-visualizer
6. GitKraken, "GitKraken Acquires CodeSee; Launches DevEx Platform" (2024-05-14) — https://www.gitkraken.com/blog/gitkraken-acquires-codesee
7. CoatiSoftware/Sourcetrail (archiviato il 2021-12-14) — https://github.com/CoatiSoftware/Sourcetrail
8. Anthropic, "Agent view in Claude Code" (2026-05-11) — https://claude.com/blog/agent-view-in-claude-code
9. Superset — https://superset.sh/ ; docs — https://www.mintlify.com/superset-sh/superset/concepts/workspaces
10. Imbue, Sculptor — https://imbue.com/sculptor
11. patoles/agent-flow — https://github.com/patoles/agent-flow
12. Pixel Agents — https://github.com/pablodelucca/pixel-agents (scheda: https://awesome.ecosyste.ms/projects/github.com%2Fpablodelucca%2Fpixel-agents)
13. Romano, Capece, Erra, Scanniello, Lanza, "On the use of virtual reality in software visualization: The case of the city metaphor", IST 114 (2019) 92–106 — https://www.inf.usi.ch/faculty/lanza/PUBS/J/Roma2019a.pdf
14. Müller, Zeckzer, "Past, Present, and Future of 3D Software Visualization — A Systematic Literature Analysis", IVAPP 2015 — https://www.scitepress.org/Papers/2015/53257/53257.pdf
15. Merino, Ghafari, Anslow, Nierstrasz, "A Systematic Literature Review of Software Visualization Evaluation", JSS 144 (2018) 165–180 — https://boris.unibe.ch/126936
16. Kuhn, Erni, Loretan, Nierstrasz, "Software Cartography: Thematic Software Visualization with Consistent Layout" (JSME 2010) e "Embedding Spatial Software Visualization in the IDE: an Exploratory Study" (SOFTVIS 2010) — https://boris.unibe.ch/4952 ; https://arxiv.org/abs/1007.4303
17. Merino et al., "CityVR: Gameful Software Visualization", ICSME 2017 — https://scg.unibe.ch/assets/archive/papers/Meri17c.pdf
18. Apple, `drawIndexedPrimitives(type:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:)` — https://developer.apple.com/documentation/metal/mtlrendercommandencoder/drawindexedprimitives(type:indexcount:indextype:indexbuffer:indexbufferoffset:instancecount:)
19. Apple, "Encoding indirect command buffers on the GPU" — https://developer.apple.com/documentation/metal/encoding-indirect-command-buffers-on-the-gpu
20. Apple, "Culling occluded geometry using the visibility result buffer" — https://developer.apple.com/documentation/metal/culling-occluded-geometry-using-the-visibility-result-buffer
21. Apple, "Improving CPU performance by using argument buffers" — https://developer.apple.com/documentation/metal/improving-cpu-performance-by-using-argument-buffers

22. Prototipo usa-e-getta della Galassia (varianti A, B, C, Sfida cronometrata) — https://github.com/mgiuditta/bubo/tree/prototype/galassia (`prototypes/galassia.html`)

Misura C: script Swift usa-e-getta (fuori dal repo) su Metal, eseguito su questo Mac il 2026-09-29. Nessun codice di prodotto.
