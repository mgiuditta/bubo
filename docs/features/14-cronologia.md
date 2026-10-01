# 14 — Cronologia ricercabile per significato

Ticket: [#126](https://github.com/mgiuditta/bubo/issues/126) (ricerca), [#131](https://github.com/mgiuditta/bubo/issues/131) (prototipo della ricerca), [#138](https://github.com/mgiuditta/bubo/issues/138) (conservazione oltre 30 giorni, [ADR 0006](../adr/0006-bubo-conserva-le-conversazioni.md)), [#140](https://github.com/mgiuditta/bubo/issues/140) (scorciatoie e Palette). Mappa: [#125](https://github.com/mgiuditta/bubo/issues/125).
Il motore è l'Indice, già specificato in [indice-semantico.md](indice-semantico.md): questa feature è solo interfaccia sopra di esso, più la conservazione delle conversazioni.
Ricerca del 2026-09-30 su Agent SDK TS **0.3.282** (`sdk.d.ts` letto in locale) e CLI `claude` di sistema **2.1.285**.

> **Nota sulla ricerca.** È scritta prima delle decisioni e in tre punti è superata: la ricerca non ha una scorciatoia propria (⌘⇧F del prototipo sparisce) ma vive nella **Palette** su ⌘K ([#140](https://github.com/mgiuditta/bubo/issues/140)); branch e PR **non** sono filtri della v1 ([#131](https://github.com/mgiuditta/bubo/issues/131)); le conversazioni della Cronologia CLI cancellate prima che Bubo le copiasse **non** si recuperano e l'Indice non le mostra ([#138](https://github.com/mgiuditta/bubo/issues/138)). Valgono la Mappa e la Specifica qui sotto.

In sintesi: quasi tutti cercano solo nei **titoli**. La ricerca nel testo delle conversazioni esiste in Raycast, ChatGPT, Cursor e Nimbalyst; per significato la fanno solo Nimbalyst (con un'estensione) e claude.ai (chiedendolo a Claude). Nessuno porta al messaggio giusto dentro una conversazione passata partendo da una ricerca su tutte le conversazioni, e nessuno offre "continua da qui" da un risultato. Il dolore più forte degli utenti di Claude Code non è la ricerca: è che **la CLI cancella i transcript dopo 30 giorni** senza avvisare, anche quelli delle app sull'SDK. Bubo risponde così: si cerca nella **Palette** (⌘K, sopra l'HUD o il Panel) con parole e significato in una casella sola, grazie all'**Indice**; il clic apre la **finestra Cronologia** in sola lettura, scorsa sul messaggio trovato; da lì **Riprendi** o **Continua da qui** (`forkSession({ upToMessageId })`). Le conversazioni si conservano per sempre con una copia a specchio via `sessionStore` (ADR 0006), senza toccare `cleanupPeriodDays`.

## Ricerca

### Come si cerca e si riprende nei concorrenti

| Prodotto | Dove si cerca | Cosa si cerca | Filtri | Risultato e ripresa |
|---|---|---|---|---|
| **Claude Code CLI** | Selettore `claude --resume` e `/resume` (TUI); `Ctrl+R` per la cronologia dei prompt; `/` nella trascrizione (`Ctrl+O`) [1][2] | Si filtra scrivendo. La doc non dice su cosa: probabilmente nome, titolo, riassunto, primo prompt e branch, non il testo [1]. Si può incollare l'URL di una PR per trovare la sessione che l'ha aperta [2] | `Ctrl+W` tutti i worktree, `Ctrl+A` tutti i Progetti, `Ctrl+B` branch corrente; `--from-pr <n>` [1] | Riga: nome o titolo generato da Haiku, tempo dall'ultima attività, branch, dimensione. `Space` mostra l'anteprima, `Ctrl+R` rinomina. Le fork stanno raggruppate sotto l'originale [1]. |
| **Agent SDK** | Nessuna UI | Nessuna ricerca: `listSessions({dir, limit, offset, includeWorktrees, includeProgrammatic})` [3][misura A] | Cartella, con i suoi worktree (default `true`) | `SDKSessionInfo`: `sessionId`, `summary`, `customTitle`, `firstPrompt`, `gitBranch`, `cwd`, `tag`, `createdAt`, `lastModified`, `fileSize`. Poi `getSessionMessages` (con `limit` e `offset`), `renameSession`, `tagSession`, `deleteSession`, `forkSession({upToMessageId})` [misura A]. |
| **Claude Desktop, scheda Code** | Barra laterale; `/resume` nel prompt [4] | Sessioni CLI per titolo, cartella o branch, con anteprima [4] | Stato, Progetto, ambiente; raggruppamento per Progetto [4] | `/resume` continua la stessa sessione, non una copia. Archiviazione, anche automatica a PR fusa o chiusa [4]. |
| **claude.ai, chat** | Chiedendolo a Claude ("Search and reference chats") [5] | Per significato (RAG), con citazioni che rimandano alle chat originali [5] | Chat fuori dai progetti, oppure un solo progetto [5] | Solo piani a pagamento. La ricerca nella barra laterale non è documentata in fonte primaria [5][6]. |
| **Conductor** | `⌘⇧F` "Search Workspaces"; pagina Workspaces; `⌘F` nelle chat [7] | Nome del branch, repo, numero di PR [7] | Repo, branch, PR [7] | Si riapre o si ripristina un workspace archiviato. Si cerca il **workspace**, non il testo [7]. |
| **Superset** | Sezione "Sessions" nella barra laterale (sessioni avviate fuori dall'app) [8] | — | — | Nessuna ricerca nelle conversazioni. Dopo un riavvio le tab si perdono e si rilancia `claude --resume <id>` a mano [9]. |
| **Nimbalyst** | Barra laterale "Search sessions…" e Quick Open `⌘⇧O` [10][11] | Titoli dal vivo; **testo** con SQLite FTS; per **significato** in Quick Open con l'estensione Memory [10][11] | 7, 30 o 90 giorni oppure tutto (default 30 "per le prestazioni"); tutti, solo prompt dell'utente, solo risposte; tag; workstream [10][11] | Oltre 5.000 messaggi chiede di costruire l'indice. Importa le sessioni esterne di Claude Code e Codex [10][11]. |
| **opcode** | Browser dei Progetti su `~/.claude/projects` [12] | Il README promette "Smart Search", ma nel codice attuale della lista non c'è ricerca (da verificare) [12] | — | Riprende con tutto il contesto; timeline dei checkpoint con fork e diff. Ultima release v0.2.0 (31 ago 2025) [12]. |
| **Raycast AI Chat** | Barra laterale della cronologia [13] | "Titoli **e contenuto** dei messaggi" [13] | — | `⌘1`–`⌘0` per le prime dieci chat, chat fissate, archiviazione automatica, "Branch Chat", cestino di 60 giorni [13]. |
| **ChatGPT** | `⌘K` sul web; `⌘F` dentro una chat nell'app macOS [14][15] | Parole nel titolo o nei messaggi, più progetti, immagini e file; anche le chat archiviate [14] | Filtri per tipo di contenuto [14] | La memoria "Reference chat history" usa le chat passate in modo implicito [16]. La parità dell'app macOS con la ricerca web non è dichiarata [14]. |
| **Warp** | Pannello Conversazioni `⌘Y` (Attive / Passate); Command Search `Ctrl+R` con `ai_history:` [17][18] | Titolo; ricerca fuzzy nella cronologia di Agent Mode [17][18] | — | Una conversazione passata si riapre in una nuova tab. "Fork conversation from here" su una risposta [19]. Salvate in locale, sincronizzazione su richiesta [17]. |
| **Cursor** (riferimento) | `⌘K` nella finestra Agents [20] | Testo delle trascrizioni passate, "oltre nomi e numeri di PR", con un indice locale che regge "migliaia di conversazioni" [20] | — | `⌘F` in una conversazione, con contatore e salto tra le occorrenze [21]. |

**Cosa ne esce.**

1. **Due posti per cercare.** Uno è una palette aperta da tastiera (`⌘K` in ChatGPT e Cursor, `⌘⇧O` in Nimbalyst, `Ctrl+R` in Warp e Claude Code). L'altro è un filtro in cima alla lista (Raycast, Warp, Nimbalyst, Claude Desktop).
2. **Cercare nel testo è raro. Cercare per significato lo è ancora di più.** Il testo lo cercano Raycast, ChatGPT, Cursor e Nimbalyst. Per significato solo Nimbalyst (estensione Memory) e claude.ai, e claude.ai lo fa solo passando da Claude: non c'è un elenco di risultati da scorrere.
3. **Dal risultato al messaggio giusto: nessuno.** I risultati aprono la conversazione dall'inizio o dalla fine. Il salto all'occorrenza c'è solo dentro una conversazione già aperta (Cursor `⌘F`, Claude Code `n`/`N` nella trascrizione).
4. **Ripresa e fork sono distinti ovunque.** La ripresa continua lo stesso id. La fork copia fino a un punto e lascia intatto l'originale: `/branch` in Claude Code, "Fork from here" in Warp, "Branch Chat" in Raycast, `forkSession({upToMessageId})` nell'SDK.
5. **I filtri che contano sono Progetto, worktree, branch, PR e data.** Tutti i prodotti orientati al codice filtrano per repo, branch o PR, non per parola.

### Cosa chiedono gli utenti

- **Non perdere la cronologia.** "Claude Code silently deletes conversation transcripts after 30 days by default" [#62476](https://github.com/anthropics/claude-code/issues/62476) (aperta): chiede un default non distruttivo, un avviso al primo avvio, un cestino. Workaround: `"cleanupPeriodDays": 3650`. In [#59248](https://github.com/anthropics/claude-code/issues/59248) (aperta) la cancellazione arriva senza avviso né recupero, anche prima di 30 giorni. In VS Code i transcript spariscono ben prima di 30 giorni: [#90371](https://github.com/anthropics/claude-code/issues/90371). Cronologia persa dopo un riavvio: [#26452](https://github.com/anthropics/claude-code/issues/26452), [#9258](https://github.com/anthropics/claude-code/issues/9258).
- **Cercare nel contenuto, non solo nel titolo.** [#8849](https://github.com/anthropics/claude-code/issues/8849) (grep e ricerca fuzzy nelle sessioni, chiusa come completata senza traccia nella doc), [#16070](https://github.com/anthropics/claude-code/issues/16070), [#77523](https://github.com/anthropics/claude-code/issues/77523). Quest'ultima è aperta: "Search Sessions" in VS Code guarda solo i titoli. Gli utenti fanno grep a mano sui `.jsonl`, e chi l'ha aperta propone FTS5, frammenti e ripresa al clic. Nomi dati con `/rename` non trovati: [#43963](https://github.com/anthropics/claude-code/issues/43963).
- **Sessioni che mancano dal selettore.** Si vedono solo 5–10 sessioni recenti [#25729](https://github.com/anthropics/claude-code/issues/25729); lista incompleta [#46553](https://github.com/anthropics/claude-code/issues/46553); "No conversations found" [#19995](https://github.com/anthropics/claude-code/issues/19995), [#18311](https://github.com/anthropics/claude-code/issues/18311); indice vecchio [#25032](https://github.com/anthropics/claude-code/issues/25032); chiave del Progetto sbagliata [#31577](https://github.com/anthropics/claude-code/issues/31577).
- **Gestire, non solo trovare.** Sfogliare e cancellare per contenuto, non per UUID: [#87839](https://github.com/anthropics/claude-code/issues/87839) (aperta). Cancellare sessioni: [#26904](https://github.com/anthropics/claude-code/issues/26904), [#16901](https://github.com/anthropics/claude-code/issues/16901). Cronologia unica tra le cartelle: [#32655](https://github.com/anthropics/claude-code/issues/32655). Vedere tutta la conversazione nell'interfaccia: [#21188](https://github.com/anthropics/claude-code/issues/21188).
- **Worktree e ripresa.** In Superset `claude --resume` in un worktree nuovo non trova niente, perché le sessioni sono legate alla cartella [#5000](https://github.com/superset-sh/superset/issues/5000). Si chiede anche di riprendere da sole le sessioni dopo un riavvio [#3496](https://github.com/superset-sh/superset/issues/3496), [#7806](https://github.com/superset-sh/superset/issues/7806).
- **Ripresa che fallisce o costa.** Sessioni con extended thinking che danno errore 400 alla ripresa [#63147](https://github.com/anthropics/claude-code/issues/63147) (aperta, 62 commenti). Consumo anomalo alla ripresa [#38029](https://github.com/anthropics/claude-code/issues/38029).

### Cosa dà già la base di Bubo

- **Elenco senza scansione propria.** `listSessions({ dir })` restituisce le conversazioni di un Progetto **e dei suoi worktree** (`includeWorktrees` è `true` di default). È il caso di Bubo, dove ogni Sessione vive in una copia isolata. `includeProgrammatic: false` imita il `/resume` del terminale e nasconde le conversazioni dell'SDK [misura A].
- **Ripresa esatta.** `resume` + `forkSession: true` ha già deciso [04](04-settaggi-claude.md). `forkSession(id, { upToMessageId })` taglia la conversazione **fino a un messaggio**, e `resumeSessionAt` riprende da un messaggio preciso [misura A]. Serve a "continua da qui" su un risultato di ricerca.
- **Nessuna ricerca nell'SDK.** Titolo, riassunto e primo prompt arrivano da `listSessions`. Il testo va letto con `getSessionMessages` e indicizzato: è il lavoro che l'**Indice** fa già a fine turno ([indice-semantico.md](indice-semantico.md)).
- **Conservazione.** `cleanupPeriodDays` vale **30 giorni di default** (minimo 1) e cancella JSONL, subagent, file-history e piani [22][23][misura A]. La cartella della memoria non viene toccata [23]. Le conversazioni di Claude Desktop e Cowork sono esenti, salvo `desktopSessionCleanupPeriodDays` [misura A]. Quelle di un'app sull'SDK, come Bubo, **non** sono esenti. Le vie d'uscita:
  - `Options.settings` con un `cleanupPeriodDays` più alto. Però la pulizia è globale, quindi cambierebbe anche la conservazione della CLI dell'utente [misura A].
  - `sessionStore` (alpha): una copia in uno store di Bubo che "l'SDK non cancella mai". Con `listSessions`, `getSessionMessages` e `resume` che leggono da lì [misura A].
  - `managedSettings` **scarta** in silenzio `cleanupPeriodDays` [misura A].
- Sul Mac di prova: 473 transcript in `~/.claude/projects`, nessuno più vecchio di 31 giorni [misura B]. È coerente con la pulizia.

## Il meglio da battere

Il riferimento è **Cursor** per la ricerca nel testo (indice locale, `⌘K`) e **Nimbalyst** per i filtri (data, autore del messaggio, estensione semantica). Nessuno dei due unisce significato, parole e salto al messaggio. Nessun prodotto basato su Claude Code protegge la cronologia dalla pulizia a 30 giorni. Criteri candidati della ricerca (fissati nella Specifica in fondo):

1. **Per significato e per parole, in una sola casella.** La ricerca ibrida dell'Indice (FTS5 + vettori) su Sessioni di Bubo e Cronologia CLI, con Recall@1 ≥ 0,80 sul set italiano. Gli altri cercano per parole (Raycast, ChatGPT, Cursor) o per significato solo con estensioni o passando dal modello (Nimbalyst, claude.ai).
2. **Dal risultato al messaggio.** Ogni risultato mostra il frammento con le parole evidenziate. Un clic apre la conversazione **su quel messaggio**, in sola lettura. Oggi 0 concorrenti lo fanno partendo da una ricerca su tutte le conversazioni.
3. **"Continua da qui".** Dal messaggio trovato si apre una nuova Sessione con `forkSession({ upToMessageId })`, con meno contesto e meno Quota di una ripresa intera. Nessuno la offre da un risultato di ricerca (Warp la offre solo dentro la conversazione aperta).
4. **Filtri da codice.** Progetto e data (branch e PR, come Conductor e Claude Code, restano fuori dalla v1), con la stessa casella. Risultati in ≤ 50 ms p95 su 30.000 frammenti, come l'Indice.
5. **0 conversazioni perse in silenzio.** Le Sessioni di Bubo restano ritrovabili e riprendibili oltre i 30 giorni della CLI. Un risultato che punta a una conversazione sparita lo dice invece di fallire. È il primo dolore degli utenti ([#62476](https://github.com/anthropics/claude-code/issues/62476), [#59248](https://github.com/anthropics/claude-code/issues/59248)) e nessun concorrente lo risolve.
6. **Tutto in locale.** 0 byte della cronologia in rete. claude.ai e la memoria di ChatGPT cercano sul server.

## Rischi e casi limite

- **L'Indice ricostruibile non basta più.** L'Indice è "una cache: cancellarlo non perde nulla" ([indice-semantico.md](indice-semantico.md)). Per le conversazioni più vecchie di 30 giorni non è vero se la fonte è solo `~/.claude/projects`: il JSONL non c'è più, il risultato si trova ma non si riapre e non si riprende. Scelte possibili: copia tramite `sessionStore`, `cleanupPeriodDays` alto con consenso, oppure risultati "solo lettura" dall'Indice. Deciso in [#138](https://github.com/mgiuditta/bubo/issues/138): `sessionStore` (vedi Mappa).
- **Cronologia CLI che sparisce sotto gli occhi.** Una conversazione trovata ieri può non esserci oggi. Il risultato deve dirlo, non fallire in silenzio.
- **Ripresa costosa o rotta.** Riprendere una conversazione lunga e ferma da più di un'ora consuma Quota. Sopra 100k token la CLI propone "Resume from summary" [1]. Con extended thinking la ripresa può fallire con un 400 [#63147](https://github.com/anthropics/claude-code/issues/63147). "Continua da qui" con `upToMessageId` riduce il contesto.
- **Conversazioni dell'SDK invisibili alla CLI.** Il `/resume` del terminale e `--continue` le escludono [1]. Bubo deve mostrare `claude --resume <id>`, come già previsto in [04](04-settaggi-claude.md).
- **Stessa conversazione aperta in due processi.** I messaggi si mescolano in un solo transcript [1]. Dalla Cronologia CLI si riprende sempre con fork (CONTEXT.md).
- **Titoli poveri.** Molte conversazioni hanno solo il primo prompt come titolo. Il risultato va mostrato con il frammento trovato, non solo con il titolo.
- **Dati sensibili nei risultati.** I frammenti possono contenere segreti incollati. Restano sul Mac e seguono la regola degli Allegati prima di andare a un altro fornitore ([indice-semantico.md](indice-semantico.md)).
- **`sessionStore` è in alpha** [misura A]: l'API può cambiare tra versioni dell'SDK (ADR 0006).

## Mappa

Architettura comune in [INDEX.md](INDEX.md). Si appoggia sull'**Indice** ([indice-semantico.md](indice-semantico.md): `Index/`, strumento `cerca`), sul ponte agente, sulle Sessioni e i worktree (01), sull'Attività (06), sulla Cronologia CLI di [04](04-settaggi-claude.md) (`History/CLIHistory`) e sugli App Intents di [09](09-sistema.md). Nessun motore di ricerca nuovo.

### Dove si cerca (deciso)

Fonti: [#131](https://github.com/mgiuditta/bubo/issues/131) (varianti B + C del prototipo usa-e-getta `prototypes/cronologia-ricerca.html`, ramo `prototype/cronologia-ricerca`; scartata A, il pannello Cronologia nell'HUD, perché 340 px bastano per la lista ma non per leggere una conversazione) e [#140](https://github.com/mgiuditta/bubo/issues/140), che vince sulla scorciatoia e sul contenuto della casella.

- **Si cerca nella Palette, si legge nella finestra Cronologia.**
- **Palette**: tasto **⌘K**, solo con Bubo in primo piano. Si apre sopra la finestra di Bubo attiva, che sia l'HUD o il Panel. È una casella sola per **comandi, conversazioni e Secondo cervello**, con risultati in gruppi: Comandi per primi se la query li nomina, poi Conversazioni, poi Secondo cervello. Ogni comando mostra la sua scorciatoia, se ne ha una. Con la query vuota mostra le conversazioni recenti e i comandi più usati. ⌘⇧F non esiste.
- Il campo del pannello Cronologia dell'HUD apre la stessa Palette: una sola ricerca, niente seconda casella.
- **Da fuori da Bubo**: nessuna scorciatoia globale nuova (restano solo ⌥Spazio e ⌘⇧O). La cronologia si raggiunge con l'App Intent **"Cerca nella cronologia"** (Spotlight, Comandi rapidi, quick key facoltativa), che apre la Palette.
- **Finestra Cronologia**: fuori dall'HUD, come la finestra Costi. Nessun tasto: si apre dal menu Finestra, dalla Palette e dal clic su un risultato. Se il risultato apre la finestra Cronologia o una Sessione, parte la finestra giusta e resta visibile un solo Orb.

### Risultato (deciso)

- **Parole e significato in una casella**: la ricerca ibrida dell'Indice (BM25 di FTS5 + vettori, fusi con RRF) sulle conversazioni: Sessioni di Bubo e Cronologia CLI.
- **Una riga per conversazione**: titolo, fonte (`Sessione` / `CLI`), frammento del messaggio migliore con chi l'ha scritto (tu / agente), Progetto, tempo; "+N altri punti" se altri messaggi rispondono.
- **Perché c'è**: parole trovate evidenziate; corrispondenze solo per significato sottolineate in modo diverso.
- **Ordine**: gruppi per data (7 giorni, 30 giorni, più vecchie), per pertinenza dentro il gruppo.
- **Anteprima a destra** nella Palette: il messaggio trovato con uno prima e uno dopo.
- **Modello di embedding assente** (non scaricato o rifiutato): solo parole, e la Palette lo dice (regola dell'Indice).

### Filtri (deciso)

- **Progetto**, **data** (7 / 30 / 90 giorni / sempre), **fonte** (Sessioni / Cronologia CLI); nella Palette, con gli altri gruppi, anche **tipo** (Comandi, Conversazioni, Secondo cervello).
- Nella Palette si scrivono nella casella (`@progetto`, `7g`, `cli`) e diventano gettoni. Nella finestra Cronologia sono una colonna a sinistra con i conteggi.
- Default: tutti i Progetti, sempre.
- Branch e PR: non in v1.

### Cosa fa il clic (deciso)

- **↩ / clic**: apre la finestra Cronologia in sola lettura, **scorsa sul messaggio trovato** ed evidenziato. Tre colonne: filtri, risultati, conversazione; si continua a cercare da lì. ⌘G salta al punto trovato successivo nella stessa conversazione.
- **Continua da qui** (⌘↩, o il pulsante su qualunque messaggio al passaggio): nuova Sessione con `forkSession({ upToMessageId })` nel Progetto della conversazione, in un worktree nuovo, ferma in attesa del prompt. Vale per Sessioni di Bubo e Cronologia CLI.
- **Riprendi** (⌥↩, pulsante nella finestra):
  - Sessione di Bubo → la stessa Sessione (`resume`). Se la Sessione è aperta nell'HUD, la porta davanti: nessun secondo processo sulla stessa conversazione.
  - Sessione di Bubo **Fusa o Archiviata** → il worktree non c'è più, quindi la stessa conversazione (`resume`) riparte in un worktree nuovo: sul branch tenuto se la Sessione era Archiviata senza merge, dal branch principale se era Fusa. La Fase torna Aperta.
  - Cronologia CLI → sempre una nuova Sessione, fork dell'intera conversazione (invariante di CONTEXT.md).
- **Comando per il terminale**: la finestra mostra `claude --resume <id>` per le Sessioni di Bubo, invisibili al `/resume` della CLI ([04](04-settaggi-claude.md)).
- **Oltre 30 giorni**: avviso "si riprende dalla copia di Bubo, ma non si riavvolge sui file" (ADR 0006).
- **Conversazione non più disponibile**: se al clic la fonte non c'è più (né in `~/.claude` né nella copia di Bubo), la finestra mostra ciò che l'Indice ha con "Conversazione non più disponibile: non si può riprendere", e Riprendi / Continua da qui sono spenti.

### Conservazione (decisa)

Fonti: [#138](https://github.com/mgiuditta/bubo/issues/138), [ADR 0006](../adr/0006-bubo-conserva-le-conversazioni.md).

- **Sessioni di Bubo**: copia a specchio con `sessionStore` nel database locale di Bubo. `append` scrive dopo la scrittura locale; `load` rimette la conversazione in un JSONL temporaneo per `resume`. Subagent inclusi (`listSubkeys`). Versione dell'SDK fissata, perché l'API è in alpha; se cambia, il ripiego è copiare il JSONL alla fine di ogni turno, con gli stessi dati.
- **Scrittura locale**: `sessionStore` non funziona con `persistSession: false`, quindi i turni delle Sessioni girano con `persistSession: true` e un `sessionId` dato da Bubo (uno per turno, salvato nella Sessione). `claude` scrive il suo transcript in `~/.claude/projects`, come dalla riga di comando, e la pulizia della CLI lo cancella; Bubo non scrive nulla in `~/.claude`. Le Domande restano senza transcript. Il database è `~/Library/Application Support/Bubo/Conversazioni.sqlite`; lo scrive solo il ponte.
- **Cronologia CLI**: Bubo la copia di default con `importSessionToStore` quando la vede per la prima volta. L'interruttore "Conserva anche le conversazioni della riga di comando" nelle Impostazioni lo spegne; spegnendolo le copie si cancellano.
- **`cleanupPeriodDays` non si tocca**: 0 modifiche a `~/.claude/settings.json`.
- **Durata**: per sempre. Le Impostazioni mostrano lo spazio occupato. Eliminare una Sessione in Bubo cancella la sua copia; Archiviata non cancella nulla.
- **File-history**: non entra nello store. Oltre i 30 giorni una Sessione si riprende ma non si riavvolge sui file; dopo Fusa o Archiviata il worktree non c'è più comunque.
- **Già cancellate** dalla CLI prima che Bubo le vedesse: non si recuperano e l'Indice non le mostra.
- **Indice**: resta ricostruibile, perché le fonti delle conversazioni sono ora nello store.

### Moduli

Architettura comune in [INDEX.md](INDEX.md). Moduli nuovi: `Palette/` e `History/` (dove 04 ha già messo `History/CLIHistory`).

- `Palette/PaletteWindow`: pannello AppKit sopra la finestra attiva (HUD o Panel), casella, gruppi, anteprima a destra, piede con i tasti (↩, ⌘↩, ⌥↩, esc).
- `Palette/PaletteQuery`: trasforma `@progetto`, `7g`, `cli` in gettoni di filtro; il resto è il testo della query.
- `Palette/CommandCatalog`: comandi della Palette presi dai menu, ognuno con la sua scorciatoia; i più usati per la query vuota.
- `History/ConversationSearch`: chiama la ricerca dell'Indice (la stessa di `cerca`) con fonte = conversazioni e i filtri; raggruppa i frammenti per conversazione (messaggio migliore, "+N altri punti"), per data e per pertinenza; segnala se ogni frammento arriva dalle parole, dal significato o da entrambi, con le posizioni da evidenziare. Il gruppo Secondo cervello della Palette usa la stessa ricerca con fonte = Secondo cervello.
- `History/ConversationReader`: legge i messaggi con `getSessionMessages` (da `~/.claude` o dallo store), scorre sul messaggio, ⌘G tra i punti trovati; stato "non più disponibile".
- `History/HistoryWindow`: finestra Cronologia a tre colonne (filtri con conteggi, risultati, conversazione) in SwiftUI dentro una finestra AppKit.
- `History/ResumeActions`: Riprendi (`resume` per le Sessioni di Bubo, fork intero per la Cronologia CLI) e Continua da qui (`forkSession({ upToMessageId })`) verso `Sessions/` (01), con il worktree nuovo.
- `History/ConversationStore`: adattatore `sessionStore` sul database locale di Bubo (`append`, `load`, `listSubkeys`), import della Cronologia CLI con `importSessionToStore`, riparazione dopo `mirror_error`, spazio occupato per le Impostazioni.
- `History/CLIHistory` (da 04): in più, segnala a `ConversationStore` ogni conversazione vista per la prima volta.
- `System/Intents` (09): App Intent "Cerca nella cronologia", che apre la Palette.
- Riuso: `Index/` e `Agent/SearchTool` (Indice), `Sessions/` (01), Attività (06), `Agent/AgentBridge` per `resume` e `forkSession`.

Requisito sull'Indice: ogni frammento di conversazione porta `sessionId`, id del messaggio, autore (tu / agente) e data, e la ricerca restituisce da quale ramo della fusione arriva (parole, significato) con le posizioni FTS5 da evidenziare.

### Flusso

1. **Conservazione**: fine di ogni scrittura della Conversazione dell'agente → `append` nello store. `CLIHistory` vede una conversazione nuova della CLI → `importSessionToStore` (se l'interruttore è acceso). `mirror_error` → segnale nella Sessione → a fine turno `importSessionToStore` ripara la copia.
2. **Indicizzazione**: fine turno → l'Indice legge le conversazioni dallo store e dalle API dell'SDK, mai dal JSONL ([indice-semantico.md](indice-semantico.md)).
3. **Ricerca**: ⌘K (o App Intent, o campo del pannello Cronologia) → Palette sopra la finestra attiva → testo + gettoni → `ConversationSearch` → righe per conversazione con frammento e anteprima.
4. **Apertura**: ↩ → finestra Cronologia → `ConversationReader` carica la conversazione → scorre sul messaggio trovato ed evidenziato.
5. **Ripresa**: ⌘↩ → `forkSession({ upToMessageId })` → nuova Sessione in un worktree nuovo, ferma in attesa del prompt. ⌥↩ → `resume` della stessa Sessione, oppure fork intero per la Cronologia CLI; oltre 30 giorni `load` dallo store in un JSONL temporaneo.

### Casi limite

- **Conversazione sparita tra la ricerca e il clic** (CLI che pulisce, copia della Cronologia CLI spenta): sola lettura con "Conversazione non più disponibile: non si può riprendere", azioni spente; 0 errori silenziosi. Al controllo successivo della fonte, l'Indice la toglie.
- **Interruttore della Cronologia CLI spento**: copie cancellate; le conversazioni della CLI restano cercabili finché la CLI le tiene.
- **Oltre 30 giorni**: ripresa dallo store senza file-history; avviso prima di riprendere.
- **Ripresa che fallisce** (errore 400 con extended thinking, `startup_failure_reason` sul worktree, vedi 01): l'errore resta visibile nella Sessione; Continua da qui resta disponibile come ripresa con meno contesto.
- **Ripresa lunga**: Continua da qui porta solo i messaggi fino a quello scelto, quindi meno contesto e meno Quota.
- **Sessione di Bubo già aperta**: Riprendi la porta davanti, nessun secondo processo sulla stessa conversazione.
- **Sessione Fusa o Archiviata**: Riprendi ricrea il worktree (branch tenuto, o branch principale dopo il merge) e riporta la Fase ad Aperta; nessun file del vecchio worktree torna.
- **Modello di embedding assente**: solo parole, detto nella Palette; nessuna sottolineatura "per significato".
- **Titoli poveri**: il frammento viene sempre prima del titolo nella riga.
- **Segreti nei frammenti**: restano sul Mac; la Palette e la finestra non inviano nulla in rete.
- **Palette dal Panel**: si apre sopra il Panel; se il risultato apre la finestra Cronologia o una Sessione nell'HUD, resta visibile un solo Orb.
- **VoiceOver e tastiera**: ogni azione della Palette e della finestra si fa da tastiera (↑↓, ↩, ⌘↩, ⌥↩, ⌘G, esc); righe con etichette che dicono fonte, Progetto, autore e data; Riduci movimento: nessuno scorrimento animato, salto diretto al messaggio.

### Test

- Recall@1 sul set fisso italiano dell'Indice più un set fisso di 30 domande su conversazioni reali, con il messaggio atteso.
- Benchmark della ricerca su 30.000 frammenti di conversazione (p95); tempo di apertura della Palette dopo ⌘K dall'HUD e dal Panel.
- Apertura sul messaggio: per ogni domanda del set, la finestra Cronologia mostra evidenziato il messaggio del risultato.
- Continua da qui: la nuova Sessione contiene tutti i messaggi fino a `upToMessageId` e nessuno dopo; l'originale resta intatto.
- Riprendi: Cronologia CLI → sempre nuovo id di Sessione; Sessione di Bubo → stesso id.
- Conservazione con data spostata a 30, 90 e 365 giorni: le Sessioni di Bubo si riaprono e si riprendono; `~/.claude/settings.json` invariato (hash).
- `mirror_error` simulato: copia riparata a fine turno, nessun messaggio mancante confrontando store e transcript.
- Transcript cancellato a mano dopo l'indicizzazione con copia spenta: messaggio "non più disponibile", azioni spente.
- Prova di rete: 0 connessioni in uscita durante ricerca, apertura e anteprima.
- Registro delle scorciatoie: 0 globali nuove; "Cerca nella cronologia" presente in Spotlight e Comandi rapidi.
- Accessibilità: audit AppKit della Palette e della finestra, audit SwiftUI delle righe e della conversazione.

### Ordine di costruzione

1. **Conservazione**: `History/ConversationStore` con `sessionStore`, import della Cronologia CLI, interruttore e spazio nelle Impostazioni. Prima di tutto, perché ogni giorno senza copia perde conversazioni. Dipende dal ponte agente ([#66](https://github.com/mgiuditta/bubo/issues/66)), da 01 (Sessioni) e da `History/CLIHistory` di 04.
2. **Palette con le conversazioni**: `Palette/` (⌘K dall'HUD e dal Panel, gettoni, anteprima) e `History/ConversationSearch`. Dipende dall'Indice con le conversazioni ([#111](https://github.com/mgiuditta/bubo/issues/111), [#112](https://github.com/mgiuditta/bubo/issues/112), [#113](https://github.com/mgiuditta/bubo/issues/113)) e dalla shell dell'HUD e del Panel.
3. **Finestra Cronologia e ripresa**: `HistoryWindow`, `ConversationReader` sul messaggio, `ResumeActions` (Riprendi, Continua da qui), avvisi oltre 30 giorni e "non più disponibile". Dipende da 1, 2, 01 (worktree nuovo) e 06 (Attività della Sessione ripresa).
4. **Palette unica e ingressi**: gruppi Comandi (`CommandCatalog`) e Secondo cervello, voce del menu Finestra, App Intent "Cerca nella cronologia". Dipende da 2, da 12 (Secondo cervello nell'Indice) e da 09 (`System/Intents`).

## Specifica "migliore di"

Miglior concorrente per la ricerca: **Cursor** (testo delle trascrizioni con indice locale su `⌘K`, salto tra le occorrenze solo dentro una conversazione aperta). Per i filtri: **Nimbalyst** (data, autore, significato con un'estensione). Per la conservazione: nessuno, perché nessuna app sull'SDK tiene le conversazioni oltre i 30 giorni.
Bubo li supera così:

1. **Parole e significato in una casella**: Recall@1 **≥ 0,80** sul set fisso italiano (Indice + 30 domande su conversazioni), in una sola ricerca per Sessioni di Bubo e Cronologia CLI.
2. **Veloce**: Palette aperta in **≤ 100 ms** dopo ⌘K, dall'HUD e dal Panel; risultati in **≤ 50 ms p95** su 30.000 frammenti.
3. **Dal risultato al messaggio**: il **100%** delle aperture dal set di test mostra la finestra Cronologia scorsa sul messaggio trovato ed evidenziato, con **1 tasto** (↩).
4. **Continua da qui**: **1 tasto** (⌘↩) da un risultato a una nuova Sessione con `forkSession({ upToMessageId })`; **0 messaggi** dopo quello scelto nella nuova Sessione; originale intatto.
5. **Ripresa corretta**: **100%** delle riprese dalla Cronologia CLI in una nuova Sessione, **0** riprese sullo stesso id; Sessione di Bubo ripresa con lo stesso id.
6. **0 conversazioni perse**: **0** Sessioni di Bubo perse dopo 30, 90 o 365 giorni (si riaprono e si riprendono, test con data spostata); **0 modifiche** a `~/.claude/settings.json`.
7. **Cronologia CLI conservata**: una conversazione della CLI arriva nello store **entro un giorno** dalla prima volta che Bubo la vede (interruttore acceso); dopo un `mirror_error`, **0 buchi** a fine turno.
8. **Mai in silenzio**: un risultato che punta a una conversazione sparita si apre con "Conversazione non più disponibile" e azioni spente: **0** errori muti.
9. **Tutto in locale**: **0 byte** della cronologia in rete durante ricerca, apertura e anteprima.
10. **Ingressi sobri**: **0** scorciatoie globali nuove; "Cerca nella cronologia" compare in Spotlight e Comandi rapidi; ogni comando della Palette mostra la sua scorciatoia, se ne ha una.

## Fonti

1. Claude Code, "Manage sessions" — https://code.claude.com/docs/en/sessions
2. Claude Code, `CHANGELOG.md` (v2.1.122 URL della PR nel selettore, v2.1.129 `Ctrl+R`, v2.1.83 ricerca nella trascrizione, v2.1.223 `--resume` su tutti i Progetti) — https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
3. Claude Code, "Agent SDK — Sessions" — https://code.claude.com/docs/en/agent-sdk/sessions ; riferimento TypeScript — https://code.claude.com/docs/en/agent-sdk/typescript
4. Claude Code, "Desktop" — https://code.claude.com/docs/en/desktop
5. Claude Help Center, "Use Claude's chat search and memory to build on previous context" — https://support.claude.com/en/articles/11817273-use-claude-s-chat-search-and-memory-to-build-on-previous-context
6. Claude Help Center, "Claude Cowork and Chat are one Claude" — https://support.claude.com/en/articles/16761823-claude-cowork-and-chat-are-one-claude
7. Conductor, changelog (0.26.0 Search Workspaces, 0.28.0 pagina Workspaces, 0.31.0 `⌘F`, 0.25.6 fork) — https://www.conductor.build/changelog
8. Superset, docs "Workspaces" — https://docs.superset.sh/llms.mdx/workspaces ; indice — https://docs.superset.sh/llms.txt
9. Superset, issue #3496, #6946, #7806, #5000, #5126, #6846 — https://github.com/superset-sh/superset/issues
10. Nimbalyst, `SessionHistory.tsx` — https://github.com/nimbalyst/nimbalyst/blob/main/packages/electron/src/renderer/components/AgenticCoding/SessionHistory.tsx
11. Nimbalyst, release v0.66.5, v0.66.7, v0.70.0, v0.74.3, v0.79.0 — https://github.com/nimbalyst/nimbalyst/releases
12. opcode, README e `src/components/SessionList.tsx` — https://github.com/winfunc/opcode
13. Raycast, "AI Chat" — https://manual.raycast.com/ai/ai-chat
14. OpenAI Help, "Search chat history" — https://help.openai.com/en/articles/10056348 (fetch diretto bloccato, letto dagli estratti indicizzati)
15. OpenAI Help, "ChatGPT macOS app release notes" — https://help.openai.com/en/articles/9703738-chatgpt-macos-app-release-notes
16. OpenAI Help, "Memory FAQ" — https://help.openai.com/en/articles/8590148-memory-faq
17. Warp, "Agent conversations" — https://docs.warp.dev/agents/using-agents/agent-conversations
18. Warp, "Command Search" — https://docs.warp.dev/terminal/entry/command-search/
19. Warp, "Conversation forking" — https://docs.warp.dev/agent-platform/local-agents/interacting-with-agents/conversation-forking/
20. Cursor, changelog 3.11 (10 lug 2026) — https://cursor.com/changelog/side-chat
21. Cursor, "Conversation search" — https://cursor.com/help/ai-features/conversation-search
22. Claude Code, "Settings reference", `cleanupPeriodDays` — https://code.claude.com/docs/en/settings-reference#cleanupperioddays
23. Claude Code, "The .claude directory", pulizia automatica — https://code.claude.com/docs/en/claude-directory#cleaned-up-automatically
24. Decisioni: [Prototipo: ricerca nella cronologia](https://github.com/mgiuditta/bubo/issues/131), [Conservazione delle conversazioni oltre i 30 giorni](https://github.com/mgiuditta/bubo/issues/138) e [ADR 0006](../adr/0006-bubo-conserva-le-conversazioni.md), [Scorciatoie e ingressi delle feature 14–19](https://github.com/mgiuditta/bubo/issues/140)

Misura A: lettura di `sdk.d.ts` di `@anthropic-ai/claude-agent-sdk` 0.3.282 su questo Mac il 2026-09-30 (`listSessions`, `ListSessionsOptions`, `SDKSessionInfo`, `getSessionMessages`, `forkSession`, `resumeSessionAt`, `tagSession`, `deleteSession`, `SessionStore`, `Settings.cleanupPeriodDays` e `desktopSessionCleanupPeriodDays`, `managedSettings`).
Misura B: conteggio dei `*.jsonl` in `~/.claude/projects` e di quelli con mtime oltre 31 giorni, su questo Mac il 2026-09-30.
