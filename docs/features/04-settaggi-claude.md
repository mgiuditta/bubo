# 04 — Riuso di `~/.claude`: skill, hook, CLAUDE.md, MCP, plugin, cronologia

Ticket: [#15](https://github.com/mgiuditta/bubo/issues/15). Mappa: [#11](https://github.com/mgiuditta/bubo/issues/11).
Ricerca del 2026-09-29 su Agent SDK TS **0.3.284** e CLI `claude` **2.1.284**.

In sintesi: l'Agent SDK carica già quasi tutto da solo. Se `settingSources` non si passa, il figlio `claude` legge le stesse cose della CLI. Bubo non deve copiare né riscrivere i file dell'utente. Deve **mostrare** cosa è stato caricato e **dire** cosa manca.

## Ricerca

### Come fanno i concorrenti

| App | Come riusa `~/.claude` | Cosa piace | Cosa lamentano / cosa manca |
|---|---|---|---|
| **App desktop ufficiale (scheda Code)** | Stesso motore della CLI. Legge gli stessi file: CLAUDE.md, MCP da `~/.claude.json` e `.mcp.json`, hook, skill, `settings.json`. Aggiunge gli MCP di `claude_desktop_config.json`. `/resume` nell'app elenca le sessioni nate nella CLI; `/desktop` nella CLI sposta la sessione nell'app. [1] | Nessuna configurazione. Passaggio CLI → app in un comando. | Ogni superficie ha **la sua lista di sessioni** [1][2]. Il pannello Customize → Skills non mostrava le skill di `~/.claude/skills/` né quelle dei plugin (issue chiusa) [3]. In alcuni casi precedenza MCP diversa dalla CLI [1]. |
| **Conductor** | Usa il binario Claude Code incluso o quello di sistema [4]. MCP da `.mcp.json` o `claude mcp add`; dopo una modifica serve una nuova sessione [5]. Comandi da `.claude/commands/` nel compositore [6]. | Funziona con la config esistente del repo. | La documentazione non dice nulla su skill utente, hook, plugin, CLAUDE.md o import della cronologia CLI [4][6]. Nessuna vista di cosa è caricato. |
| **Nimbalyst (ex Crystal)** | Provider "Claude Agent" su Agent SDK. Costruisce **da sé** la lista `mcpServers`: server propri, `~/.claude.json`, `.mcp.json` del workspace [7]. | Sessioni salvate e ricercabili, rami, archivio [8]. | Issue aperta: le sessioni **non vedono MCP, hook e skill dei plugin installati** in Claude Code, "senza nessuna indicazione nella UI" [7]. Richiesta di leggere l'MCP utente (#43) [9]. Il picker `/` elenca README e CHANGELOG dei plugin come comandi (#869) [10]. Prompt da 154k token per catalogo skill + 150 tool MCP (#914) [11]. |
| **opcode (ex Claudia)** | App Tauri. Sfoglia `~/.claude/projects/`, riprende sessioni, editor di CLAUDE.md, registro MCP con import da Claude Desktop [12]. 22,4k stelle. | Vista d'insieme della cronologia e della config. | Scriveva gli **hook nel formato sbagliato** dentro `~/.claude/settings.json` (#287) [13]. Ricostruisce il percorso del progetto dal nome cartella: con `_` nel nome utente sbaglia e il prompt fallisce (#465) [14]. "Failed to load MCP servers" (#224, 12 commenti) [15]. Chiudere l'editor CLAUDE.md perde le modifiche (#478) [16]. |
| **Sculptor (Imbue)** | Copia nei container: comandi, subagent, definizioni e auth MCP, `settings.json` (user/project/local) [17]. | Il comportamento locale si ripete nel container. | Copia, quindi due verità da tenere allineate. Skill, hook e plugin non sono nell'elenco citato [17]. |
| **Superset** | Lancia le CLI degli agenti (Claude Code, Codex, …) nei terminali, ognuna in un worktree [18]. | Riuso totale, perché gira proprio la CLI. | Nessuna vista dedicata a skill, MCP o cronologia: si vede solo il terminale [18]. |
| **CodeAgentSwarm, ClaudeGUI, Agentic Stack Desktop** | Nessuna fonte primaria trovata su questo tema. | — | — |

### Temi ricorrenti nelle lamentele

1. **Degrado silenzioso.** Un'app ricostruisce a mano MCP o skill e ne perde una parte. L'utente non lo sa (Nimbalyst #1489).
2. **Scrittura nei file dell'utente.** Un formato sbagliato rompe anche la CLI (opcode #287).
3. **Parsing fragile dei nomi di cartella e del JSONL** (opcode #465). Anthropic avverte che il formato è interno e cambia tra versioni [19].
4. **Troppo contesto.** Centinaia di skill e tool MCP gonfiano il prompt (Nimbalyst #914).
5. **Liste di sessioni separate** tra CLI, app e IDE [1][2].
6. **Concorrenza.** Più istanze che scrivono `~/.claude.json` lo corrompevano (issue #18998 e #28989, chiuse nel 2026) [20][21].

## Cosa carica l'Agent SDK

Regola base: se `settingSources` non si passa, equivale a `['user','project','local']`, come la CLI [22][23]. `[]` = isolamento. Il valore predefinito era stato cambiato in v0.1.0 ed è poi tornato indietro [23].

| Settaggio | Caricato? | Come / nota |
|---|---|---|
| `~/.claude/settings.json`, `.claude/settings.json`, `.claude/settings.local.json` | Sì | Con `user`, `project` e `local`. Il `settings.json` di progetto si legge solo da `<cwd>/.claude/`, senza risalire alle cartelle padre [22]. |
| CLAUDE.md e rules | Sì | Utente: `~/.claude/CLAUDE.md` e `~/.claude/rules/*.md`. Progetto: `cwd` e padri; sottocartelle a richiesta. Locale: `CLAUDE.local.md` [22]. Serve `systemPrompt: {type:'preset', preset:'claude_code'}` per avere il prompt di Claude Code [23]. |
| Skill | Sì | `~/.claude/skills/` e `.claude/skills/` fino alla radice del repo. L'opzione `skills` (`'all'` o un elenco) è **solo un filtro di contesto, non una sandbox** [22][24]. |
| Comandi e subagent | Sì | `~/.claude/commands|agents/` e quelli di progetto [22]. |
| Hook da file | Sì | Eseguiti come nella CLI (command, http, mcp_tool, prompt, agent). Convivono con gli hook a callback di Bubo [22]. |
| MCP utente/locale (`~/.claude.json`) | Sì | Letto sempre, anche con `settingSources: []` [22]. Nella prova: sorgente `user` [misura A]. |
| MCP di progetto (`.mcp.json`) | Sì, con `project` | Server di progetto soggetti ad approvazione [25][26]. |
| Plugin da marketplace (`enabledPlugins`) | Sì, con `user` | La doc SDK chiede di passare i percorsi a mano [27], **ma** il figlio è la CLI, che carica i plugin da `installed_plugins.json` e dalla cache all'avvio [26]. Prova: 24 plugin e 164 skill di plugin senza passare `plugins` [misura A]. |
| Plugin extra | Sì, con `plugins: [{type:'local', path}]` | Id `nome@inline`. Niente `~` nei percorsi. Un percorso che non esiste viene saltato in silenzio: controllare `plugins` e `plugin_errors` nel messaggio init [27]. |
| Plugin sincronizzati da claude.ai | Sì | Anche con `settingSources: []` ne restano 2 nella prova [misura A][26]. |
| Connettori MCP di claude.ai | Sì | Anche con `mcpServers: {}`. Si tolgono con `strictMcpConfig: true` o `ENABLE_CLAUDEAI_MCP_SERVERS=false` [22]. |
| Auto memory `~/.claude/projects/<p>/memory/` | Sì | Sempre. Si spegne con `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` [22]. |
| Policy gestite (MDM, managed settings) | Sì | Sempre; non disattivabili dall'SDK [22]. |
| OAuth MCP | No | L'SDK non apre il browser. Un server senza token resta `needs-auth` [25]. |
| Flag di una sessione CLI (`--mcp-config`, `--settings`, `--plugin-dir`, `--add-dir`) | No al resume | Vanno ripassati [2]. |

API utili per **mostrare** cosa è caricato, senza leggere i file a mano (da `sdk.d.ts` 0.3.284):

- messaggio `system/init`: `skills`, `plugins` (nome, percorso, versione), `plugin_errors`, `mcp_servers` (nome, stato, `source`), `slash_commands`, `agents`, `tools`;
- `supportedCommands()`, `supportedAgents()`, `mcpServerStatus()`, `reconnectMcpServer()`, `reloadSkills()`, `reloadPlugins()`, `getContextUsage()` (token per categoria, file di memoria compresi);
- hook `InstructionsLoaded`: `file_path` e `memory_type` (User, Project, Local, Managed) di ogni CLAUDE.md caricato;
- `resolveSettings({cwd})` (alpha): impostazioni unite, con la **provenienza** di ogni chiave;
- `projectConfigRoot`: per i worktree (feature 01), prende la config di progetto dal checkout fidato.

**Misura A** (questo Mac, cwd = repo Bubo, `query()` interrotta al messaggio init):

| | init dopo | skill (di plugin) | plugin | MCP | slash command | tool |
|---|---|---|---|---|---|---|
| predefinito | 994 ms | 355 (164) | 24 | 12 (4 plugin, 2 user, 6 claude.ai) | 392 | 77 |
| `settingSources: []` | 650 ms | 18 (0) | 2 | 6 (claude.ai) | 54 | 25 |

## Cronologia sessioni

**Formato.** `~/.claude/projects/<cwd-codificato>/<session-id>.jsonl`. Il nome della cartella è il percorso con ogni carattere non alfanumerico sostituito da `-`. Oltre 200 caratteri: troncato + hash [19]. La codifica **non è reversibile** (`_` e `/` diventano entrambi `-`): è il bug opcode #465 [14]. Accanto al file: cartella `<session-id>/` con `subagents/agent-<id>.jsonl` [sdk.d.ts]. Ogni riga è un oggetto JSON. Anthropic: "il formato è interno e cambia tra versioni", quindi gli script che lo leggono direttamente si possono rompere [19].

Struttura osservata (solo nomi dei campi, CLI 2.1.284): tipi `user`, `assistant`, `attachment`, `system` (sottotipi `turn_duration`, `stop_hook_summary`, `local_command`), `mode`, `ai-title`, `last-prompt`, `file-history-snapshot`, più altri. Campi comuni: `uuid`, `parentUuid`, `sessionId`, `timestamp`, `cwd`, `gitBranch`, `version`, `entrypoint`, `isSidechain`. `~/.claude/history.jsonl` (permessi 600) tiene i prompt digitati: `display`, `pastedContents`, `project`, `sessionId`, `timestamp`.

**Leggere senza parsing proprio.** L'SDK espone `listSessions({dir, limit, offset, includeWorktrees, includeProgrammatic})`, `getSessionInfo`, `getSessionMessages`, `listSubagents`, `getSubagentMessages`, `renameSession`, `tagSession`, `deleteSession`, `forkSession` [28]. `SDKSessionInfo` dà `summary`, `customTitle`, `firstPrompt`, `gitBranch`, `cwd`, `tag`, `createdAt`, `lastModified`, `fileSize`.

**Misura B** (questo Mac): 247 sessioni, 728 MB di JSONL. `listSessions()` su tutti i progetti: 132 ms; prima pagina da 50: 30 ms; solo interattive (`includeProgrammatic:false`): 218 sessioni in 109 ms. 183 su 247 hanno un titolo; 246 hanno il branch.

**Resume.**
- `resume: <id>` riprende una sessione nata nella CLI. Dalla CLI 2.1.223 la ricerca dell'id attraversa tutti i progetti; con copie duplicate risponde "non trovata" [28][2].
- `continue: true` prende l'ultima sessione della cartella [28].
- `forkSession: true` crea un nuovo id e lascia intatto l'originale [28].
- `resumeSessionAt` riprende da un messaggio preciso [sdk.d.ts].
- Il resume ripristina modello, agente e modalità permessi (con eccezioni) [2].
- **Al contrario:** le sessioni create dall'SDK **non compaiono** nel picker `/resume` né in `claude --continue`. Si riaprono solo con `claude --resume <id>` [2].
- **Stessa sessione in due processi senza fork:** "i messaggi di entrambi si mescolano in un solo transcript" [2].
- **Conservazione:** 30 giorni di default (`cleanupPeriodDays`) [19]. `sessionStore` (alpha) copia i transcript in uno store di Bubo; `importSessionToStore` importa un JSONL esistente [sdk.d.ts][28].

## Il meglio da battere

Il riferimento è l'**app desktop ufficiale**: stessa config della CLI, zero setup, `/resume` delle sessioni CLI. Però non mostra cosa è caricato e ha liste di sessioni separate. Criteri candidati:

1. **Parità totale, verificata:** con la stessa cartella, Bubo carica lo stesso numero di skill, plugin e server MCP della CLI (conteggio da `init`), 0 differenze. Zero file di `~/.claude` scritti senza un'azione esplicita dell'utente.
2. **Tutto visibile in 1 clic:** un pannello mostra CLAUDE.md caricati, skill, plugin (con `plugin_errors`), MCP con stato e sorgente, token per categoria. Ogni elemento mancante o in errore ha un avviso (0 degradi silenziosi).
3. **Una sola cronologia:** sessioni CLI e Bubo in un'unica lista. Primi 50 elementi in < 100 ms (misura attuale: 30 ms). Ripresa di una sessione CLI in ≤ 2 clic.
4. **Nessuna collisione:** se la sessione è aperta nella CLI, Bubo la apre con fork, mai in scrittura condivisa.
5. **Avvio:** messaggio `init` entro 1 s con la config completa (misura attuale: 994 ms).

## Rischi e casi limite

- **Scrivere nei file dell'utente.** Un errore rompe anche la CLI (opcode #287). Regola candidata: sola lettura; ogni modifica passa dalla CLI (`claude mcp add`, `claude plugin …`) oppure da un'anteprima con backup.
- **CLI aperta in parallelo.** Due processi sulla stessa sessione mescolano il transcript [2]. `~/.claude.json` si è corrotto con più istanze insieme (bug chiusi, ma il rischio resta) [20][21]. Serve fork, oppure un blocco basato sull'mtime del JSONL o sui processi attivi (`~/.claude/sessions/`).
- **Formato JSONL instabile** [19]. Usare solo le API dell'SDK (`listSessions`, `getSessionMessages`), mai un parser proprio. Non ricostruire mai il percorso dal nome della cartella: usare `SDKSessionInfo.cwd` [14].
- **Versione del binario.** Se Bubo include il suo `claude` (#3) e l'utente ne ha uno più nuovo, i plugin o il formato possono divergere (Nimbalyst: CLI inclusa 2.1.257, di sistema 2.1.267) [7].
- **Dati sensibili.** I transcript contengono output dei tool (file letti, variabili d'ambiente, token incollati). `history.jsonl` contiene i contenuti incollati. Le cartelle hanno permessi 700/600. Bubo non deve indicizzarli verso servizi esterni né copiarli fuori da `~/.claude` senza consenso. Attenzione alla feature 14 (ricerca semantica): gli embedding restano in locale.
- **Contesto gonfio.** Con tutta la config ci sono 355 skill e 77 tool (misura A). Il router di Bubo (feature 10) può filtrare con `skills: [...]` per le richieste semplici. È solo un filtro, non una sandbox [24].
- **Effetti non voluti.** Gli hook utente girano anche nelle sessioni di Bubo, compresi hook lenti o con notifiche proprie. Anche i connettori claude.ai si caricano sempre. Bubo deve mostrarlo e offrire un interruttore (`strictMcpConfig`, `settingSources` ridotto).
- **OAuth MCP.** L'SDK non completa l'OAuth: un server `needs-auth` va sistemato nella CLI (`/mcp`) o da un flusso proprio di Bubo [25].
- **Cancellazione a 30 giorni** della cronologia della CLI [19]: la cronologia di Bubo non deve dipendere solo da `~/.claude/projects`.
- **Sessioni SDK invisibili nella CLI** [2]: se l'utente torna al terminale non vede le sessioni di Bubo. Bubo deve mostrare il comando `claude --resume <id>`.
- **Codifica del percorso lossy e cartelle troncate** oltre 200 caratteri (worktree annidati) [19].

## Mappa

Architettura comune in [INDEX.md](INDEX.md#architettura-comune-feature-16).

- **Moduli**: nessuna copia della configurazione: l'SDK la carica da solo. `Config/ConfigInspector` (messaggio `init`, `mcpServerStatus()`, hook `InstructionsLoaded`, `plugin_errors`), `HUD/ConfigPanel` (tutto visibile in 1 clic), `History/CLIHistory` (`listSessions` / `getSessionMessages`, ripresa sempre come fork in una nuova Sessione).
- **Flusso**: apertura Progetto → `init` → pannello con conteggi ed errori; Cronologia CLI → "Riprendi" → nuova Sessione (fork).
- **Casi limite**: MCP che chiede OAuth (l'SDK non lo completa: rimandare alla CLI con istruzioni), contesto gonfio da troppe skill (mostrare i token per categoria), transcript con dati sensibili (mai inviati fuori), cronologia cancellata dalla CLI dopo 30 giorni.
- **Test**: confronto dei conteggi `init` tra Bubo e CLI sulla stessa cartella.

## Specifica "migliore di"

Miglior concorrente: **app desktop ufficiale** (stessa configurazione della CLI, `/resume`), ma non mostra cosa carica; Nimbalyst e opcode perdono o corrompono configurazione.
Bubo lo supera così:
- **Parità verificata** con la CLI: stesso numero di skill, plugin e MCP (conteggio da `init`), **0 file** di `~/.claude` scritti senza un clic esplicito.
- **Tutto visibile in 1 clic**: CLAUDE.md, skill, plugin con errori, MCP con stato e sorgente; 0 degradi silenziosi.
- Cronologia CLI in lista separata ma **ricerca unica** con le Sessioni; primi 50 elementi **< 100 ms**; ripresa come fork in **≤ 2 clic**.
- `init` con configurazione completa **entro 1 s**.

## Fonti

1. Claude Code, "Desktop application" — https://code.claude.com/docs/en/desktop
2. Claude Code, "Manage sessions" — https://code.claude.com/docs/en/sessions
3. anthropics/claude-code #31597, "Skills from ~/.claude/skills/ and plugins not shown in Customize -> Skills panel" — https://github.com/anthropics/claude-code/issues/31597
4. Conductor, "Claude Code harness reference" — https://www.conductor.build/docs/reference/harnesses/claude-code
5. Conductor, "Set up MCP servers" — https://www.conductor.build/docs/guides/configure-mcp-servers
6. Conductor, "Slash commands" — https://www.conductor.build/docs/reference/slash-commands
7. nimbalyst/nimbalyst #1489, "Claude Agent sessions never see MCP servers (or hooks) shipped inside installed Claude Code plugins" — https://github.com/nimbalyst/nimbalyst/issues/1489
8. SitePoint, "Nimbalyst: the visual workspace for building with Claude Code and Codex" — https://www.sitepoint.com/nimbalyst-the-visual-workspace-for-building-with-claude-code-and-codex/
9. nimbalyst/nimbalyst #43 — https://github.com/nimbalyst/nimbalyst/issues/43
10. nimbalyst/nimbalyst #869 — https://github.com/nimbalyst/nimbalyst/issues/869
11. nimbalyst/nimbalyst #914 — https://github.com/nimbalyst/nimbalyst/issues/914
12. winfunc/opcode README — https://github.com/winfunc/opcode
13. winfunc/opcode #287, "Claudia 0.1.0 writes hooks in the wrong format" — https://github.com/winfunc/opcode/issues/287
14. winfunc/opcode #465, percorso ricostruito male con `_` — https://github.com/winfunc/opcode/issues/465
15. winfunc/opcode #224 — https://github.com/winfunc/opcode/issues/224
16. winfunc/opcode #478 — https://github.com/winfunc/opcode/issues/478
17. Imbue, "Synchronizing Claude Configuration" (Sculptor) — https://docs.imbue.com/features/synchronizing-claude-configuration (al momento della ricerca risponde 404; contenuto dall'estratto indicizzato)
18. Superset docs — https://docs.superset.sh/ ; Show HN — https://news.ycombinator.com/item?id=46368739
19. Claude Code, "Manage sessions → Where transcripts are stored" — https://code.claude.com/docs/en/sessions#where-transcripts-are-stored
20. anthropics/claude-code #18998, corruzione di `.claude.json` con 30+ sessioni — https://github.com/anthropics/claude-code/issues/18998
21. anthropics/claude-code #28989, race condition su `.claude.json` — https://github.com/anthropics/claude-code/issues/28989
22. Agent SDK, "Use Claude Code features in the SDK" — https://code.claude.com/docs/en/agent-sdk/claude-code-features
23. Agent SDK, "Migrate to Claude Agent SDK" (predefinito di settingSources, system prompt) — https://code.claude.com/docs/en/agent-sdk/migration-guide
24. `@anthropic-ai/claude-agent-sdk` 0.3.284, `sdk.d.ts` (opzioni `skills`, `settingSources`, `plugins`, `persistSession`, `sessionStore`, `resumeSessionAt`, `projectConfigRoot`, `resolveSettings`, `SDKSystemMessage`) — https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk
25. Agent SDK, "Connect to external tools with MCP" — https://code.claude.com/docs/en/agent-sdk/mcp
26. Claude Code, "Plugin loading reference" — https://code.claude.com/docs/en/plugins/loading
27. Agent SDK, "Plugins in the SDK" — https://code.claude.com/docs/en/agent-sdk/plugins
28. Agent SDK, "Work with sessions" — https://code.claude.com/docs/en/agent-sdk/sessions

Misure A e B: script in locale sull'SDK 0.3.284 con la CLI 2.1.284 (`pathToClaudeCodeExecutable`), eseguiti su questo Mac il 2026-09-29. Della struttura di `~/.claude` sono stati letti solo nomi di file e di campi, nessun contenuto.
