# Indice: ricerca per significato e per parole, in locale (pezzo condiviso per 12, 13 e 14)

Ticket: [Ricerca: indice semantico locale](https://github.com/mgiuditta/bubo/issues/47), [Indice semantico condiviso](https://github.com/mgiuditta/bubo/issues/55). Mappa: [#42](https://github.com/mgiuditta/bubo/issues/42).
Ricerca del 2026-09-29 su macOS 26.7, Xcode 26.6 (SDK 26.5), MacBook Pro M4 Max 36 GB.

In sintesi: il modello di Apple (`NLContextualEmbedding`) c'è già sul Mac ma in italiano recupera male. I modelli aperti multilingue sono nettamente migliori e girano in locale con **MLX Swift**, che ha già i preset pronti. Per l'archivio basta **SQLite di sistema**: una tabella con i vettori come BLOB e una ricerca esaustiva con Accelerate, sotto il millisecondo fino a 100.000 frammenti. Aggiornamento con **FSEvents**, ripartendo dall'ultimo event ID salvato. Stima per 10.000 note (circa 30.000 frammenti): da 1 a 10 minuti la prima volta a seconda del modello, da 23 a 123 MB di vettori su disco, meno di 30 ms per query.

## Ricerca

> Nota: la ricerca precede le decisioni. Rispetto alla **Proposta** qui sotto, [Indice semantico condiviso](https://github.com/mgiuditta/bubo/issues/55) ha scartato bge-m3 (unica qualità alta: Qwen3-Embedding-0.6B 4-bit), escluso il codice dei Progetti, indicizzato fin da subito le conversazioni passate (non solo con la 14) e fissato come criterio Recall@1 ≥ 0,80 invece di Recall@3 ≥ 0,95. Vale la Specifica in fondo.

### Modelli di embedding disponibili su macOS 26

| Opzione | Cosa è | Italiano | Nota |
|---|---|---|---|
| `NLEmbedding.sentenceEmbedding(for: .italian)` | Embedding di frase di Apple, statico, già sul sistema | Sì | 640 dimensioni, revisione 1 [misura A]. Apple lo suggerisce per la similarità [1]. Nella prova recupera peggio di tutti. |
| `NLContextualEmbedding` | Transformer di Apple, restituisce **un vettore per token** (il vettore della frase lo fa l'app, es. media) | Sì: modello "Latin" con 20 lingue, italiano compreso [2] | 512 dimensioni, max 256 token, gli asset si scaricano con `requestAssets` [2][misura A]. L'header dice: "per la similarità semantica valuta `NLEmbedding`" [2]. Non è addestrato per il retrieval. |
| Foundation Models (`SystemLanguageModel`) | LLM di sistema per generare testo, tool calling, output strutturato [3] | — | **Nessuna API di embedding**: 0 occorrenze di "embed" nell'interfaccia Swift dell'SDK 26.5 [misura C]. |
| Core Spotlight, ricerca semantica (`CSUserQuery`) | Indice di sistema in cui l'app "dona" i contenuti; ricerca semantica attiva di default [4] | Non dichiarato | "Indice privato, interamente locale". I modelli li decide il sistema: niente vettori, niente controllo sul ranking, solo contenuti donati dall'app [4]. Buono per far trovare le note da Spotlight (feature 09), non come motore di Bubo. |
| Modelli aperti via **MLX Swift** (`MLXEmbedders` in `ml-explore/mlx-swift-lm`) | Porting Swift di encoder (BERT, NomicBert, Qwen3, Gemma3, LFM2), con pooling e reranker [5] | Sì, per i multilingue | Preset già pronti: `multilingual_e5_small`, `bge_m3`, `qwen3_embedding` (Qwen3-Embedding-0.6B 4-bit, 335 MB), `bge_reranker_v2_m3` [5]. Release 3.31.4 del 2026-06-30. |
| Modelli aperti via Core ML | Conversione con coremltools, può usare il Neural Engine | Sì | Conversione e tokenizer a carico nostro. Non misurato qui. |

### Qualità in italiano: fonti pubbliche

Non esiste una classifica MTEB solo italiana. I riferimenti più vicini sono MTEB(Multilingual) e MTEB(Europe) [6], più le tabelle dei model card.

| Modello | Parametri | Dim. | MTEB(Multilingual) media | MTEB(Europe) media / retrieval | Fonte |
|---|---|---|---|---|---|
| multilingual-e5-small | 118M, 12 layer | 384 | 55,5 | 55,0 / 46,1 | [6][7] |
| multilingual-e5-base | — | 768 | 57,0 | 57,2 / 50,2 | [6] |
| multilingual-e5-large-instruct | 0,6B | 1024 | 63,2 | 62,2 / 54,8 | [6] |
| bge-m3 | 0,6B | 1024 | 59,56 | — | [8] |
| EmbeddingGemma-300m | 300M | 768 (MRL 512/256/128) | 61,15 (v2); Code 68,76 | — | [9] |
| Qwen3-Embedding-0.6B | 600M | 1024 (MRL) | 64,33; contesto 32k | — | [8] |

I numeri di [6] e [8][9] vengono da versioni diverse del benchmark: confrontabili solo dentro la stessa fonte. `NLContextualEmbedding` non compare su MTEB.

### Misura A: prova di recupero in italiano (questo Mac)

Set fatto a mano: 30 note brevi in italiano (ricette, codice, bollette, storia, git…) e 30 domande riformulate senza parole in comune, una nota giusta per domanda. Coseno su vettori normalizzati. Modelli aperti con sentence-transformers su GPU (MPS), prefissi `query:`/`passage:` per E5 e istruzione per Qwen3. Throughput su 792 paragrafi veri dei documenti di Bubo (775 caratteri, circa 200 token ciascuno). È un set piccolo: serve a vedere l'ordine di grandezza, non a stilare una classifica.

| Modello | Recall@1 | Recall@3 | MRR | ms per frammento | Embedding di una query | Pesi |
|---|---|---|---|---|---|---|
| `NLEmbedding` frase (it) | 0,23 | 0,40 | 0,397 | — | — | di sistema |
| `NLContextualEmbedding` (media dei token) | 0,60 | 0,77 | 0,717 | 15,5 (uno alla volta) | 6,8 ms | di sistema; `load()` 429 ms, RSS 156 MB |
| multilingual-e5-small | 0,83 | 0,97 | 0,908 | 2,2 (lotti da 32) | 13,9 ms | 470 MB fp32 |
| multilingual-e5-base | 0,90 | 0,97 | 0,936 | 6,2 | 11,8 ms | ~1,1 GB fp32 |
| bge-m3 | **0,97** | **1,00** | **0,983** | 20,1 | 25,5 ms | 2,27 GB fp32 |
| Qwen3-Embedding-0.6B (fp32) | 0,93 | 1,00 | 0,967 | 33,4 | 27,5 ms | 335 MB in 4-bit MLX |

La RAM dei modelli aperti non è misurabile in modo pulito da Python: il picco (da 1,2 a 4 GB) comprende PyTorch. Stima dai pesi: e5-small circa 250 MB in fp16, Qwen3 4-bit circa 350 MB, bge-m3 circa 1,1 GB in fp16.

### Archivio

| Opzione | Pro | Contro |
|---|---|---|
| **SQLite di sistema + vettori BLOB + ricerca esaustiva con Accelerate** | Nessuna dipendenza. SQLite 3.51 con FTS5 attivo [misura C]. Una sola tabella tiene testo, percorso, hash, vettore. | La ricerca si fa in memoria: la matrice va caricata in RAM (30.000 × 384 float32 = 46 MB). |
| **sqlite-vec** (`vec0`) | C puro, senza dipendenze, MIT/Apache. Vettori float, int8 e bit; colonne di metadati e di partizione [10]. KNN in SQL. | **Pre-v1**, "aspettati modifiche incompatibili" [10]; ultima release v0.1.10-alpha.4 (2026-05-18). Ricerca esaustiva, più lenta del BLAS (misura B). Il SQLite di sistema **non carica estensioni**: `sqlite3_load_extension` manca dall'header dell'SDK e `sqlite3_auto_extension` non ha effetto; funziona solo compilando `sqlite-vec.c` nell'app e chiamando `sqlite3_vec_init(db,…)` su ogni connessione [misura C]. |
| **SwiftData** | Già nello stack. | Nessun tipo vettore e nessuna funzione di similarità (0 occorrenze nell'interfaccia dell'SDK [misura C]); `#Predicate` non calcola prodotti scalari. Andrebbe caricato tutto in memoria comunque. |
| **File piatti** (un `.bin` di vettori + JSON) | Semplicissimo. | Aggiornamenti incrementali, cancellazioni e metadati da gestire a mano; nessuna ricerca per parole. |
| Core Spotlight | Gratis, visibile in Spotlight. | Scatola nera (vedi sopra) [4]. |

**Misura B** (questo Mac, vettori casuali normalizzati, k = 10):

| | Scrittura | Query | File |
|---|---|---|---|
| Accelerate `cblas_sgemv`, 10.000 × 512 float32 | — | 0,19 ms | — |
| Accelerate `cblas_sgemv`, 100.000 × 512 float32 | — | 1,17 ms | — |
| sqlite-vec, 50.000 × 512 float | 0,6 s | 12,0 ms | 99 MB |
| sqlite-vec, 50.000 × 1024 float | 3,8 s | 24,1 ms | 197 MB |
| sqlite-vec, 50.000 × 1024 int8 | 0,3 s | 7,6 ms | 50 MB |
| sqlite-vec, 200.000 × 512 float | 2,4 s | 48,9 ms | 397 MB |

### Aggiornamento incrementale: FSEvents

Dall'header `FSEvents.h` dell'SDK [11] e dalla documentazione [12]:

- Gli event ID stanno in un **database persistente per volume**. Si salvano l'ultimo ID (`FSEventStreamGetLatestEventId`) e l'UUID del volume (`FSEventsCopyUUIDForDevice`). Al riavvio di Bubo, `FSEventStreamCreateRelativeToDevice` con quel `sinceWhen` riconsegna gli eventi persi, poi un evento `HistoryDone`.
- `kFSEventStreamCreateFlagFileEvents`: eventi per file, non solo per cartella.
- `MustScanSubDirs` (con `UserDropped` o `KernelDropped`): eventi fusi o persi, "l'app deve riscansionare ricorsivamente". `RootChanged`: la cartella osservata è stata spostata o cancellata. Se l'UUID del volume cambia, o gli ID ripartono da capo (`EventIdsWrapped`): scansione completa.
- Gli eventi arrivano raggruppati secondo il parametro `latency`: è un'ottima coda di lavoro, non uno stream in tempo reale.

La scansione completa confronta mtime e dimensione, poi un hash del contenuto: si ricalcolano solo i frammenti con hash nuovo.

### Stima per 10.000 note

Ipotesi: 10.000 note Markdown, in media 3 frammenti da circa 200 token (30.000 frammenti). Tempi dalla misura A su M4 Max; un M1 base sarà più lento di alcune volte.

| Modello | Prima indicizzazione | Vettori su disco (float32 / int8) | Query totale (embedding + ricerca) |
|---|---|---|---|
| `NLContextualEmbedding` | circa 8 min (un thread) | 61 / 15 MB | circa 7 ms |
| multilingual-e5-small | circa 1 min | 46 / 12 MB | circa 15 ms |
| multilingual-e5-base | circa 3 min | 92 / 23 MB | circa 13 ms |
| bge-m3 | circa 10 min | 123 / 31 MB | circa 26 ms |
| Qwen3-Embedding-0.6B | circa 17 min in fp32 (in 4-bit MLX probabilmente meno, non misurato) | 123 / 31 MB; con MRL anche 512 o 256 dim | circa 28 ms |

Più testo e FTS5: dello stesso ordine della dimensione delle note. Con la ricerca esaustiva la RAM dell'indice è uguale al file dei vettori; si può tenere in float16 per dimezzarla.

## Proposta

1. **Modello predefinito: multilingual-e5-small via MLX Swift** (`MLXEmbedders.multilingual_e5_small`). Batte nettamente il modello di Apple in italiano (Recall@1 0,83 contro 0,60), è il più rapido, 384 dimensioni. Si scarica al primo uso (470 MB, meno se convertito in fp16); intanto funziona la sola ricerca per parole.
2. **Qualità alta opzionale: bge-m3 o Qwen3-Embedding-0.6B 4-bit.** Quasi perfetti nella prova. Qwen3 ha contesto lungo e MRL, utile per il codice. Si sceglie nelle impostazioni; cambiare modello vuol dire reindicizzare tutto.
3. **Ricerca ibrida:** FTS5 (BM25) più vettori, fusi con Reciprocal Rank Fusion. Nel codice e nei nomi propri le parole esatte contano, e FTS5 è già nel SQLite di sistema.
4. **Archivio:** un file SQLite di Bubo in Application Support (sorgente, percorso, hash, testo, vettore BLOB, modello e revisione), con la matrice caricata in memoria e la ricerca in Accelerate. sqlite-vec solo se servono filtri SQL su centinaia di migliaia di frammenti: oggi è pre-v1 e più lento. Niente SwiftData per i vettori.
5. **Sorgenti:** Secondo cervello (cartella Markdown, FSEvents); Memoria di Progetto (`~/.claude/projects/*/memory/*.md`, FSEvents); Cronologia (feature 14) letta con le API dell'SDK (`getSessionMessages`), mai col parsing del JSONL (vedi [04](04-settaggi-claude.md)). L'indice è una **cache ricostruibile**, non un archivio proprietario: cancellarlo non perde nulla.
6. **Frammenti:** per titoli Markdown, massimo circa 256–512 token con un po' di sovrapposizione; E5 tronca a 512 token, `NLContextualEmbedding` a 256.

## Il meglio da battere

Riferimento: la ricerca semantica di Core Spotlight [4] e la ricerca per parole di Obsidian. Criteri candidati:

1. **Qualità in italiano:** Recall@3 ≥ 0,95 sul set di prova di Bubo (da allargare a ≥ 200 domande reali). Oggi e5-small fa 0,97.
2. **Prima indicizzazione:** 10.000 note in ≤ 3 min su M-series di base, in background, senza scatti all'Orb.
3. **Aggiornamento:** una nota salvata è cercabile entro 5 s; nessun evento perso dopo un riavvio (ripresa con `sinceWhen`).
4. **Query:** ≤ 50 ms dal testo ai primi 10 risultati con 30.000 frammenti.
5. **Tutto in locale:** 0 byte di contenuto in rete; la rete serve solo a scaricare il modello, con consenso.
6. **Ingombro:** indice ≤ 150 MB su disco e ≤ 100 MB di RAM per 10.000 note (modello escluso).

## Rischi e casi limite

- **Modello scaricato.** 335 MB–2,3 GB, a seconda del modello. Serve un flusso con consenso, progresso e checksum. In alternativa si include e5-small nell'app (+250 MB circa).
- **Cambio di modello o di revisione:** i vettori non sono confrontabili tra modelli. Nell'indice si salvano modello e revisione e alla differenza si reindicizza. Anche `NLContextualEmbedding` ha una `revision` da fissare [2].
- **Asset Apple:** `NLContextualEmbedding` può richiedere un download (`requestAssets`) [2]; su questo Mac c'erano già.
- **Dati sensibili:** Memoria e Cronologia contengono output dei tool e segreti incollati. L'indice va escluso dai backup verso il cloud se l'utente lo chiede, e ha i permessi 600 come `~/.claude` (vedi [04](04-settaggi-claude.md)).
- **FSEvents:** eventi fusi o persi (`MustScanSubDirs`), cartella spostata (`RootChanged`), volumi esterni o di rete senza storico affidabile: in tutti questi casi, scansione completa con hash.
- **Codice:** e5-small non è addestrato sul codice. Per il codice meglio Qwen3 o EmbeddingGemma (Code 68,76 [9]), oppure solo FTS5.
- **sqlite-vec pre-v1:** se si adotta, bisogna fissarne la versione e compilarlo nell'app; il SQLite di sistema non carica estensioni [misura C].
- **Energia:** una prima indicizzazione lunga sulla GPU consuma batteria. Meglio farla con l'alimentatore collegato o a bassa priorità (QoS `.utility`).
- **Set di prova piccolo:** 30 domande scritte a mano. Prima della spec va costruito un set più grande con note vere.

## Mappa

Architettura comune in [INDEX.md](INDEX.md). L'**Indice** è una cache sul Mac: cancellarlo non perde nulla, si ricostruisce.

- **Moduli**:
  - `Index/IndexStore`: un file SQLite di sistema in Application Support. Tabella dei frammenti (fonte, Progetto, percorso, hash, testo, vettore BLOB, modello e revisione) più FTS5. Nessuna estensione, niente sqlite-vec, niente SwiftData.
  - `Index/Embedder`: multilingual-e5-small via MLX Swift (`MLXEmbedders`), Qwen3-Embedding-0.6B 4-bit come "qualità alta". Scarica i pesi al primo uso (consenso, avanzamento, checksum, versione fissata nell'app). Libera il modello dopo 60 s senza richieste.
  - `Index/VectorSearch`: matrice in RAM in float16, ricerca esaustiva con Accelerate, fusione con BM25 di FTS5 via Reciprocal Rank Fusion.
  - `Index/Sources`: una fonte per tipo. Secondo cervello (`.md` e `.txt`, FSEvents), Memoria di Progetto di tutti i Progetti (`~/.claude/projects/*/memory/`, CLAUDE.md, FSEvents), conversazioni (Sessioni di Bubo e Cronologia CLI via API dell'SDK, mai parsing del JSONL, vedi [04](04-settaggi-claude.md)).
  - `Index/Watcher`: FSEvents con event ID e UUID del volume salvati; `IndexScheduler` per la coda in QoS `.utility`.
  - `Agent/SearchTool`: strumento MCP interno `cerca` (testo, filtri per fonte e Progetto) esposto a Sessioni e Domande su Claude; riusato dalla ricerca nell'interfaccia.
- **Flusso**:
  1. Primo avvio: si indicizza subito per parole (FTS5); si chiede il consenso a scaricare il modello; con il modello pronto si calcolano i vettori in background.
  2. Bubo aperto: FSEvents mette in coda i file cambiati → confronto di mtime, dimensione e hash → nuovi frammenti (per titoli Markdown) → embedding → scrittura. Le conversazioni entrano a fine turno dell'agente.
  3. Riavvio: ripresa da `sinceWhen` salvato fino a `HistoryDone`; su `MustScanSubDirs`, `RootChanged`, `EventIdsWrapped` o UUID del volume cambiato, scansione completa via hash.
  4. Ricerca: query → embedding della query + BM25 → RRF → primi risultati con fonte, percorso e Progetto. Da `cerca`, i frammenti vanno solo a Claude o a modelli locali; agli altri fornitori solo con consenso, come per gli Allegati.
  5. Cambio di modello o di revisione: tutti i vettori si ricalcolano; intanto resta la ricerca per parole.
- **Esclusioni**: niente codice dei Progetti; nel Secondo cervello saltati `.obsidian/`, `.trash/`, cartelle nascoste, `Bubo/Sessioni/` (i Riassunti di Sessione ripetono conversazioni già indicizzate, [#54](https://github.com/mgiuditta/bubo/issues/54)) e le cartelle escluse a mano; niente PDF né immagini in v1.
- **Casi limite**:
  - modello non ancora scaricato o download rifiutato: solo FTS5, e l'interfaccia lo dice;
  - Risparmio energetico o batteria < 20%: la prima indicizzazione va in pausa e riprende da sola;
  - oltre 100.000 frammenti: avviso e proposta di escludere cartelle;
  - Secondo cervello spostato o su volume esterno senza storico affidabile: scansione completa;
  - Memoria di Progetto cambiata fuori da Bubo: si rilegge dal disco, nessuna cache oltre l'Indice;
  - frammenti con segreti incollati: restano sul Mac; 0 byte in rete dopo lo scaricamento del modello.
- **Test**:
  - set fisso italiano di 30 domande (quello della misura A) come test di regressione di Recall@1;
  - benchmark di query su 30.000 frammenti sintetici (p95);
  - prova FSEvents: salvataggio di una nota → trovabile; Bubo chiuso, modifica, riapertura → ritrovata; evento `MustScanSubDirs` simulato → scansione completa;
  - prova di rete: 0 connessioni in uscita durante indicizzazione e query dopo lo scaricamento.

## Specifica "migliore di"

Riferimento: ricerca semantica di Core Spotlight (locale ma scatola nera, solo contenuti donati) e ricerca per parole di Obsidian (niente significato).
Bubo lo supera così:
- **Qualità in italiano**: Recall@1 **≥ 0,80** sul set fisso di 30 domande (e5-small oggi 0,83; il modello di Apple 0,60).
- **Query**: **≤ 50 ms p95** dal testo ai primi risultati su 30.000 frammenti, ricerca ibrida parole + significato.
- **Freschezza**: nota salvata trovabile **entro 5 s**; **0 eventi persi** dopo un riavvio di Bubo.
- **Prima indicizzazione**: 10.000 note in **≤ 3 min** su M-series di base, in background (QoS `.utility`), in pausa con batteria < 20% o Risparmio energetico.
- **Ingombro**: **≤ 100 MB** di RAM per 10.000 note (vettori float16, modello escluso), **≤ 150 MB** su disco; modello liberato dopo 60 s di inattività.
- **Privacy**: **0 byte** di contenuto in rete dopo lo scaricamento del modello; nessun demone a Bubo chiuso; cancellare l'Indice non perde nessun dato dell'utente.
- **Una sola ricerca** per Secondo cervello, Memoria di tutti i Progetti e conversazioni passate (Sessioni e Cronologia CLI), usata sia dall'interfaccia sia dall'agente via `cerca`.

## Fonti

1. Apple, "Finding similarities between pieces of text" — https://developer.apple.com/documentation/naturallanguage/finding-similarities-between-pieces-of-text
2. Apple, `NLContextualEmbedding` (header `NLContextualEmbedding.h` dell'SDK macOS 26.5: lingue, `maximumSequenceLength`, `requestAssets`, `revision`, nota sulla similarità) — https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding
3. Apple, `SystemLanguageModel` — https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
4. Apple, WWDC24 "Support semantic search with Core Spotlight" — https://developer.apple.com/videos/play/wwdc2024/10131/
5. ml-explore/mlx-swift-lm, `Libraries/MLXEmbedders` (README, `ModelFactory.swift`) — https://github.com/ml-explore/mlx-swift-lm/tree/main/Libraries/MLXEmbedders
6. Enevoldsen et al., "MMTEB: Massive Multilingual Text Embedding Benchmark", tabella 2 — https://arxiv.org/abs/2502.13595
7. intfloat/multilingual-e5-small, model card — https://huggingface.co/intfloat/multilingual-e5-small
8. Qwen/Qwen3-Embedding-0.6B, model card (tabella MTEB multilingue con bge-m3 ed e5-large-instruct) — https://huggingface.co/Qwen/Qwen3-Embedding-0.6B
9. google/embeddinggemma-300m, model card — https://huggingface.co/google/embeddinggemma-300m
10. asg017/sqlite-vec, README e release — https://github.com/asg017/sqlite-vec
11. Header `FSEvents.h` dell'SDK macOS 26.5 (`CoreServices.framework/Frameworks/FSEvents.framework`)
12. Apple, "File System Events" — https://developer.apple.com/documentation/coreservices/file_system_events
13. Decisione: [Indice semantico condiviso](https://github.com/mgiuditta/bubo/issues/55)
14. Decisione: [Memoria e secondo cervello: cosa si scrive, quando, dove](https://github.com/mgiuditta/bubo/issues/54) (esclusione di `Bubo/Sessioni/`, `cerca` come unica lettura del Secondo cervello)


Misure A, B e C: script nella cartella temporanea della sessione, non nel repo, eseguiti su questo Mac il 2026-09-29. A: Swift 6.3.3 `-O` con NaturalLanguage e Accelerate; Python 3.12 con sentence-transformers su MPS. B: sqlite-vec v0.1.9 (Python) e `cblas_sgemv`. C: grep sulle interfacce dell'SDK 26.5 (FoundationModels, SwiftData, `sqlite3.h`); prova in C di sqlite-vec compilato staticamente con `/usr/lib/libsqlite3` (3.51.0): `sqlite3_auto_extension` non registra le funzioni, `sqlite3_vec_init(db,0,0)` sì. Il corpus del throughput sono i documenti di Bubo (CONTEXT.md, docs/features, docs/adr).
