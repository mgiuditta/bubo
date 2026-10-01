# 25 — Prestazioni native e come misurarle

Ticket: [#181](https://github.com/mgiuditta/bubo/issues/181) (ricerca), [#186](https://github.com/mgiuditta/bubo/issues/186) (soglie e misura), [#184](https://github.com/mgiuditta/bubo/issues/184) (finestra Plugin), [#185](https://github.com/mgiuditta/bubo/issues/185) (Sandbox), [#187](https://github.com/mgiuditta/bubo/issues/187) (onboarding). Mappa: [#178](https://github.com/mgiuditta/bubo/issues/178).
Ricerca del 2026-09-30 su MacBook Pro M4 Max (14 core, 36 GB), macOS **26.7**, Xcode **26.6**, CLI `claude` **2.1.285**, Agent SDK TS **0.3.282**, Bun **1.3.10**. Claude Desktop **2.16120.0** (Electron 44.4.3), Cursor **3.20.21** (Electron 42.10.0).

> **Nota sulla ricerca.** È scritta prima delle decisioni e in alcuni punti è superata. Le baseline XCTest non servono a bloccare: sui runner di GitHub non sono stabili, quindi la CI blocca solo oltre **2× il budget** o su un invariante rotto, e i budget esatti si verificano sul Mac di riferimento con `scripts/perf.sh` ([#186](https://github.com/mgiuditta/bubo/issues/186)). MetricKit si usa anche se la consegna con Developer ID non è confermata, ma i report restano sul Mac e non si inviano mai. Il modello di Conductor (chiudere gli agenti inattivi) diventa la **sospensione dopo 10 minuti**. L'Orb non punta ai 120 fps di Zed: resta a **60 fps** come nel brief, con tempo GPU p95 ≤ 4 ms. Gli obiettivi per un M1 base sono stime riportate dalla CI, non soglie. Le misure della ricerca sono fatte con `settingSources: []`: i budget di RAM totali valgono con configurazione vuota, e i Server MCP dell'utente restano fuori. Valgono la Mappa e la Specifica qui sotto.

In sintesi: nessun concorrente pubblica numeri misurati con un metodo ripetibile. **Claude Desktop** a riposo pesa **670 MB** di footprint in 12 processi, misurati qui; le issue parlano di 2,4 GB con una sola sessione. **Codex Desktop** e **Cursor** hanno issue aperte con il Mac in crisi di memoria, fino al crash di `WindowServer`. **Zed**, l'unico nativo, dichiara avvio sotto 1 s e fotogrammi sotto 4 ms a 120 fps, senza dire come misura. **Conductor** chiude i processi agente inattivi e li riprende quando servono. Il peso vero di Bubo non è l'app: è un `claude` per Sessione, **~135 MB** di footprint a riposo e pronto in **~0,5 s**, più il ponte `bun` da 36–41 MB. Con 10 Sessioni il totale è **1,38 GB**, e le sessioni lunghe crescono. Apple ha tutto per misurare su macOS 26: signpost, sette metriche XCTest (con la nuova `XCTHitchMetric`), MetricKit con metriche giornaliere, Metal HUD con log per fotogramma e `xctrace` da riga di comando. Swift Testing invece **non ha test di prestazione**. La 25 fissa il Mac di riferimento, una **tabella unica dei budget** di tutte le feature, gli strumenti di misura e due meccanismi di prodotto: la sospensione delle Sessioni inattive e l'avviso delle Sessioni pesanti.

## Ricerca

### Concorrenti: tecnologia e numeri pubblici

| Prodotto | Tecnologia | Avvio | RAM | Fotogrammi | Fonte e metodo |
|---|---|---|---|---|---|
| **Claude Desktop** 2.16120.0 | Electron 44.4.3; bundle 884 MB | Non pubblicato | Misura locale a riposo: **670 MB** di footprint deduplicato in 12 processi. Issue: ~2,4 GB e ~70% di CPU con una sessione su MacBook Air M3 16 GB [27] | Non pubblicato; renderer all'87% della CPU [31] | Issue e misura locale |
| **Codex Desktop** (app ChatGPT [36]) | Electron (`Codex (Renderer)`, `Codex (Service)`) [33] | Non pubblicato | Issue: Renderer ~818 MB, Service ~390 MB, `codex` ~733 MB. Con 5 subagent su un Air da 16 GB, crash di `WindowServer` [33]. All'apertura `syspolicyd` sale a più GB (90 commenti) [32] | Non pubblicato | Issue |
| **Cursor** 3.20.21 | Electron 42.10.0; bundle 932 MB | Non pubblicato | Issue: oltre 100 GB dopo lo stop del Mac, fino al riavvio di `WindowServer` [34] | Non pubblicato | Forum ufficiale |
| **Conductor** | Tauri 2.6.2, agenti su Bun, SQLite [26] | Non pubblicato | Chiude i processi agente inattivi e li riprende su richiesta; −150 MB di bundle passando da Node a Bun [26] | "50% più veloci" dopo la riscrittura; chat virtualizzata (~15 messaggi montati su 500+) [26] | Blog tecnico |
| **Zed** | Rust, GPUI su Metal | "under 1 second" [25] | "~600MB RAM" [25] | 120 fps, fotogramma sotto 4 ms [24] | Pagine senza metodo |

**Come Zed è arrivato a 120 fps** [24]. Ha tolto `presentsWithTransaction` con `waitUntilCompleted()` e usato `waitUntilScheduled`. Ha aggiunto un pool di buffer (triplo buffering), perché la CPU riscriveva memoria che la GPU leggeva ancora. Per non far scendere ProMotion, disegna ancora per 1 s dopo l'ultimo input.

### Misure locali: il costo di una Sessione

**Metodo.** Uno script `bun` importa l'SDK e apre N `query()` con un input in streaming che non manda mai messaggi: è una Sessione aperta e ferma. `claude` installato, `settingSources: []`, cartella vuota. "Pronto" = risoluzione di `supportedCommands()`. Memoria letta dopo 15 s con `footprint --noCategories` e con `ps` (RSS).

| Scenario | Ponte (footprint) | Ogni `claude` (footprint) | Totale footprint | Pronto |
|---|---|---|---|---|
| Ponte `bun` con SDK, 0 Sessioni | 36 MB | — | 36 MB | — |
| `bun`, 1 Sessione | 37 MB | 136 MB | 173 MB | 531 ms |
| `bun`, 10 Sessioni | 41 MB | 132–136 MB (RSS 267–274 MB) | **1.384 MB** (deduplicato) | 637–790 ms in parallelo |
| `node` 24 come ponte, 1 Sessione | 48 MB | 136 MB | 184 MB | 544 ms |
| `bun`, 1 Sessione **con** impostazioni utente | 38 MB | 156 MB | 194 MB + figli MCP | 767 ms |

- Con le impostazioni dell'utente `claude` avvia anche i Server MCP: sul Mac di prova un `uv` (~32 MB di RSS) e un `node` (~48 MB) **per Sessione**.
- La differenza tra RSS e footprint del `claude` sono pagine pulite del binario da 224 MB [35]. Il totale deduplicato di 10 Sessioni è quasi la somma: la memoria sporca non si condivide.
- Due sessioni `claude` interattive usate per ~2 h 43 min: **313 MB** e **370 MB**, ciascuna con i suoi figli (`uv`, `node`, `caffeinate`, un server di linguaggio).
- Le issue riportano ~700 MB di RSS a riposo su Linux [28], crescite fino a 4,6 GB in pochi minuti [29] e 14,6 GiB con OOM dopo 2,5 h [30].

**Claude Desktop a riposo** (stesso Mac, aperto da 2 h 23 min): renderer principale 347 MB, main 181 MB, quattro helper 116 MB, secondo renderer 22 MB, altri ~8 MB. **Totale deduplicato 670 MB** (RSS sommato 1.092 MB).

### Definizioni e soglie di Apple

- **Avvio** [7]: Xcode Organizer e MetricKit lo misurano fino al **primo fotogramma**. Il lavoro dopo non entra; Apple consiglia di marcarlo con signpost nella categoria `pointsOfInterest`. Caldo e freddo sono "uno spettro": freddo è dopo un riavvio o quando un'app pesante ha tolto dalla memoria le dipendenze.
- **Reattività** [8]: oltre **100 ms** di lavoro sincrono sul main thread per un'interazione discreta è un hang. Per le interazioni continue il limite è un refresh (8,3 ms a 120 Hz, 16,7 ms a 60 Hz); sotto **5 ms** il fotogramma di solito è pronto.
- **Hitch** [8]: un fotogramma non pronto per il refresh successivo. Si vede nei modelli Instruments Animation Hitches, Time Profiler e Hitches.

### Strumenti di misura su macOS 26

**Signpost** [6]. `OSSignposter` (macOS 12+): `beginInterval`/`endInterval`, `withIntervalSignpost`, `emitEvent`, `beginAnimationInterval`. Esiste un signposter `disabled`. Gli intervalli si vedono in Instruments e si misurano con `XCTOSSignpostMetric`.

**Metriche XCTest** (intestazioni di Xcode 26.6) [1][2].

| Metrica | Cosa misura | Note per macOS |
|---|---|---|
| `XCTApplicationLaunchMetric` | Tempo al primo fotogramma; con `waitUntilResponsive: true` finché il main thread accetta input | Serve un target di UI test (`XCUIApplication().launch()`) |
| `XCTMemoryMetric` | Memoria fisica | `init(application:)` misura l'app sotto test |
| `XCTCPUMetric` | Istruzioni e tempo di CPU | — |
| `XCTClockMetric` | Tempo monotono | Default di `measure` |
| `XCTStorageMetric` | Byte scritti su disco | — |
| `XCTOSSignpostMetric` | Durata di un signpost `(subsystem, category, name)` | Su un intervallo di animazione aggiunge fps, hitch e rapporto di hitch |
| `XCTHitchMetric` | Hitch dell'app sotto test | **Nuova in macOS 26**, solo `init(application:)` [4] |

- `iterationCount` di default 5; la prima iterazione si scarta [1].
- Baseline [3]: configurazione **Release**, niente "Debug executable", copertura né sanitizer. Le baseline sono legate alla **combinazione di macchina e destinazione** [23].

**Swift Testing** [5] non ha misure né baseline: l'unico limite è `.timeLimit(.minutes(n))`.

**MetricKit** [9][10][11]. Metriche giornaliere su macOS **26+**, diagnosi (crash, hang, eccessi di CPU e disco) da macOS 12. Su macOS: avvio (`histogrammedTimeToFirstDraw`, avvio esteso con `extendLaunchMeasurement(forTaskID:)`), reattività, memoria, CPU, GPU, disco, animazioni (`hitchTimeRatio` da 26). `MXAppLaunchDiagnostic` non esiste su macOS. Con Developer ID sembra funzionare (48 h di `pastPayloads` riportate), ma Apple non conferma che la consegna non richieda App Store o TestFlight [12].

**Fotogrammi Metal** [13][14][15]. Il **Metal Performance HUD** con `MTL_HUD_LOG_ENABLED=1` scrive ogni secondo una riga `metal-HUD:` con intervallo di presentazione e tempo GPU di ogni fotogramma: si legge con uno script. `MTLCommandBuffer.gpuStartTime`/`gpuEndTime` danno il tempo GPU per command buffer. In Instruments: Metal System Trace, Display, Frame Lifetimes, Hitches.

**`xctrace`** [16]. `xctrace record --template <nome> --launch|--attach`, `--time-limit`, `--no-prompt`; `export --toc`/`--xpath` in XML. Osservazione locale: il modello App Launch lanciato da una shell non interattiva non si è fermato da solo, e il file salvato non si esportava. Il Time Profiler invece sì.

**`footprint`** [17]. Misura la memoria sporca e deduplica tra processi (`--noCategories`, `-j` per JSON, `--sample`). Senza root legge solo i processi dell'utente.

### CI su GitHub Actions

| Runner | Etichetta | Hardware |
|---|---|---|
| Standard arm64 | `macos-26` | VM M1, 3 core, 7 GB [18] |
| XLarge arm64 (a pagamento) | `macos-26-xlarge` | M2, 5 core + 8 core GPU, 14 GB [19] |

macOS 26 è disponibile a tutti dal 2026-02-26 [21], con Xcode 26.6 di default [22]. Niente virtualizzazione annidata e nessun UUID fisso per i runner arm64 [18]: le baseline XCTest non si ritrovano da un job all'altro. GitHub non dice niente di Metal sui runner standard né garantisce prestazioni costanti.

### Lamentele ricorrenti (issue)

- **Claude Desktop**: 2,4 GB e 70% di CPU con una sessione; peso diviso tra renderer, GPU, main, VM Linux e CLI [27]. Renderer all'87% [31].
- **CLI `claude`**: ~700 MB a riposo [28], da 500 MB a 4,6 GB [29], 14,6 GiB e OOM [30].
- **Codex Desktop**: `syspolicyd`/`trustd` fuori controllo all'avvio [32]; i subagent saturano 16 GB [33].
- **Cursor**: oltre 100 GB e crash di `WindowServer` dopo lo stop del Mac [34].

## Il meglio da battere

Nessuno pubblica numeri ripetibili. Il riferimento per l'app è **Claude Desktop** (670 MB a riposo, misurato qui); per i fotogrammi è **Zed** (dichiarato, non misurato); per i processi agente è **Conductor**, che chiude quelli inattivi. Criteri candidati usciti dalla ricerca (quelli decisi sono nella Specifica):

1. **Avvio sotto 1 s** fino all'HUD che accetta input, non solo al primo fotogramma; nessun `claude` all'avvio.
2. **App leggera**: Bubo a riposo sotto 100 MB, contro 670 MB di Claude Desktop.
3. **Sessioni ferme quasi gratis**: chiudere i `claude` inattivi e riprenderli senza che l'utente se ne accorga (Conductor lo fa, ma non dice con quali numeri).
4. **Nessuna sessione che cresce di nascosto**: le issue arrivano a 4,6 GB e 14,6 GiB senza che l'utente veda niente.
5. **Orb fluido e muto quando non si vede**: 60 fps, tempo GPU basso, 0 fotogrammi coperto.
6. **Nessun hang** nei flussi principali.
7. **Metodo pubblicato**: test e script ripetibili, che nessun concorrente ha.

## Rischi e casi limite

- **Il costo vero è fuori da Bubo**: ~135 MB per `claude` più i Server MCP dell'utente per ogni Sessione. Bubo non può ridurli, può solo non tenerli accesi quando non servono.
- **Sospendere uccide i figli**: un comando in background lanciato dall'agente (server, watcher) è figlio di `claude`. Chiudere `claude` lo fermerebbe.
- **Ripresa che fallisce**: worktree spostato o cancellato → `startup_failure_reason` = `worktree_unverified` o `worktree_resume_refused` ([01](01-sessioni-worktree.md)). Il messaggio dell'utente non deve perdersi.
- **Ripresa che cambia il contesto**: i Server MCP ripartono e la cache del prompt può scadere. Il primo turno dopo la sospensione può costare di più.
- **Baseline instabili in CI**: VM condivise, niente UUID fisso. Soglie strette in CI darebbero falsi rossi.
- **Metal sui runner standard** non documentato: i test di fotogrammi potrebbero non avere una GPU.
- **`xctrace` da shell non interattiva** può non fermarsi e salvare file non esportabili: la profilazione resta un lavoro con una persona davanti.
- **MetricKit con Developer ID** non confermato da Apple: la raccolta può restare vuota.
- **Lettura del footprint**: lanciare `footprint` o `ps` ogni 30 s per 10 Sessioni sarebbe esso stesso un costo (la 15 vieta già `lsof`/`ps` periodici).
- **Latenze sparse in 20 spec**: senza una tabella unica un numero cambia in una spec e non nell'altra.
- **Mac più piccoli**: M1 base con 8 GB e 10 Sessioni da 135 MB più MCP va in pressione di memoria prima dei 10.

## Mappa

Architettura comune in [INDEX.md](INDEX.md). La 25 non aggiunge funzioni visibili a parte due: la sospensione delle Sessioni inattive (invisibile) e l'avviso "Sessione pesante". Il resto è metodo: definizioni, budget, strumenti, CI. Si appoggia sul ponte agente ([#66](https://github.com/mgiuditta/bubo/issues/66)), sulle Sessioni (01), sull'Orb e sul pannello debug (fase 1–2), sulla Galassia (11), sull'Indice e sulle Impostazioni.

### Mac di riferimento e definizioni (deciso)

Fonte: [#186](https://github.com/mgiuditta/bubo/issues/186).

- **Mac di riferimento**: M4 Max 36 GB, macOS 26, il Mac di sviluppo. Tutti i budget valgono lì.
- **M1 base**: gli obiettivi (per esempio Galassia a 60 fps) restano stime. Li riporta il runner CI standard (VM M1, 3 core): segnalano, non bloccano.
- **Avvio** = dal lancio all'**HUD interattivo**: primo fotogramma più main thread che accetta input. Si misura con `XCTApplicationLaunchMetric(waitUntilResponsive: true)` e con il signpost `HUD interattivo`. **Caldo** = Bubo appena chiuso, dipendenze in memoria. **Freddo** = dopo un riavvio del Mac.
- **Sessione pronta** = dall'apertura della Sessione alla fine dell'`initialize` del suo `claude` (`supportedCommands()` risolto).
- **RAM** = footprint (memoria sporca), come lo conta `footprint`. RSS non si usa per i budget.
- **Hang** = più di 100 ms di lavoro sul main thread in un'interazione discreta. **Hitch** = fotogramma non pronto per il refresh successivo.
- **Flussi principali**: avvio, apertura Sessione, Palette, cambio di Vista delle Sessioni.

### Tabella dei budget (deciso)

Una sola tabella per tutte le feature. **Ogni numero resta nella sua spec**: qui c'è il rimando e il modo di misurarlo. Se una spec cambia un numero, cambia anche questa riga. Tutto sul Mac di riferimento, p95 dove non scritto altrimenti.

Colonna **CI**: *2×* = misurato in CI, blocca la PR solo oltre il doppio del budget; *invariante* = blocca sempre se rotto; *perf.sh* = solo sul Mac di riferimento prima di ogni rilascio; *feature* = misurato dai test della feature proprietaria.

| Area | Budget | Come si misura | Spec | CI |
|---|---|---|---|---|
| Avvio caldo | **≤ 500 ms** fino all'HUD interattivo | `XCTApplicationLaunchMetric(waitUntilResponsive: true)` + signpost `HUD interattivo` | 25 | 2× |
| Avvio freddo | **≤ 1 s** fino all'HUD interattivo | `perf.sh` dopo riavvio del Mac | 25 | perf.sh |
| `claude` all'avvio | **0** processi | albero dei processi figli dopo l'avvio | 25 | invariante |
| Sessione pronta | **≤ 1 s** dall'apertura (misurati ~0,5 s) | signpost `Sessione pronta` | 25, 04 | perf.sh |
| `init` con configurazione completa | **≤ 1 s** | messaggio `init` | 04 | feature |
| Sessione in worktree con 1 GB di dipendenze | **< 2 s** | tempo di creazione | 01 | feature |
| Ripresa dopo sospensione | **≤ 1 s** dal messaggio all'invio a `claude` | signpost `Ripresa Sessione` | 25 | perf.sh |
| Bubo a riposo | **≤ 100 MB** (HUD + Orb, 0 Sessioni, Indice non caricato) | `XCTMemoryMetric(application:)`, `footprint` | 25 | 2× |
| Bubo con 10 Sessioni | **≤ 150 MB**, processi agente esclusi; **< 1% CPU** a riposo | `footprint`, `XCTCPUMetric` | 01 | perf.sh |
| Indice caricato | **≤ +100 MB** di RAM per 10.000 note (modello escluso), **≤ 150 MB** su disco; modello liberato dopo 60 s | `footprint` | Indice | feature |
| Ponte | **≤ 50 MB** | `footprint` | 25 | perf.sh |
| Totale con 10 Sessioni, configurazione vuota | **≤ 1,6 GB** (i `claude` ~1,35 GB) | `footprint` deduplicato su Bubo, ponte e `claude` | 25 | perf.sh |
| 10 Sessioni sospese | **≤ 200 MB** in totale (Bubo + ponte, 0 `claude`) | `footprint` | 25 | perf.sh |
| Riserva del pannello della configurazione | **230–260 MB**, un solo `claude`; mai nei primi 10 s dopo l'HUD interattivo, chiusa con la pressione di memoria ([#311](https://github.com/mgiuditta/bubo/issues/311)) | `footprint` | 25, 04 | perf.sh |
| Sessione pesante | avviso oltre **2 GB** per `claude`, letto ogni **30 s** | `ProcessFootprintMonitor` | 25 | feature |
| Orb | **60 fps**, tempo GPU **p95 ≤ 4 ms** | `gpuStartTime`/`gpuEndTime`, log del Metal HUD | 25, fase 1–2 | 2× |
| Orb nascosto o coperto | **0 fotogrammi** | contatore dei fotogrammi | 25 | invariante |
| Galassia | **120 fps**, fotogramma **p95 < 8 ms** con Orb aperto; prima immagine **< 500 ms** su 10.000 file; stella accesa **< 100 ms** | log del Metal HUD, signpost | 11 | feature |
| Galassia su M1 base | **60 fps** (stima) | runner CI standard | 11 | solo report |
| Galassia ferma, coperta o minimizzata | **0 fotogrammi** | contatore dei fotogrammi | 11 | invariante |
| Hang nei flussi principali | **0 > 100 ms** | `XCTOSSignpostMetric`, modello Hangs | 25 | 2× |
| Hitch nelle animazioni Notte | rapporto **< 1%** | `XCTHitchMetric` | 25 | 2× |
| Palette | aperta **≤ 100 ms** dopo ⌘K; risultati **≤ 50 ms** su 30.000 frammenti | signpost `Palette` | 14 | feature |
| Indice | query **≤ 50 ms** su 30.000 frammenti | test dell'Indice | Indice | feature |
| Cronologia CLI | primi 50 **< 100 ms** | test della 04 | 04 | feature |
| Dal gesto all'Orb | **< 300 ms** (Bubo aperto); selettore di finestra **≤ 500 ms** | signpost | 09 | feature |
| Pipeline degli ingressi | Pensiero **≤ 100 ms**; inizio Morph **≤ 350 ms** (previsione) o **≤ 600 ms** (classificatore); Morph finito **≤ 1,7 s** | signpost | 09, 08 | feature |
| Voce | testo finale **≤ 250 ms**; primo audio **≤ 300 ms**; audio fermo **≤ 100 ms** | test della 08 | 08 | feature |
| Router | decisione **≤ 50 ms** con le regole, **≤ 300 ms** on-device o Jev | test della 10 | 10 | feature |
| Diff e merge | diff aggiornato **< 300 ms**; **60 fps** su 50.000 righe, primo fotogramma **< 200 ms**; `merge-tree` **< 500 ms** | test della 02 | 02 | feature |
| Terminale e Anteprima | pannello **< 100 ms**; server rilevato **≤ 1 s**; screenshot **< 500 ms**; clic **< 200 ms**; l'utente interrompe **≤ 100 ms** | test della 15 | 15 | feature |
| Board | **60 fps** con 500 Sessioni e 100 Bozze; `BoardColumn` **< 5 ms**; ⌘4 **< 100 ms** | test della 17 | 17 | feature |
| Finestra Costi | **< 500 ms** con 12 mesi | test della 18 | 18 | feature |
| Automazioni | scarto dall'orario **< 1 min**; recupero **≤ 5 s** dal risveglio | test della 19 | 19 | feature |
| Finestra Plugin | Marketplace in cache **< 300 ms** senza rete | signpost | 20 | feature |
| Sandbox | overhead **≤ 10 ms** per comando (misurati ~5,5 ms) | test della 22 | 22 | feature |
| Onboarding | **≤ 60 s** dal lancio al primo token con `claude` pronta; rilevamento **dopo** l'HUD interattivo; timeout del primo token 30 s | cronometro della 26 | 26 | feature |

### Avvio (deciso)

Fonte: [#186](https://github.com/mgiuditta/bubo/issues/186), rilevamento da [#187](https://github.com/mgiuditta/bubo/issues/187).

- Prima dell'HUD interattivo solo ciò che serve a disegnarlo: finestra, Orb, design token, impostazioni lette.
- **Dopo** l'HUD interattivo, in background e in quest'ordine: ponte `bun`, rilevamento di `claude` (onboarding, 26), osservatori FSEvents, iscrizione a MetricKit, attesa della riserva del pannello della configurazione.
- **Nessun `claude`** finché non si apre una Sessione. Unica eccezione, per decisione dell'utente su [#311](https://github.com/mgiuditta/bubo/issues/311): la **riserva** del pannello della configurazione, un `claude` avviato con `prewarm()` **10 s dopo** l'HUD interattivo, solo se esiste un Progetto (mai durante l'onboarding), chiuso con la pressione di memoria. Nessun Indice caricato all'avvio: si carica alla prima ricerca (regola dell'Indice).
- Il signpost `HUD interattivo` è un evento nel sottosistema di Bubo, categoria `pointsOfInterest`. MetricKit riceve lo stesso punto come fine dell'avvio esteso (`extendLaunchMeasurement`/`finishExtendedLaunchMeasurement`).

### Memoria e processi (deciso)

- Budget in tabella: Bubo ≤ 100 MB a riposo, ≤ 150 MB con 10 Sessioni, ponte ≤ 50 MB, totale ≤ 1,6 GB con configurazione vuota.
- **Sospensione delle Sessioni inattive**:
  - Dopo **10 minuti** senza turno in corso, senza Richiesta di permesso aperta e senza comandi in background, Bubo chiude il `claude` della Sessione.
  - Al messaggio successivo lo riprende con `resume` (~0,5 s) e poi invia il messaggio.
  - È invisibile: la Sessione resta Ferma com'era, niente segno e niente notifica. I Server MCP ripartono alla ripresa.
  - Nessuna impostazione in v1.
  - Effetto: 10 Sessioni ferme passano da ~1,4 GB a ~200 MB.
- **Sessioni che crescono**: il footprint di ogni `claude` si legge ogni **30 s**. Oltre **2 GB** la Sessione mostra "Sessione pesante: [Riavvia]". Riavvia chiude e riprende, come la sospensione.

### Fotogrammi e reattività (deciso)

- **Orb**: 60 fps come nel brief, tempo GPU **p95 ≤ 4 ms**. Nascosto o coperto: **0 fotogrammi** (già fatto nel Panel da `OrbPanelController`, che mette in pausa la vista quando il Panel non è visibile; lo stesso vale per l'Orb dell'HUD).
- **Galassia**: i numeri della 11 (120 fps su M4 Max, p95 < 8 ms con Orb aperto).
- **0 hang > 100 ms** nei flussi principali.
- **Hitch < 1%** durante le animazioni Notte (`XCTHitchMetric`).

### Strumenti di misura (deciso)

- **Signpost**: `OSSignposter` con il sottosistema di Bubo e categoria `pointsOfInterest` per gli intervalli chiave.
- **Target XCTest di prestazione**: avvio, memoria, hitch, `XCTOSSignpostMetric`. Swift Testing resta per tutto il resto, perché non ha misure.
- **Script `footprint`** per Bubo, ponte e processi figli; **log del Metal HUD** (`MTL_HUD_LOG_ENABLED=1`) per Orb e Galassia.
- **MetricKit sul campo**: i report restano sul Mac, visibili in **Impostazioni › Diagnostica**. Non si inviano mai.

### CI (deciso)

- Workflow su `macos-26` che esegue i test di prestazione.
- **Blocca** la PR solo se un valore supera **2× il budget** o se si rompe un invariante: 0 fotogrammi a scena ferma o nascosta, 0 `claude` all'avvio. Il resto va nel report, come artefatto.
- I budget esatti si verificano sull'M4 Max con `scripts/perf.sh` **prima di ogni rilascio** (checklist della 27).

### Profilazione reale (deciso)

- È un `task` nel piano di costruzione, dopo Sessioni (01), Galassia (11) e Indice, prima della prima beta.
- Sul Mac di riferimento con `xctrace`: Time Profiler, Allocations, Metal System Trace.
- Scenario: 10 Sessioni per 2 ore più la Galassia su 10.000 file.
- Produce ticket di correzione, uno per problema trovato.

### Dettagli scelti scrivendo la spec

Non decisi nelle issue, facili da cambiare.

- **Nomi dei signpost** (catalogo chiuso in `Perf/Signposts`): eventi `HUD interattivo`; intervalli `Avvio differito`, `Apertura Sessione`, `Sessione pronta`, `Ripresa Sessione`, `Palette`, `Cambio vista`; intervalli di animazione `Morph` e `Animazione Notte`. Le altre feature aggiungono i loro nomi allo stesso catalogo.
- **Lettura del footprint dentro Bubo** con `proc_pid_rusage` (`RUSAGE_INFO_V4`, campo `ri_phys_footprint`) invece di lanciare `footprint`: 0 processi avviati per il controllo delle Sessioni pesanti. Lo script `footprint` resta per `perf.sh`.
- **"Comandi in background"** per la sospensione = processi figli del `claude` ancora vivi, subagent in background o `Bash` con `run_in_background` non finiti. Se l'albero dei processi del `claude` ha figli diversi dai Server MCP, la Sessione non si sospende.
- **Pressione di memoria**: con `DispatchSource.makeMemoryPressureSource` a livello `.critical` Bubo sospende subito le Sessioni idonee, senza aspettare i 10 minuti.
- **Riavvia durante un turno**: se la Sessione è in Lavora, il pulsante diventa "Riavvia a fine turno" e agisce appena il turno finisce. In un'Esecuzione (19) solo l'avviso, nessun riavvio automatico.
- **Budget leggibili dalla macchina**: un solo file `BuboPerfTests/PerfBudgets.swift` con i numeri della colonna CI; `perf.sh` e la CI leggono quello. La tabella qui resta la versione per le persone.
- **Report di `perf.sh`**: Markdown e JSON in `.build/perf/<data>/`, una riga per budget con valore, soglia ed esito. Giudica al budget esatto (1×) ed esce con 1 se un budget è superato o un invariante è rotto; le righe non misurate dicono perché e non bloccano. Con più letture dello stesso budget conta la peggiore.
- **Uso di `perf.sh`**: `scripts/perf.sh` a Bubo chiuso e senza toccare il Mac (i UI test vogliono schermo e fuoco); `--freddo` subito dopo un riavvio misura l'avvio freddo dal lancio al signpost `HUD interattivo`; `--live` apre una Sessione vera per l'intervallo sul main thread. La build non è firmata (`CODE_SIGNING_ALLOWED=NO`) e usa `.build/DerivedData` come `check.sh`: il permesso di Accessibilità del runner resta legato a quel percorso.
- **Letture**: i test allegano ogni lettura all'`.xcresult` come JSON `perf-<id>` (`BuboPerfTests/PerfMeasurement.swift`); lo script aggiunge le sue. Il tempo GPU dell'Orb si legge anche dal log del Metal HUD (`MTL_HUD_LOG_ENABLED`, solo con `TEST_RUNNER_BUBO_METAL_HUD=1`). Il report è `scripts/perf/`, compilato da `perf.sh` insieme a `PerfBudgets.swift`.
- **CI**: `.github/workflows/perf.yml` lancia `scripts/perf.sh --ci` su `macos-26` con Xcode 26.6, lo stesso del Mac di sviluppo: il codice deve compilare con l'Xcode predefinito di `macos-26` (Xcode 27 c'è solo sull'etichetta `xcode-27`, in anteprima, su macOS 27). Gira a ogni push su `main` e a mano (`workflow_dispatch`), non su ogni PR, per il costo del runner macOS (0,062 $/min su un repo privato). I 1,2 s e 600 ms dei criteri di #195 sono il p95 dell'avvio caldo misurato: sul runner la base è già 270–550 ms, quindi un ritardo finto va calibrato su quella. Con `--ci` lo script esce con 1 solo se una lettura blocca la PR (oltre 2× o invariante rotto) e scrive gli avvisi di GitHub Actions: errore per chi blocca, avviso per chi supera il budget entro 2× o non è misurato. Il report va nel riepilogo dell'esecuzione e nell'artefatto `prestazioni` con letture e `.xcresult`.
- **Metal assente sul runner**: i test di fotogrammi si saltano con un avviso nel report, non falliscono. La GPU paravirtuale delle VM di GitHub conta come assente: lì il Panel trasparente dell'Orb oscura lo schermo invece di disegnare. I test di prestazione lanciano Bubo con `-ApplePersistenceIgnoreState YES`, così una finestra chiusa da un test non resta chiusa nel successivo.
- **Isteresi dell'avviso**: "Sessione pesante" sparisce sotto 1,5 GB, per non lampeggiare vicino ai 2 GB.
- **Quota senza `claude` all'avvio** ([#197](https://github.com/mgiuditta/bubo/issues/197)): l'HUD mostra l'ultima Quota salvata (le finestre già azzerate restano nascoste). La lettura col metodo di uso parte solo quando l'utente apre l'HUD dopo l'avvio, una volta per avvio; prima arriva dalle Domande e dalle Sessioni (`rate_limit_event`). Non è in `LaunchSequence`, che non avvia `claude` fuori dall'onboarding.
- **Dopo un riavvio di Bubo** le Sessioni partono sospese: nessun `claude` finché l'utente non scrive (coerente con la 01, niente ripresa automatica).
- **Diagnostica**: report MetricKit salvati come JSON in `Application Support/Bubo/Diagnostica/`, tenuti 30 giorni; la sezione mostra l'ultimo giorno (avvio, hang, memoria di picco, hitch) e "Mostra nel Finder".

### Moduli

Architettura comune in [INDEX.md](INDEX.md). Moduli nuovi:

- `Perf/Signposts`: un solo `OSSignposter` di Bubo, catalogo dei nomi, evento `HUD interattivo`.
- `App/LaunchSequence`: tutto ciò che parte dopo l'HUD interattivo, in ordine (ponte, rilevamento di `claude`, FSEvents, MetricKit), fuori dal main thread quando possibile.
- `Sessions/SessionSuspender`: timer di inattività per Sessione, condizioni di sospensione, chiusura del `claude` via ponte, ripresa con `resume` al messaggio successivo con il messaggio tenuto in coda; pressione di memoria.
- `Sessions/ProcessFootprintMonitor`: footprint di ogni `claude` ogni 30 s con `proc_pid_rusage`, soglia di 2 GB.
- `HUD/HeavySessionBanner`: "Sessione pesante: [Riavvia]" nella Sessione.
- `Diagnostics/MetricsCollector`: iscritto a `MXMetricManager`, salva i payload sul Mac, avvio esteso.
- `Settings/DiagnosticsView`: sezione Impostazioni › Diagnostica.
- `bridge/`: comandi per chiudere una Conversazione dell'agente e riprenderla con `resume`, con l'elenco dei figli vivi del `claude`.
- Target `BuboPerfTests` (UI test XCTest, Release): avvio, memoria, hitch, signpost, invarianti; `PerfBudgets.swift`.
- `scripts/perf.sh`: build Release, test di prestazione, `footprint` di Bubo, ponte e `claude`, log del Metal HUD, report.
- `.github/workflows/perf.yml`: job `macos-26` con la regola del 2× e gli invarianti.
- Riuso: pannello debug dell'Orb con fps e tempo GPU (fase 1–2, [#32](https://github.com/mgiuditta/bubo/issues/32)), `OrbPanelController` (pausa a finestra coperta), `Agent/AgentBridge` e `Sessions/` (01), Galassia (11).

### Flusso

1. **Avvio**: lancio → HUD e Orb → primo fotogramma → main thread libero → evento `HUD interattivo` → `LaunchSequence`: ponte, rilevamento di `claude`, FSEvents, MetricKit. Nessun `claude`; la riserva del pannello della configurazione parte 10 s dopo, se esiste un Progetto.
2. **Apertura Sessione**: intervallo `Apertura Sessione` → ponte avvia `claude` → `initialize` → `Sessione pronta`.
3. **Inattività**: 10 minuti senza turno, Richieste o comandi in background → `SessionSuspender` chiude il `claude`. La Sessione resta Ferma.
4. **Messaggio a Sessione sospesa**: il messaggio va in coda → `resume` → `Ripresa Sessione` → invio. L'Orb passa a Pensiero all'invio, come sempre.
5. **Controllo del peso**: ogni 30 s `ProcessFootprintMonitor` legge ogni `claude` → oltre 2 GB → `HeavySessionBanner` → [Riavvia] → chiusura e `resume`.
6. **Misura**: PR → CI `macos-26` → test di prestazione → blocco oltre 2× o su invariante → report. Prima di un rilascio → `perf.sh` sull'M4 Max → report con tutti i budget.

### Casi limite

- **Comando in background dell'agente** (server, watcher): la Sessione non si sospende finché il comando vive.
- **Richiesta di permesso aperta** da ore: nessuna sospensione. La Richiesta resta com'è.
- **Ripresa fallita** (worktree spostato o cancellato): la Sessione va in Errore con il motivo della 01 e [Riprendi]; il messaggio resta nel prompt, non si perde.
- **Server avviato dalla 15** (terminale dell'utente): non è figlio di `claude`, non blocca la sospensione e non si ferma con lei.
- **Sonno del Mac**: al risveglio le Sessioni ferme da più di 10 minuti si sospendono subito.
- **Riavvio di Bubo**: tutte le Sessioni ripartono sospese; il primo messaggio riprende come dopo una sospensione (coerente con la 01: nessuna ripresa automatica).
- **Molte riprese insieme** (per esempio "Riprendi" su 10 Sessioni): in parallelo, misurate 0,64–0,79 s per 10.
- **Sessione pesante in un'Esecuzione** (19): avviso nella Sessione, nessun riavvio automatico.
- **Sessione oltre 2 GB che scende**: l'avviso sparisce sotto 1,5 GB, per non lampeggiare vicino alla soglia.
- **Server MCP pesanti dell'utente**: non contano nel budget di 1,6 GB (configurazione vuota), ma la sospensione li ferma insieme al `claude`.
- **Runner CI senza Metal**: test di fotogrammi saltati con avviso nel report.
- **MetricKit che non consegna** (Developer ID): la sezione Diagnostica dice "Nessun report ancora" e il resto funziona.
- **ProMotion**: l'Orb resta a 60 fps anche su schermi a 120 Hz; la Galassia sale a 120.

### Test

- **Avvio**: `XCTApplicationLaunchMetric(waitUntilResponsive: true)` in Release, 5 iterazioni, p95 ≤ 500 ms sull'M4 Max. Freddo con `perf.sh` dopo riavvio: ≤ 1 s.
- **Invariante `claude`**: dopo l'avvio e 10 s di attesa, 0 processi `claude` figli di Bubo o del ponte.
- **Memoria**: `XCTMemoryMetric(application:)` a riposo ≤ 100 MB; `perf.sh` con 10 Sessioni aperte e ferme: Bubo ≤ 150 MB, ponte ≤ 50 MB, totale ≤ 1,6 GB con configurazione vuota.
- **Sospensione** con orologio finto: tabella di condizioni (turno in corso, Richiesta aperta, figlio vivo, subagent in background, niente di questi) → sospende sì o no. Su Mac vero: 10 Sessioni ferme per 10 minuti → totale ≤ 200 MB; messaggio a una sospesa → `Ripresa Sessione` ≤ 1 s, risposta corretta con il contesto di prima.
- **Ripresa fallita**: worktree cancellato a Sessione sospesa → Errore con motivo, messaggio ancora nel prompt.
- **Sessione pesante**: `ProcessFootprintMonitor` con un processo finto che alloca oltre 2 GB → avviso entro 30 s; [Riavvia] → nuovo `claude`, stessa Conversazione. 0 processi lanciati dal monitor.
- **Orb**: 600 fotogrammi di Morph → tempo GPU p95 ≤ 4 ms; Panel coperto per 10 s → 0 fotogrammi. In Release il pannello debug non c'è: lanciato con `-orbFrameLog <file>`, Bubo scrive il tempo GPU di ogni fotogramma del Panel in quel file, una riga per fotogramma, e fa passare l'Orb da una Variante del Catalogo all'altra.
- **Hang e hitch**: `XCTOSSignpostMetric` su `Apertura Sessione`, `Palette`, `Cambio vista`: nessun intervallo sul main thread oltre 100 ms. `XCTHitchMetric` durante le animazioni Notte: rapporto < 1%.
- **CI**: una PR con un ritardo finto di 1,2 s all'avvio fallisce (oltre 2× di 500 ms); una con 600 ms passa con avviso nel report.
- **`perf.sh`**: sull'M4 Max produce un report con una riga per ogni budget con CI *2×*, *invariante* o *perf.sh*.
- **Diagnostica**: un payload MetricKit finto salvato e mostrato; nessuna connessione di rete aperta da `MetricsCollector`.
- **Accessibilità**: audit SwiftUI dell'avviso Sessione pesante e di Impostazioni › Diagnostica.

### Ordine di costruzione

La misura viene prima dell'ottimizzazione: i passi 1–5 danno numeri, i passi 6–8 li migliorano, il passo 9 cerca quello che i test non vedono.

1. **Signpost e test di avvio e memoria**: `Perf/Signposts` con l'evento `HUD interattivo`; target `BuboPerfTests` con avvio caldo, memoria a riposo e invariante "0 `claude`"; `PerfBudgets.swift`. Dipende solo dalla shell dell'app.
2. **Test di fotogrammi e reattività**: tempo GPU dell'Orb dai command buffer nei test, contatore dei fotogrammi a Panel coperto, intervalli `Apertura Sessione` e `Cambio vista` con `XCTOSSignpostMetric`, `XCTHitchMetric` sulle animazioni. Dipende da 1 e dall'Orb con pannello debug ([#29](https://github.com/mgiuditta/bubo/issues/29), [#32](https://github.com/mgiuditta/bubo/issues/32)).
3. **`scripts/perf.sh` e report**: build Release, test di prestazione, `footprint` di Bubo, ponte e `claude`, lettura del log del Metal HUD, report Markdown e JSON contro `PerfBudgets.swift`. Dipende da 1 e 2.
4. **CI di prestazione**: workflow `macos-26`, regola del 2×, invarianti, report come artefatto, fotogrammi saltati senza Metal. Dipende da 3.
5. **MetricKit e Impostazioni › Diagnostica**: `MetricsCollector`, avvio esteso fino a `HUD interattivo`, payload salvati sul Mac, sezione nelle Impostazioni. Dipende da 1.
6. **Avvio differito**: `App/LaunchSequence`; ponte, FSEvents e MetricKit spostati dopo `HUD interattivo`; 0 hang all'avvio; avvio caldo ≤ 500 ms misurato con 1. Dipende da 1, 5 e dal ponte agente ([#66](https://github.com/mgiuditta/bubo/issues/66)).
7. **Sospensione delle Sessioni inattive**: `SessionSuspender`, comandi del ponte per chiudere e riprendere, messaggio in coda, pressione di memoria, ripresa fallita. Dipende da 3, dal ponte e dalla Sessione in worktree ([#66](https://github.com/mgiuditta/bubo/issues/66), [#69](https://github.com/mgiuditta/bubo/issues/69), [#71](https://github.com/mgiuditta/bubo/issues/71)).
8. **Sessione pesante**: `ProcessFootprintMonitor`, `HeavySessionBanner`, [Riavvia] e "Riavvia a fine turno". Dipende da 7.
9. **Profilazione reale** (`task`, con una persona davanti): `xctrace` sull'M4 Max, 10 Sessioni per 2 ore più Galassia su 10.000 file; un ticket di correzione per problema. Dopo 01, 11 e Indice, prima della prima beta.

## Specifica "migliore di"

Miglior concorrente: nessuno pubblica numeri ripetibili. **Claude Desktop** pesa 670 MB a riposo (misurato qui) e 2,4 GB con una sessione (issue); **Zed** dichiara avvio sotto 1 s e 120 fps senza metodo; **Conductor** chiude gli agenti inattivi senza numeri. Bubo li supera così, sul Mac di riferimento:

| # | Criterio | Soglia | Concorrente | Come si misura |
|---|---|---|---|---|
| 1 | **Avvio** fino all'HUD interattivo | caldo **≤ 500 ms p95**, freddo **≤ 1 s**; **0 `claude`** all'avvio | Zed "under 1 second", senza metodo | `XCTApplicationLaunchMetric(waitUntilResponsive: true)`, `perf.sh` |
| 2 | **App leggera** | Bubo a riposo **≤ 100 MB** | Claude Desktop **670 MB** | `XCTMemoryMetric`, `footprint` |
| 3 | **Sessioni ferme quasi gratis** | 10 Sessioni sospese **≤ 200 MB** in totale; attive **≤ 1,6 GB** con configurazione vuota; ripresa **≤ 1 s** | Conductor sospende, senza numeri; Claude Desktop 2,4 GB con una | `footprint` deduplicato, signpost `Ripresa Sessione` |
| 4 | **Nessuna crescita nascosta** | **0 Sessioni** oltre 2 GB senza avviso entro 30 s | issue fino a 4,6 GB e 14,6 GiB senza avviso | test di `ProcessFootprintMonitor` |
| 5 | **Orb fluido e muto quando non si vede** | **60 fps**, tempo GPU **p95 ≤ 4 ms**; **0 fotogrammi** nascosto o coperto; hitch **< 1%** | Zed 120 fps dichiarati per l'editor | tempo GPU dei command buffer, contatore, `XCTHitchMetric` |
| 6 | **Nessun hang** | **0 hang > 100 ms** in avvio, apertura Sessione, Palette, cambio vista | renderer di Claude Desktop all'87% della CPU | `XCTOSSignpostMetric`, modello Hangs |
| 7 | **Metodo pubblicato e ripetibile** | test XCTest in CI (blocco a 2× e invarianti) + `scripts/perf.sh` sull'M4 Max prima di ogni rilascio | nessuno | presenza e verde della CI; report di `perf.sh` allegato al rilascio |

## Fonti

1. Xcode 26.6, intestazioni XCTest: `XCTMetric.h`, `XCTMetric+UIAutomation.h`, `XCTMeasureOptions.h`, `XCTestDefines.h`
2. Apple, "Performance Tests" — https://developer.apple.com/documentation/xctest/performance-tests
3. Apple, "Writing and running performance tests" — https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests
4. Apple, `XCTHitchMetric` — https://developer.apple.com/documentation/xctest/xcthitchmetric
5. Xcode 26.6, `Testing.swiftmodule/arm64-apple-macos.swiftinterface` (Swift 6.3.3), `TimeLimitTrait`
6. Apple, `OSSignposter` — https://developer.apple.com/documentation/os/ossignposter
7. Apple, "Reducing your app's launch time" — https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time
8. Apple, "Improving app responsiveness" — https://developer.apple.com/documentation/xcode/improving-app-responsiveness
9. Apple, MetricKit — https://developer.apple.com/documentation/metrickit
10. Apple, `MXMetricManager` — https://developer.apple.com/documentation/metrickit/mxmetricmanager
11. macOS 26 SDK (Xcode 26.6), intestazioni `MetricKit.framework/Headers/`
12. Apple Developer Forums, "Need MetricKit Implementation details for MacOS background Application" — https://developer.apple.com/forums/thread/821002
13. Apple, "Monitoring your Metal app's graphics performance" — https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance
14. Apple, `CAMetalDisplayLink` — https://developer.apple.com/documentation/quartzcore/cametaldisplaylink
15. Apple, `MTLCommandBuffer.gpuStartTime` — https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpustarttime
16. `xcrun xctrace help record`, `help export`, `list templates`, `list instruments` (xctrace 16.0), eseguiti in locale
17. `man footprint` (macOS 26.7)
18. GitHub Docs, "GitHub-hosted runners" — https://docs.github.com/en/actions/reference/runners/github-hosted-runners
19. GitHub Docs, "Larger runners" — https://docs.github.com/en/actions/reference/runners/larger-runners
20. GitHub Blog, M1 macOS larger runner (2023-10-02) — https://github.blog/news-insights/product-news/introducing-the-new-apple-silicon-powered-m1-macos-larger-runner-for-github-actions/
21. GitHub Changelog, "macOS 26 is now generally available for GitHub-hosted runners" (2026-02-26) — https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/
22. actions/runner-images, `macos-26-arm64/20260907.0351` — https://github.com/actions/runner-images/releases/tag/macos-26-arm64%2F20260907.0351
23. Square Engineering, "measureBlock: How Does Performance Testing Work In iOS?" (fonte secondaria) — https://developer.squareup.com/blog/measureblock-how-does-performance-testing-work-in-ios/
24. Zed, "Optimizing the Metal pipeline to maintain 120 FPS in GPUI" — https://zed.dev/blog/120fps
25. Zed, "Zed vs VS Code" — https://zed.dev/compare/vscode
26. performance.dev, "The Conductor rewrite" (2026-06-01) — https://performance.dev/the-conductor-rewrite
27. anthropics/claude-code #77560 — https://github.com/anthropics/claude-code/issues/77560
28. anthropics/claude-code #61425 — https://github.com/anthropics/claude-code/issues/61425
29. anthropics/claude-code #46931 — https://github.com/anthropics/claude-code/issues/46931
30. anthropics/claude-code #86712 — https://github.com/anthropics/claude-code/issues/86712
31. anthropics/claude-code #32010 — https://github.com/anthropics/claude-code/issues/32010
32. openai/codex #25719 — https://github.com/openai/codex/issues/25719
33. openai/codex #34685 — https://github.com/openai/codex/issues/34685
34. Cursor Forum, "Cursor using 105GB memory…" — https://forum.cursor.com/t/cursor-using-105gb-memory-causing-out-of-application-memory-on-macos-tahoe-26/140754
35. Ricerca interna "Runtime Node e Agent SDK dentro Bubo.app" — `docs/research/runtime-node.md` sul branch `research/runtime-node`
36. OpenAI, app desktop — https://learn.chatgpt.com/docs/app
