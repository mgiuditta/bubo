# 13 — Memoria di Progetto e Riassunto di Sessione

Ticket: [#46](https://github.com/mgiuditta/bubo/issues/46) (ricerca), [#54](https://github.com/mgiuditta/bubo/issues/54) (decisioni), [#55](https://github.com/mgiuditta/bubo/issues/55) (Indice). Mappa: [#42](https://github.com/mgiuditta/bubo/issues/42).
La ricerca copre anche il Secondo cervello, specificato in [12-secondo-cervello.md](12-secondo-cervello.md). L'Indice è in [indice-semantico.md](indice-semantico.md).
Ricerca del 2026-09-29 su CLI `claude` **2.1.285**, Agent SDK TS **0.3.285**, Obsidian **1.13.7**.

In sintesi: la memoria nativa di Claude Code copre già la Memoria di Progetto. CLAUDE.md a livelli la scrive l'utente; la memoria automatica (`~/.claude/projects/<p>/memory/`, indice `MEMORY.md` + un file per ricordo) la scrive Claude. L'Agent SDK carica entrambe senza opzioni e la memoria è **condivisa tra i worktree dello stesso repo**, quindi tutte le Sessioni di un Progetto la vedono. Bubo non deve inventare un archivio: deve **mostrarla**, farla **modificare** e **segnalare** quando cresce troppo. Per il secondo cervello una cartella Markdown scritta direttamente su disco basta: frontmatter YAML, wikilink tra virgolette nelle proprietà, cartella dedicata. Obsidian (CLI, URI, Local REST API) resta un'aggiunta, perché tutte e tre le vie chiedono l'app aperta.

## Ricerca

### Memoria nativa di Claude Code

**Due sistemi, entrambi caricati a ogni conversazione** [1]:

| | CLAUDE.md | Memoria automatica |
|---|---|---|
| Chi scrive | L'utente | Claude |
| Contenuto | Istruzioni e regole | Cose imparate: preferenze, correzioni, contesto non ricavabile dal codice |
| Ambito | Progetto, utente, organizzazione | Per repository, **condivisa tra worktree** |
| Caricamento | Intero (salta i file oltre 4 MiB; consigliate < 200 righe) | Prime **200 righe o 25 KB** di `MEMORY.md` |

**CLAUDE.md a livelli** [1], in ordine di caricamento, dal più generale al più specifico:

- gestito: `/Library/Application Support/ClaudeCode/CLAUDE.md` (macOS), oppure la chiave `claudeMd` nei managed settings; non si esclude;
- utente: `~/.claude/CLAUDE.md` e `~/.claude/rules/*.md`;
- progetto: `./CLAUDE.md` o `./.claude/CLAUDE.md`, `.claude/rules/**/*.md` (con `paths:` nel frontmatter si caricano solo quando Claude legge un file che corrisponde);
- locale: `./CLAUDE.local.md`, da mettere in `.gitignore`.

I file si **concatenano**, non si sovrascrivono. Si caricano quelli delle cartelle padre all'avvio e quelli delle sottocartelle quando Claude legge lì. Import con `@percorso`, fino a 4 salti. Un import esterno alla cartella chiede approvazione una volta. I commenti HTML a blocco vengono tolti prima dell'iniezione. `AGENTS.md` si legge al posto di CLAUDE.md se questo manca (da 2.1.277; impostazione **Project instructions**). `claudeMdExcludes` salta file nei monorepo. Dopo `/compact` il CLAUDE.md della radice si rilegge da disco [1].

**Memoria automatica** [1]:

- Cartella `~/.claude/projects/<progetto>/memory/`. `<progetto>` deriva dal repo git: **tutti i worktree e le sottocartelle** dello stesso repo condividono la stessa cartella. Fuori da git si usa la radice del progetto.
- `MEMORY.md` è un indice, una riga per ricordo. I file di argomento (`user_role.md`, `feedback_testing.md`, …) **non** si caricano all'avvio: Claude li legge quando servono.
- Quattro tipi nel frontmatter (`type`): `user`, `feedback`, `project`, `reference`. Claude non salva ciò che si ricava dal codice né ciò che CLAUDE.md dice già.
- Dalla 2.1.214 Claude Code scrive il campo `modified` (ISO 8601) nel frontmatter a ogni scrittura.
- Oltre il limite la scrittura riesce, ma Claude Code risponde con un errore che chiede di riscrivere l'indice, perché la parte in eccesso si perde al caricamento successivo.
- La pulizia a 30 giorni dei transcript (`cleanupPeriodDays`) **non** tocca la cartella memory.
- Solo su questo Mac: niente sincronizzazione tra macchine.
- Si accende e spegne con `/memory` (salva `autoMemoryEnabled` in `~/.claude/settings.json`), per progetto con `autoMemoryEnabled: false`, oppure con `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`. La cartella si sposta con `autoMemoryDirectory`, ignorata se arriva dal `settings.json` di progetto versionato [1][3].
- "Ricordati che…" va nella memoria automatica; "aggiungilo a CLAUDE.md" va in CLAUDE.md [1].

**Comandi** [1]: `/memory` elenca i file di memoria (anche quelli non ancora creati), attiva o spegne la memoria automatica e apre la cartella. `/context` mostra i "Memory files" caricati. `/init` genera CLAUDE.md e legge le regole di Cursor, Copilot, Windsurf e Cline. `/import` copia una volta la configurazione di un altro agente (da 2.1.213). `/doctor prompt-audit` trova istruzioni vecchie o in conflitto (da 2.1.283).

**Memoria dei subagent** [2]: campo `memory: user|project|local` → `~/.claude/agent-memory/<nome>/`, `.claude/agent-memory/<nome>/`, `.claude/agent-memory-local/<nome>/`. Stesso limite 200 righe / 25 KB. Si spegne insieme alla memoria automatica.

**Consolidamento ("auto-dream").** `sdk.d.ts` 0.3.285 ha l'impostazione `autoDreamEnabled`: "Enable background memory consolidation (auto-dream). When set, overrides the server-side default" [3]. La documentazione ufficiale non la descrive. Fonti secondarie parlano di un comando `/dream` non documentato che unisce i doppioni, risolve le contraddizioni e accorcia l'indice [16]. Non ci si può contare come comportamento stabile.

**Cosa espone l'Agent SDK** (fonti [3][4]):

- Se `settingSources` non si passa, CLAUDE.md, rules e CLAUDE.local.md si caricano come nella CLI. La memoria automatica si carica **sempre**, anche con `settingSources: []`: la spengono solo `autoMemoryEnabled: false` o `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`. L'agente scrive i ricordi con i tool `Write` e `Edit` standard, niente tool dedicato: senza quei tool non salva.
- Hook `InstructionsLoaded`: `file_path`, `memory_type` (`User`, `Project`, `Local`, `Managed`), `load_reason` (`session_start`, `nested_traversal`, `path_glob_match`, `include`, `compact`).
- `getContextUsage()` → `memoryFiles` con i token per file.
- Messaggio `system/memory_recall` (`SDKMemoryRecallMessage`): modalità `select` (file interi) o `synthesize` (paragrafo scritto da Sonnet), `scope` `personal|team|organization`. Serve a mostrare "Recalled from memory" nell'interfaccia. Gli ambiti team/organization non sono documentati.
- Hook `PreCompact` e `PostCompact` (quest'ultimo con `compact_summary`), `SessionEnd` (`reason`: `clear`, `resume`, `logout`, `prompt_input_exit`, `other`), `Stop`.
- `SDKSessionInfo.summary` e il titolo generato (`aiTitle`) per la cronologia; vedi la ricerca 04.

**Misura C** (questo Mac): 467 cartelle in `~/.claude/projects`, 46 con `memory/`, 22 con `MEMORY.md`, il più lungo di 34 righe (lontano dal limite di 200). Tipi dei file di argomento: 79 `project`, 13 `feedback`, 6 `reference`, 1 `user`. Nessuna cartella `session-memory` presente. La memoria di Bubo stesso è in `-Users-matteo-dev-bubo/memory/` e la vedono anche i worktree degli agenti.

### Come fanno i concorrenti

| App | Memoria | Riassunti | Cosa piace | Cosa manca |
|---|---|---|---|---|
| **Claude Code (CLI e app)** | CLAUDE.md a livelli + memoria automatica in Markdown [1] | Titolo e `summary` per sessione, compattazione | File in chiaro, modificabili, condivisi tra worktree | La memoria automatica si vede solo aprendo la cartella o con `/memory`. Nessun avviso visivo quando si salva, a parte "Saved N memories" |
| **Cline — Memory Bank** | **Convenzione**, non funzione: istruzioni in `.clinerules/memory-bank.md` che chiedono di tenere `projectbrief.md`, `productContext.md`, `activeContext.md`, `systemPatterns.md`, `techContext.md`, `progress.md` [5] | Solo a comando: "update memory bank" | Funziona con qualunque agente, file nel repo | Va tenuta a mano. Vale quanto la disciplina di chi la aggiorna [5] |
| **Cursor — Memories** | Generate da un modello laterale e approvate dall'utente, per progetto. **Tolte in 2.1.x** (staff, 25/11/2025); si esportano con "Export memories" in `.mdc` e diventano Rules [6][7] | — | — | Tolte: al loro posto le Rules scritte a mano |
| **Windsurf / Devin desktop — Cascade Memories** | Generate da sole o su richiesta ("create a memory of…"). Legate al workspace, salvate in `~/.codeium/windsurf/memories/`, non nel repo, non consumano crediti. Rules in `.devin/rules/` o `.windsurf/rules/` (globali 6.000 caratteri, workspace 12.000 per file) con attivazione `always_on`, `model_decision`, `glob`, `manual` [8] | — | Nessun costo, attivazione a glob | Formato proprietario fuori dal repo: non passa ad altri strumenti |
| **Conductor** | Nessuna memoria propria: usa quella di Claude Code. Dalla 0.28.0 (22/12/2025) ogni workspace ha una cartella `.context` per contesto condiviso tra agenti e non versionato [9][10] | — | Semplice: una cartella | Nessuna memoria né riassunto tra workspace |
| **Nimbalyst** | Nessuna memoria automatica documentata. Tracker Markdown con collegamento sessione ↔ elemento, import delle sessioni di Claude Code, "evidence trails" [11] | Collegamento manuale al tracker, non riassunto | Tracciabilità da idea a commit | Nessun riassunto automatico, il collegamento è a mano |
| **Copilot for Obsidian** | Due memorie in Markdown dentro il vault: "Recent Conversations" (titolo di 2–8 parole + riassunto di 2–3 frasi generati da LLM a fine chat, buffer delle ultime 30, da 10 a 50) e "Saved Memories" (elenco puntato fuso da LLM quando l'utente chiede di ricordare) [12]. Chat salvate come note in `copilot/copilot-conversations/` con nome `{$topic}@{$date}_{$time}` [13] | **Sì**, a fine conversazione, in background | Il riassunto di fine chat è proprio il pattern che vuole Bubo; tutto in Markdown nel vault | La cartella `copilot/` dentro il vault finisce nella ricerca se non la si esclude [13] |
| **Basic Memory** (MCP) | Note Markdown con "observations" e "relations" (wikilink); indice SQLite locale con embedding locali; tool MCP `write_note`, `read_note`, `search_notes`, `build_context`, `recent_activity` [14] | L'agente scrive note su richiesta | Stesse note leggibili in Obsidian | Sintassi propria; Python/uv; AGPL |

### Temi ricorrenti

1. **Due memorie distinte**: quello che l'utente prescrive (CLAUDE.md, Rules) e quello che l'agente impara (memoria automatica, Cascade Memories). Tutti le separano.
2. **Il formato proprietario perde**: Cursor ha tolto le Memories e ha dovuto dare un export verso le Rules [7]. Windsurf le tiene fuori dal repo [8]. Il Markdown in chiaro (Claude Code, Cline, Copilot) sopravvive.
3. **L'indice cresce e degrada**: Claude Code mette un tetto a 200 righe / 25 KB con avviso [1] e sperimenta il consolidamento [3]. Copilot usa un buffer a rotazione [12]. Cline aggiorna solo a mano [5].
4. **Il riassunto di fine sessione** esiste solo in Copilot for Obsidian [12]. Nessun concorrente agentico lo scrive in una cartella dell'utente.

## Secondo cervello (feature 12)

### Strumenti

| Strumento | Cosa fa | Indice / embedding | App aperta? | Stato |
|---|---|---|---|---|
| **Smart Connections** | Note e blocchi collegati per somiglianza | Modello di embedding locale incluso, senza chiavi. Indice in `.smart-env/` nel vault, che il plugin aggiunge a `.gitignore` [15][17] | Sì, plugin | 5,5k stelle, commit 2026-09-24. Chat separata in Smart Chat; Pro a parte |
| **Copilot for Obsidian** | Chat agentica (opencode, Claude, Codex) sul vault | Ricerca locale "Miyo", app separata; la cartella di Copilot è esclusa [13] | Sì | 7,8k stelle, commit 2026-09-29 |
| **Khoj** | "AI second brain" self-hosted; Markdown, org, PDF, Notion | Server con Postgres/pgvector, Docker o pip; web su `localhost:42110`; per la chat offline minimo 8 GB di RAM [18][19] | No, ma serve il server | 37,5k stelle, AGPL, ultimo push 2026-08-02 |
| **Obsidian URI** | `obsidian://open|new|daily|unique|search`; `new` con `content`, `append`, `overwrite`, `silent`, `x-success`; `open` con `prepend` o `append` (unisce le proprietà). I valori vanno codificati (`/` → `%2F`) [20] | — | Sì, la lancia | Ufficiale |
| **Obsidian CLI** | `obsidian create|read|append|prepend|search|search:context|daily:append|property:set`, `vault=<nome>`, uscita `json|tsv|md` [21] | Ricerca di Obsidian | Sì (il primo comando la lancia). Installer 1.12.7+, symlink `/usr/local/bin/obsidian` con password admin | Ufficiale |
| **Local REST API** | HTTPS `127.0.0.1:27124` (HTTP 27123 facoltativo), bearer token, certificato autofirmato; CRUD `/vault/`, `/active/`, `/search/`, `/commands/`, PATCH mirato su intestazione, blocco o frontmatter; server MCP integrato su `/mcp/` [22] | Ricerca di Obsidian | Sì | 3k stelle, commit 2026-09-28 |
| **MCP per Obsidian** | `mcp-obsidian` (4,5k stelle): 7 tool via Local REST API [23]; `obsidian-mcp-server` (cyanheads, 0,7k); `obsidian-mcp` (StevenStavrakis, 0,7k, su file) | — | Sì se passa da REST API | Comunità |
| **obsidian-skills** (kepano) | Agent Skills per Markdown di Obsidian, Bases, JSON Canvas, CLI; compatibili con Claude Code [24] | — | Solo per la parte CLI | 49k stelle, MIT |

### Convenzioni per scrivere note

- **Proprietà** = frontmatter YAML tra `---`. Tipi: testo, lista, numero, checkbox, data (`YYYY-MM-DD`), data e ora (ISO 8601), tag. Predefinite: `tags`, `aliases`, `cssclasses`. I link interni nelle proprietà **vanno tra virgolette**: `"[[Nota]]"` [25].
- **Link**: wikilink `[[Nota]]` predefinito, oppure Markdown `[testo](Nota%20nome.md)` se l'utente ha tolto "Use [[Wikilinks]]". `[[Nota#Titolo]]`, blocchi `#^id`, alias `[[Nota|testo]]`. Obsidian aggiorna i link quando si rinomina un file, ma solo se il file lo rinomina Obsidian [26].
- **Cartella dedicata**: Copilot usa una radice configurabile (`copilot/`) con sottocartelle ed esclude la radice dalla propria ricerca [13]. Conductor usa `.context` [10]. Per Bubo il candidato è `Bubo/` con una nota per Sessione.
- **Riconoscere un vault**: cartella `.obsidian/` nella radice (convenzione osservata). L'elenco dei vault è in `~/Library/Application Support/obsidian/obsidian.json` (`vaults.<id>.path`, `ts`, `open`), un file **interno e non documentato**: si usa solo per proporre una scelta.
- **Scrittura diretta su disco**: è l'unica via che funziona con Obsidian chiuso e con qualunque cartella Markdown (Logseq, iA Writer, cartella qualsiasi). Obsidian rileva i file cambiati all'esterno. Le altre vie (URI, CLI, REST) chiedono l'app aperta.

## Il meglio da battere

**Memoria di Progetto.** Il riferimento è Claude Code stesso: file in chiaro, condivisi tra worktree, tetto con avviso. Gli manca la visibilità: nessuno mostra cosa si è salvato e quando. Criteri candidati:

1. **Parità**: Bubo legge e scrive solo la memoria nativa (CLAUDE.md, `memory/`), 0 archivi propri. Una Sessione di Bubo e una della CLI sullo stesso repo vedono gli stessi ricordi.
2. **Visibile in 1 clic**: un pannello del Progetto mostra CLAUDE.md caricati (da `InstructionsLoaded`), l'indice `MEMORY.md` con l'occupazione rispetto a 200 righe / 25 KB, i file di argomento con tipo e `modified`, e ogni `memory_recall` durante la Sessione.
3. **Modifica sicura**: modifica e cancellazione di un ricordo con anteprima, 0 file di `~/.claude` scritti senza un'azione dell'utente, un avviso prima di superare il limite dell'indice.

**Secondo cervello.** Il riferimento è Copilot for Obsidian (riassunto di fine chat in Markdown). Criteri candidati:

4. **Qualunque cartella Markdown**, Obsidian chiuso compreso: scrittura diretta su file, frontmatter valido per le proprietà di Obsidian, 0 plugin richiesti.
5. **Riassunto di fine Sessione** entro 10 s dalla chiusura, una nota per Sessione con titolo, Progetto, branch, esito, link alla Sessione (`bubo://`) e `"[[...]]"` alle note correlate. Lunghezza e innesco decisi in [#54](https://github.com/mgiuditta/bubo/issues/54): vedi la Mappa.
6. **Locale per default**: indice ed embedding sul Mac (pezzo condiviso 12/13/14). 0 byte del vault al cloud senza consenso.

## Rischi e casi limite

- **La memoria automatica si carica anche con `settingSources: []`** [4]. Per le Domande (senza Progetto) Bubo deve decidere se spegnerla con `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, altrimenti una Domanda fatta dalla cartella sbagliata eredita i ricordi di un repo.
- **Scritture concorrenti**: più Sessioni in worktree diversi scrivono nella stessa `memory/` [1]. Nessun lock documentato. Bubo non deve aggiungere un secondo scrittore a `MEMORY.md` mentre una Sessione lavora.
- **Codifica del percorso** `<progetto>` con perdita di informazione (vedi ricerca 04): trovare la cartella partendo dal repo, mai il contrario.
- **Auto-dream** non documentato, deciso lato server [3]: la memoria può cambiare senza che Bubo abbia fatto nulla. Serve rileggere da disco, niente cache.
- **Ambiti `team` e `organization`** nel `memory_recall` [3]: ricordi che non arrivano da file locali. Vanno mostrati con la loro sorgente.
- **Il secondo cervello è dell'utente**: scrivere solo nella cartella dedicata, mai rinominare o spostare note (i link si aggiornano solo se rinomina Obsidian [26]). Nomi di file senza `/ : * ? " < > |` (stessa regola dei nomi di Copilot [13]).
- **Dati sensibili nei riassunti**: output dei tool, token, percorsi. Il riassunto deve passare da un filtro e nascere in locale, oppure con consenso se usa un modello cloud.
- **Cartella di Bubo nella ricerca semantica**: i riassunti non devono far rispondere l'indice con se stesso (Copilot esclude la propria cartella [13]).
- **iCloud / sync**: vault in iCloud Drive o Obsidian Sync; `.smart-env/` va escluso dalla sincronizzazione [15]. L'indice di Bubo non va messo nel vault.
- **Local REST API e CLI** chiedono l'app aperta e, per la CLI, una password di amministratore [21][22]: solo come extra, mai come requisito.

## Mappa

Architettura comune in [INDEX.md](INDEX.md). Si appoggia su `Config/ConfigInspector` (feature 04), sulle Sessioni (01, 06), sul router (10) e sull'Indice ([indice-semantico.md](indice-semantico.md)).

### Memoria di Progetto

- **Cosa è**: solo la memoria nativa di Claude Code (CLAUDE.md a livelli, `~/.claude/projects/<p>/memory/`). 0 archivi propri.
- **Chi scrive**: solo l'agente, con `Write` ed `Edit`, come nella CLI. Bubo scrive in `~/.claude` solo su azione dell'utente (modifica o cancellazione con anteprima) e solo quando nessuna Sessione del Progetto è in un turno, per non aggiungere un secondo scrittore su `MEMORY.md`.
- **Moduli**:
  - `Memory/ProjectMemory`: trova la cartella `memory/` partendo dal repo (mai dal nome della cartella codificata), legge `MEMORY.md` e i file di argomento (`type`, `modified`), calcola l'occupazione su 200 righe / 25 KB. Nessuna cache: rilegge da disco a ogni apertura del pannello e su FSEvents.
  - `Memory/MemoryEvents`: dal ponte agente raccoglie `InstructionsLoaded`, `memory_recall` (con `scope`), le scritture di `Write`/`Edit` sotto `memory/` e le chiamate a `cerca`; ne fa righe della Sessione.
  - `HUD/MemoryPanel`: pannello Memoria del Progetto.
  - `HUD/MemoryLine`: riga **Ricordato / Richiamato** nel flusso della Sessione, con Apri e Annulla.
- **Pannello Memoria** (1 clic dal Progetto): CLAUDE.md caricati con livello (da `InstructionsLoaded`), indice `MEMORY.md` con barra di occupazione, file di argomento con tipo e data, ricordi `team`/`organization` con la loro sorgente. Avviso oltre l'80% del tetto dell'indice. Modifica e cancellazione con anteprima del file risultante.
- **Riga Ricordato / Richiamato**: "Ricordato" quando l'agente scrive in `memory/`; "Richiamato" per `memory_recall` e per ogni chiamata a `cerca`. Apri mostra il file o il frammento; Annulla ripristina la versione precedente del file (stessa regola di scrittura: solo fuori da un turno).
- **Auto-dream**: `autoDreamEnabled` non si tocca (parità con la CLI). Se un file cambia senza una scrittura vista nella Sessione, il pannello mostra "cambiato fuori da Bubo" con la data.
- **Domande**: memoria automatica spenta con `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` nell'`env` del ponte. I ricordi si raggiungono con `cerca` sull'Indice. Quando una Domanda diventa Sessione, la variabile cade e la memoria si riaccende.
- **"Ricordati questo"**: in una Sessione lo salva l'agente nella Memoria di Progetto. In una Domanda va nel Secondo cervello ([12-secondo-cervello.md](12-secondo-cervello.md)).

### Riassunto di Sessione

- **Innesco**: passaggio della Sessione a Fusa o Archiviata, oppure "Riassumi ora". Una nota per Sessione: se la Sessione si riapre e torna Fusa o Archiviata, la stessa nota si aggiorna.
- **Chi lo scrive**: Claude, col modello leggero scelto dal router (feature 10); il contenuto è già passato a Claude, quindi nessun nuovo destinatario. Senza rete: Apple Foundation Models.
- **Ingresso del modello**: titolo, Progetto, branch, messaggi dell'utente e dell'agente della Sessione. Niente output grezzo dei tool I messaggi sono quelli di tutti i turni (`Session.conversations`): ogni turno è una Conversazione dell'agente distinta.
- **Filtro dei segreti**: locale, prima della scrittura su disco. Il testo prodotto dal modello passa dal filtro; se trova un segreto lo sostituisce con `[rimosso]`.
- **Forma**:

  ```markdown
  ---
  titolo: "…"
  progetto: "…"
  branch: "…"
  fase: fusa | archiviata
  creata: AAAA-MM-GG
  aggiornata: AAAA-MM-GG
  sessione: "bubo://sessione/<id>"
  correlate: ["[[…]]", "[[…]]"]
  ---

  ## Fatto
  ## Decisioni
  ## Aperto
  ```

  Corpo ≤ 200 parole. `correlate` viene dall'Indice (ricerca sul testo del riassunto). Proprietà valide per Obsidian: date `AAAA-MM-GG`, link tra virgolette.
- **Dove**: `Bubo/Sessioni/AAAA-MM-GG Titolo.md` nel Secondo cervello (nome file senza `/ : * ? " < > |`). La cartella è esclusa dall'Indice, perché le conversazioni sono già indicizzate. Senza Secondo cervello, al primo riassunto si chiede la cartella; se l'utente rifiuta, nessuna nota.
- **Note modificate a mano**: Bubo salva l'hash della nota scritta. Se l'hash su disco è diverso, non sovrascrive: aggiunge in fondo `## Aggiornamento AAAA-MM-GG`.
- **Moduli**: `Memory/SessionSummarizer` (innesco, chiamata al modello, ripiego), `Memory/SecretFilter` (condiviso con l'Indice e con gli Allegati se serve), `SecondBrain/NoteWriter` ([12-secondo-cervello.md](12-secondo-cervello.md)).

### Flusso

1. Apertura Progetto → `ProjectMemory` legge `memory/` → pannello pronto.
2. Turno dell'agente → `InstructionsLoaded`, `memory_recall`, `Write` in `memory/`, `cerca` → righe Ricordato / Richiamato entro 1 s.
3. Sessione → Fusa o Archiviata → `SessionSummarizer` → modello → `SecretFilter` → `NoteWriter` → nota in `Bubo/Sessioni/` entro 10 s.

### Casi limite

- Più Sessioni in worktree dello stesso repo scrivono nella stessa `memory/`: Bubo non scrive mai durante un turno; Annulla e modifica si abilitano solo a turni fermi.
- `MEMORY.md` oltre il tetto: Claude Code risponde già con un errore all'agente; Bubo avvisa prima, all'80%.
- Auto-dream o CLI che cambiano la memoria a Bubo aperto: FSEvents + "cambiato fuori da Bubo".
- Riassunto senza rete: Apple FM; senza Apple FM disponibile, il riassunto resta in coda e si scrive al ritorno della rete.
- Sessione riaperta più volte: una sola nota, aggiornata; se modificata a mano, sezioni "Aggiornamento" in coda.
- Secondo cervello non raggiungibile (disco esterno, iCloud non scaricato): il riassunto resta in coda, avviso nella Sessione.
- Domanda nata in una cartella che è un repo: nessun ricordo del repo (variabile d'ambiente), verificato con `memoryFiles`.

### Test

- Stesso repo, una Sessione di Bubo e una della CLI: stessi file in `memoryFiles` di `getContextUsage()`.
- Domanda lanciata dentro un repo con memoria: 0 file di memoria in `memoryFiles`.
- Monitor di scrittura su `~/.claude` durante una Sessione senza azioni dell'utente: 0 scritture di Bubo.
- Set fisso di 20 trascrizioni con segreti piantati (API key, token, password, chiavi private): 0 segreti nelle note.
- Nota modificata a mano, poi Sessione riaperta e rifusa: contenuto originale intatto, sezione "Aggiornamento" aggiunta.
- Nota aperta in Obsidian: 0 errori sulle proprietà.

## Specifica "migliore di"

Miglior concorrente per la memoria: **Claude Code stesso** (file in chiaro, condivisi tra worktree, tetto con avviso), che però non mostra cosa salva né quando. Per il riassunto: **Copilot for Obsidian**, unico che scrive un riassunto a fine chat, ma solo dentro Obsidian e senza filtro dei segreti; nessun concorrente agentico ne scrive uno.
Bubo li supera così:

1. **Parità**: 0 archivi propri; una Sessione di Bubo e una della CLI sullo stesso repo vedono gli stessi ricordi.
2. **Visibile**: pannello Memoria a **1 clic**; riga Ricordato / Richiamato **entro 1 s** dall'evento.
3. **Nessuna scrittura non chiesta**: **0 file** di `~/.claude` scritti senza azione dell'utente; avviso oltre l'**80%** del tetto dell'indice.
4. **Riassunto**: su disco **entro 10 s** da Fusa/Archiviata, **≤ 200 parole**, frontmatter letto da Obsidian **senza errori**, **0 plugin**.
5. **Segreti**: **0 segreti** trapelati sul set fisso di 20 trascrizioni.
6. **Rispetto delle note**: **0 note** dell'utente toccate fuori da `Bubo/`; **0 sovrascritture** di note modificate a mano.
7. **Isolamento delle Domande**: **0 ricordi** di un Progetto caricati in una Domanda (verifica con `memoryFiles`).

## Fonti

1. Claude Code, "How Claude remembers your project" — https://code.claude.com/docs/en/memory (letto 2026-09-29)
2. Claude Code, "Subagents → Enable persistent memory" — https://code.claude.com/docs/en/sub-agents#enable-persistent-memory
3. `@anthropic-ai/claude-agent-sdk` 0.3.285, `sdk.d.ts` (`autoMemoryEnabled`, `autoMemoryDirectory`, `autoDreamEnabled`, `SDKMemoryRecallMessage`, `InstructionsLoadedHookInput`, `PostCompactHookInput`, `SessionEndHookInput`, `ExitReason`, `AgentDefinition.memory`) — https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk
4. Agent SDK, "Use Claude Code features in the SDK" (tabella "What settingSources does not control") — https://code.claude.com/docs/en/agent-sdk/claude-code-features
5. Cline, "Memory Bank" — https://docs.cline.bot/prompting/cline-memory-bank
6. Cursor forum, "Custom modes and memories gone in 2.1" — https://forum.cursor.com/t/custom-modes-and-memories-gone-in-2-1/143744
7. Cursor forum, "Are my memories gone?" (Dean Rie, staff, 25/11/2025) — https://forum.cursor.com/t/are-my-memories-gone/144057 ; changelog 2.1 (21/11/2025) — https://cursor.com/changelog/2-1
8. Devin/Windsurf, "Cascade Memories" — https://docs.devin.ai/desktop/cascade/memories (ex docs.windsurf.com)
9. Conductor docs, indice — https://www.conductor.build/llms.txt
10. Conductor changelog 0.28.0 (22/12/2025) — https://www.conductor.build/changelog/0.28.0-workspaces-page-claude-s-context-interactive-planning-keyboard-nav-and-more
11. Nimbalyst docs — https://docs.nimbalyst.com/llms.txt ; https://docs.nimbalyst.com/task-management/linking-sessions-and-tracked-items.md
12. logancyang/obsidian-copilot, `src/memory/memory-design.md` — https://github.com/logancyang/obsidian-copilot/blob/master/src/memory/memory-design.md
13. logancyang/obsidian-copilot, `docs/settings.md` e `src/settings/copilotFolder.ts` — https://github.com/logancyang/obsidian-copilot/blob/master/docs/settings.md
14. basicmachines-co/basic-memory — https://github.com/basicmachines-co/basic-memory
15. brianpetro/obsidian-smart-connections README — https://github.com/brianpetro/obsidian-smart-connections
16. Fonti secondarie su auto-dream (non ufficiali): https://claudefa.st/blog/guide/mechanics/auto-dream ; https://www.mindstudio.ai/blog/what-is-claude-code-autodream-memory-consolidation
17. brianpetro/obsidian-smart-connections, `src/main.js` (aggiunta di `.smart-env` a `.gitignore`) — https://github.com/brianpetro/obsidian-smart-connections/blob/main/src/main.js
18. khoj-ai/khoj README — https://github.com/khoj-ai/khoj
19. Khoj, "Setup" — https://docs.khoj.dev/get-started/setup
20. Obsidian Help, "Obsidian URI" — https://obsidian.md/help/Extending+Obsidian/Obsidian+URI
21. Obsidian Help, "Obsidian CLI" — https://obsidian.md/help/cli
22. coddingtonbear/obsidian-local-rest-api — https://github.com/coddingtonbear/obsidian-local-rest-api
23. MarkusPfundstein/mcp-obsidian — https://github.com/MarkusPfundstein/mcp-obsidian
24. kepano/obsidian-skills — https://github.com/kepano/obsidian-skills
25. Obsidian Help, "Properties" — https://obsidian.md/help/properties
26. Obsidian Help, "Internal links" — https://obsidian.md/help/links

Stelle e date dei repo lette con `gh api` il 2026-09-29.
