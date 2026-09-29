# 01 — Sessioni Claude Code in parallelo in git worktree

Ticket: [#12](https://github.com/mgiuditta/bubo/issues/12). Mappa: [#11](https://github.com/mgiuditta/bubo/issues/11). Ricerca del 2026-09-29.

## Ricerca

Tutti i concorrenti seri usano lo stesso schema: una sessione = un worktree = un branch. Cambiano i dettagli: dove sta il worktree, come si prepara (dipendenze, `.env`), come si gestiscono le porte e come si pulisce. Solo Sculptor usa container al posto dei worktree.

Numeri di tempo "da clic a sessione pronta" non li pubblica nessuno. È un buco: nessuno si misura su questo.

### App desktop ufficiale di Claude Code (scheda Code)

**Come lo fa**
- Nuova sessione con **Cmd+N**. Per i repo git si sceglie l'opzione **worktree** accanto al nome del branch. [desktop]
- Posizione di default: `<repo>/.claude/worktrees/`. Si può cambiare in Settings → Claude Code ("Worktree location"). C'è un prefisso configurabile per i nomi dei branch. [desktop]
- Dalla CLI (`claude -w <nome>`) il branch si chiama `worktree-<nome>`. Senza nome ne genera uno tipo `bright-running-fox`. [worktrees]
- Base: di default il branch di default del remoto (`worktree.baseRef: "fresh"`), con fetch se l'ultimo ha più di 24 ore, limitato a 5 secondi. In alternativa `"head"`. Non accetta un nome di branch. [worktrees]
- `--worktree "#1234"` o URL di PR/MR: crea il worktree dalla PR. [worktrees]
- File ignorati: `.worktreeinclude` con sintassi `.gitignore`. Copia solo file che sono anche gitignored. [worktrees]
- Setup non-git o personalizzato: hook `WorktreeCreate` / `WorktreeRemove`. [worktrees]
- Isolamento attivo: blocca edit e comandi Bash che puntano al checkout principale (anche `git -C`, `GIT_DIR`). [worktrees]
- Lock: tiene un `git worktree lock` finché l'agente gira. Uno sweep periodico rilascia i lock orfani. [worktrees]
- Condivisi col checkout principale: `.git`, plugin di progetto, approvazioni dei permessi, skill/agent non tracciati. [worktrees]
- Pulizia: icona "archivia" nella sidebar. Opzione **Auto-archive dopo merge o chiusura della PR**. [desktop]
- Porte: il server di anteprima ha `autoPort`. Se la porta è occupata ne sceglie una libera e la passa in `PORT`. [desktop]

**Cosa piace**
- Tutto integrato: sidebar, diff, terminale, anteprima, stato PR/CI.
- `.worktreeinclude` è diventato uno standard di fatto: lo legge anche Conductor. [conductor-files]
- Le sessioni si parlano tra loro ("dì alla sessione pagamenti che lo schema è cambiato"). [desktop]

**Cosa lamentano**
- Worktree imposto: richieste per disattivarlo, 31 e 47 commenti ([#21236], [#12513]).
- Disco: ogni worktree è un checkout completo; in desktop non c'è un "momento di uscita". Esempio riportato: 7 worktree inattivi = 4,2 GB. Esiste Settings → Desktop → Storage → "Free up space" (soglia di default 7 giorni). [wmedia]
- Submodule non inizializzati nei worktree creati dalla desktop app (la CLI invece lo fa) ([#83411]).
- `core.hooksPath` scritto come percorso assoluto nel `config.worktree`: il worktree esegue gli hook del checkout principale ([#88747], 15 commenti, aperta).
- Hook di progetto che non arrivano nel worktree quando `.claude/` è gitignored ([#83953]).
- Non si vede in UI in quale worktree/cwd si è ([#60097]).
- Diff bloccato sul branch base scelto alla creazione ([#79530]).
- Git LFS installato con `--local`: nel worktree ci sono solo i puntatori. Serve `git lfs pull`. [worktrees]

**Cosa manca**
- Nessuno script di setup nativo (install dipendenze): solo hook o chiedere a Claude.
- Nessuna porta assegnata per sessione ai dev server generici (solo l'anteprima ha `autoPort`).
- Nessuna copia veloce di `node_modules`.

**Numeri**
- 1 scorciatoia (Cmd+N) + 1 opzione worktree per creare la sessione.
- Fetch della base limitato a 5 s. [worktrees]
- Cross-session: vede le 20 sessioni più recenti. [desktop]

### Conductor (Melty Labs, YC)

**Come lo fa**
- App Mac, solo Apple Silicon. Shell Tauri, runtime Bun, SQLite locale. [performance-dev]
- Ogni workspace è un worktree in `~/conductor/workspaces/<repo>/<workspace>`. Le versioni vecchie usavano `.conductor/` dentro il repo e confondevano i build tool. [conductor-worktrees] [conductor-nesting]
- Script in `.conductor/settings.toml`: `setup`, `run`, `archive`. [conductor-scripts]
- Variabili: `CONDUCTOR_PORT` (prima di **10 porte** riservate al workspace), `CONDUCTOR_ROOT_PATH`, `CONDUCTOR_WORKSPACE_PATH`, `CONDUCTOR_WORKSPACE_NAME`. [conductor-scripts]
- `run_mode`: `concurrent` o `nonconcurrent` (avviarne uno ferma gli altri, per porte o DB fissi). [conductor-scripts]
- Stop: SIGTERM al process group, SIGKILL dopo 5 s. [conductor-scripts]
- File da copiare: `.worktreeinclude` > `file_include_globs` > default `.env*`. Solo file gitignored. `node_modules` va gestito dallo script di setup. [conductor-files]
- Archivio "istantaneo" e ripristino dalla scheda History (0.46.0). Rilancio dello script di setup (0.32.1), log del setup visibili (0.31.0), cambio del branch target (0.28.7), fork di workspace (0.25.6). [conductor-changelog]
- Workspace inattivi spenti per recuperare memoria; ripresa su richiesta. [performance-dev]

**Cosa piace**
- È il riferimento per il ciclo di vita completo: setup, run, archive, porte, file da copiare.
- Pensato per 5–10 agenti in parallelo. [conductor-yc]

**Cosa lamentano**
- La prima versione era "frustrantemente lenta" su chat, worktree e visualizzazione codice: ha richiesto una riscrittura. [performance-dev]
- CPU alta in versioni vecchie (0.7.0 "We no longer burn your CPU (hopefully)", leak dei terminali). [conductor-changelog]
- Git vieta lo stesso branch in due worktree: serve un branch nuovo o cambiare workspace. [conductor-worktrees]

**Cosa manca**
- Nessuna copia copy-on-write documentata per le dipendenze.
- Solo Apple Silicon. Niente numeri pubblici di tempo di creazione o RAM.

**Numeri**
- 10 porte per workspace. Stop in 5 s. Riscrittura: creazione tab, cambio workspace e rendering file "50% più veloci"; bundle −150 MB con Bun. [performance-dev]

### Superset

**Come lo fa**
- Editor/terminale per agenti CLI (Claude Code, Codex, Gemini, ecc.). Ogni task ha worktree e branch. [superset-guide]
- Nuovo workspace con **⌘N** o **⌘⇧N**. [superset-scripts]
- `.superset/config.json` con `setup`, `teardown`, `run`. Override utente in `~/.superset/projects/<repo>/config.json`, estensioni locali in `.superset/config.local.json` (gitignored, con `before`/`after`). [superset-scripts]
- Variabili: `SUPERSET_ROOT_PATH`, `SUPERSET_WORKSPACE_NAME`, `SUPERSET_WORKSPACE_PATH`. [superset-scripts]
- Porte: **non** assegna intervalli. Scopre le porte in ascolto, le raggruppa per workspace, permette di killare il processo. Etichette in `.superset/ports.json`. [superset-ports]

**Cosa piace**
- Agnostico sull'agente. Pannello porte comodo.
- La loro stessa guida è onesta: "un worktree separa file e indice. Non alloca DB, porta, nome container o rate limit". [superset-guide]

**Cosa lamentano**
- Input lag grave: polling git per ogni workspace aperto. Con 3 workspace e un agente Endpoint Security: ~450k eventi filesystem da `git` in 10 s da fermo ([superset#4198]).
- Workspace spariti dopo aggiornamenti ([superset#5537], [superset#4610], [superset#4763]).
- UI bloccata cancellando workspace fissati ([superset#7125]).
- Vogliono scegliere il nome del workspace e del branch ([superset#6398]) e creare da branch esistente ([superset#691]).

**Cosa manca**
- Porte isolate per costruzione. Posizione del worktree configurabile in v2 ([superset#4696]).

**Numeri**
- 1 scorciatoia per creare. Nessun tempo pubblicato. ~14.7k stelle GitHub.

### Nimbalyst (ex Crystal, Stravu)

**Come lo fa**
- Crystal: Electron, una sessione per prompt, ognuna in un worktree; commit, diff, squash e rebase integrati. [crystal]
- Nimbalyst: monorepo TypeScript/Electron più app iOS SwiftUI. Worktree **opzionali**, sessioni su kanban, file toccati per sessione. [nimbalyst]

**Cosa piace**
- Kanban delle sessioni e tracciamento file→sessione. Più agenti (Claude Code, Codex).

**Cosa lamentano**
- Crystal: `.env` da copiare a mano in ogni worktree ([crystal#39], ancora aperta); worktree nel `.gitignore` ([crystal#152]); posizione non configurabile ([crystal#19]).
- Nimbalyst: renderer al 100% di CPU all'avvio ([nimbalyst#444]); sessioni perse dopo update ([nimbalyst#65]); archivio che non fa nulla ([nimbalyst#282]).

**Cosa manca**
- Documentazione pubblica del ciclo di vita del worktree (nome, base, pulizia). Non trovata.

**Numeri**
- Crystal ~3.1k stelle, fermo da febbraio 2026. Nimbalyst ~1.8k stelle, attivo.

### Sculptor (Imbue)

**Come lo fa**
- **Container**, non worktree. Ogni agente ha un container con copia del progetto, file system, repo e branch propri, strumenti da devcontainer. [sculptor]
- **Pairing Mode**: sincronizza in due direzioni il codice dell'agente con il repo locale, per provarlo nel proprio IDE. Rileva i conflitti di merge. [sculptor] [hn-sculptor]
- Mac Apple Silicon e Linux. [sculptor]

**Cosa piace**
- Sicurezza: l'agente non tocca la macchina. Nessun reinstall di dipendenze sulla macchina host.

**Cosa lamentano**
- Pesante: più container con Postgres separati "molto pesanti per un portatile"; CPU e memoria alte anche da fermo; crash su Linux/Wayland. [hn-sculptor]

**Cosa manca**
- Leggerezza. Richiede un runtime container.

### opcode (ex Claudia)

- Tauri 2 + React + Rust + SQLite. Gestione progetti e sessioni, checkpoint con timeline a rami. **Nessun supporto worktree** documentato. [opcode]
- ~22.4k stelle, ma ultima release v0.2.0 del 2025-08-31.
- Da battere solo sui checkpoint, non sull'isolamento.

### CodeAgentSwarm, ClaudeGUI, Agentic Stack Desktop

- **CodeAgentSwarm**: più terminali Claude Code in una finestra, con guida ai worktree. Pagina primaria non leggibile (HTTP 429). Dati non verificati. [cas]
- **ClaudeGUI**: nome generico; il progetto più vicino è `markes76/claude-code-gui` (terminali, stream strutturato, CLAUDE.md, MCP). Nessun worktree documentato. [claude-code-gui]
- **Agentic Stack Desktop**: app macOS nativa per memoria condivisa tra agenti (grafo della cronologia di Claude Code, Codex, Cursor). Non gestisce worktree. [agentic-stack]

### Misura locale: copiare `node_modules`

Test sul Mac dell'autore (macOS 26.7, APFS), `node_modules` di un progetto reale: 1,0 GB, 84.594 file.

| Metodo | Tempo |
|---|---|
| `cp -R` (copia completa) | 35,4 s |
| `cp -Rc` (clone APFS file per file) | 16,0 s |
| `clonefile(2)` sull'intera cartella | **1,37 s** |

Il clone dell'intera cartella con una sola chiamata di sistema è ~26 volte più veloce della copia e non occupa spazio finché non si modifica. Nessun concorrente lo documenta. Strumenti CLI come `cow-cli`, `wt` e `agent-worktree` usano copy-on-write, ma via `cp -c`. [cow]

Non è stato possibile misurare `git worktree add`: l'isolamento del worktree dell'agente blocca git fuori dal proprio worktree. Da misurare nella mappa.

## API coinvolte

**git** (versione locale: 2.50.1, Apple Git-155) [git-worktree]
- `git worktree add [-b <branch>] <path> [<commit-ish>]`; `--no-checkout` (per sparse-checkout), `--lock`, `--orphan`, `--detach`.
- `git worktree remove [--force]`, `prune [--expire]`, `lock --reason`, `unlock`, `move`, `repair`, `list --porcelain`.
- `worktree.useRelativePaths` (serve `extensions.relativeWorktrees`): percorsi relativi, utili se il repo si sposta.
- Limiti: stesso branch non in due worktree (salvo `--force`). Sezione BUGS: "Multiple checkout in general is still experimental, and the support for submodules is incomplete. It is NOT recommended to make multiple checkouts of a superproject."
- `gc.worktreePruneExpire` governa la pulizia automatica dei metadati.

**Claude Agent SDK TypeScript** (opzioni attuali) [sdk-ts]
- `cwd`: cartella di lavoro della sessione. È il modo per legare una sessione a un worktree.
- `projectConfigRoot`: percorso del checkout "fidato" di cui `cwd` è un worktree. Legge settings, `.mcp.json`, skill e agent da lì e imposta `CLAUDE_PROJECT_DIR`. Richiede Claude Code ≥ v2.1.275. Risolve il problema "hook/skill non arrivano nel worktree".
- `additionalDirectories`, `env` (sostituisce l'ambiente, non lo unisce), `settingSources`.
- Sessioni: `sessionId`, `resume`, `continue`, `forkSession`, `persistSession`, `sessionStore`.
- `listSessions({ dir, includeWorktrees: true })`: elenca le sessioni di tutti i worktree del repo. Restituisce anche `gitBranch` e `cwd`.
- `startup()` e `prewarm()` (alpha, SDK ≥ v0.3.282): processo pronto prima del prompt. Utile per il tempo "clic → sessione pronta".
- `spawnClaudeCodeProcess`: per lanciare in container o VM.
- Resume in un worktree non valido: risultato con `startup_failure_reason` = `worktree_unverified` o `worktree_resume_refused`. [worktrees]
- Il motore Claude Code crea worktree anche da solo (`EnterWorktree`, `isolation: worktree` per i subagent) e ne ha il ciclo di vita (lock, sweep con `cleanupPeriodDays`). [worktrees]

**macOS**
- `clonefile(2)` / `copyfile(3)` con `COPYFILE_CLONE`: copy-on-write su APFS, per `.env`, `node_modules`, cache di build.
- FSEvents (`FSEventStream`) per sapere quando ricalcolare lo stato git, invece del polling.

## Il meglio da battere

1. **Ciclo di vita**: Conductor (setup/run/archive, 10 porte, `.worktreeinclude`). Candidato: sessione pronta con dipendenze in **< 3 s** su un repo con 1 GB di `node_modules` (clone APFS), contro setup con `pnpm install` dei concorrenti.
2. **Clic**: tutti richiedono ≥ 1 scorciatoia + scelta opzioni. Candidato: **1 azione** (voce o Cmd+N) → sessione isolata, con nome e branch proposti e modificabili.
3. **Porte**: Conductor 10 porte fisse, Superset solo scoperta. Candidato: **0 conflitti di porta** con 10 sessioni che avviano lo stesso dev server, senza configurare nulla.
4. **Risorse**: Superset lagga con 3 workspace per polling git. Candidato: **< 1% CPU da fermo e < 150 MB RAM** dell'app con 10 sessioni aperte (esclusi i processi degli agenti), stato git via FSEvents.
5. **Disco e pulizia**: desktop ufficiale accumula GB. Candidato: spazio extra per sessione **< 50 MB** grazie al copy-on-write, e pulizia automatica al merge.

## Rischi e casi limite

- **Stesso branch** in due sessioni: git lo vieta. Serve branch nuovo o un avviso chiaro.
- **Submodule**: supporto "incompleto" per git. La desktop app ufficiale non li inizializza. Serve `git submodule update --init` nel setup.
- **Git LFS** con filtri `--local`: file puntatore. Claude Code salta di proposito i filter driver del repo per sicurezza.
- **Hook git**: `core.hooksPath` assoluto fa girare gli hook del checkout sbagliato (bug aperto in Claude Code).
- **`.claude/` gitignored**: skill e hook di progetto mancano nel worktree. Usare `projectConfigRoot`.
- **Porte, DB, container, nomi Docker**: il worktree non li isola. Serve un'allocazione per sessione.
- **Disco**: ogni worktree è un checkout completo. Repo grandi e monorepo moltiplicano lo spazio.
- **Clone APFS**: funziona solo sullo stesso volume. Worktree su un disco esterno o altro volume → copia lenta.
- **Polling git**: con molti worktree e agenti di sicurezza aziendali (Jamf, EDR) l'app rallenta.
- **Lock e pulizia**: processi uccisi lasciano lock. Rimozione di cartelle con symlink: rischio di cancellare fuori dal worktree.
- **Posizione**: worktree dentro il repo confondono i build tool (Conductor li ha spostati in `~/conductor/`). Fuori dal repo perdono `.gitignore` e config locale.
- **Resume**: worktree cancellato o spostato → la sessione riparte fuori dall'isolamento. Gestire `startup_failure_reason`.
- **Worktree creati da Claude Code stesso** (`EnterWorktree`, subagent): Bubo deve riconoscerli e non duplicarli.
- **Chi non vuole i worktree**: richiesta molto votata. Serve un'opzione "lavora nella cartella".

## Mappa

### Modello di Sessione (deciso, condiviso con 02, 06, 13, 17, 18)

Fonte: [Modello di Sessione condiviso](https://github.com/mgiuditta/bubo/issues/18); termini in `CONTEXT.md`.

- **Progetto** = qualunque cartella; copia isolata (worktree) solo se è un repo git.
- **Sessione** = unità stabile: id proprio, worktree, branch, catena di Conversazioni dell'agente (resume e fork cambiano l'id SDK, non la Sessione).
- Worktree per impostazione predefinita; "Lavora sul checkout" facoltativo, al massimo una Sessione per Progetto.
- Branch `bubo/<slug>` dal branch attivo nel checkout principale, rinominabile.
- Preparazione: `clonefile` di tutti i file ignorati da git, rispettando `.worktreeinclude` / `.worktreeignore`, cache di build escluse di default; script di setup facoltativo per Progetto.
- 10 porte libere per Sessione, in `BUBO_PORT` e `PORT`.
- **Attività** (Lavora, Attende te, Ferma, Errore) e **Fase** (Aperta, In revisione, Fusa, Archiviata) indipendenti; badge nel Dock = Sessioni in Attende te.
- Al riavvio di Bubo, Lavora → Ferma con "Riprendi" in evidenza; nessuna ripresa automatica.
- Dopo il merge: worktree rimosso, branch cancellato, Fase Archiviata, transcript consultabile. Archiviare senza merge: worktree rimosso, branch tenuto. Cancellare: conferma con elenco delle modifiche perse.
- **Cronologia CLI** in lista separata, sola lettura; aprirne una crea una nuova Sessione come fork.
- **Domanda** = richiesta leggera senza Progetto né worktree; trasformabile in Sessione con un clic.

### Resto della mappa

_da definire_

## Specifica "migliore di"

_da definire_

## Fonti

- [worktrees] Claude Code, "Run parallel sessions with worktrees": https://code.claude.com/docs/en/worktrees
- [desktop] Claude Code, "Desktop application": https://code.claude.com/docs/en/desktop
- [sdk-ts] Claude Agent SDK, riferimento TypeScript: https://code.claude.com/docs/en/agent-sdk/typescript
- [#21236] https://github.com/anthropics/claude-code/issues/21236
- [#12513] https://github.com/anthropics/claude-code/issues/12513
- [#83411] https://github.com/anthropics/claude-code/issues/83411
- [#88747] https://github.com/anthropics/claude-code/issues/88747
- [#83953] https://github.com/anthropics/claude-code/issues/83953
- [#60097] https://github.com/anthropics/claude-code/issues/60097
- [#79530] https://github.com/anthropics/claude-code/issues/79530
- [wmedia] Disco dei worktree nella desktop app: https://wmedia.es/en/tips/claude-code-worktrees-desktop-disk
- [conductor-worktrees] https://conductor.build/docs/concepts/git-worktrees
- [conductor-scripts] https://conductor.build/docs/reference/scripts
- [conductor-files] https://www.conductor.build/docs/reference/files-to-copy
- [conductor-nesting] https://www.conductor.build/docs/tips/nesting-issues
- [conductor-changelog] https://www.conductor.build/changelog
- [conductor-yc] https://www.ycombinator.com/launches/OHk-conductor-run-a-bunch-of-claude-codes-in-parallel
- [performance-dev] "The Conductor rewrite": https://performance.dev/the-conductor-rewrite
- [superset-guide] https://superset.sh/blog/parallel-coding-agents-guide
- [superset-scripts] https://docs.superset.sh/setup-teardown-scripts
- [superset-ports] https://docs.superset.sh/ports
- [superset#4198] https://github.com/superset-sh/superset/issues/4198
- [superset#5537] https://github.com/superset-sh/superset/issues/5537
- [superset#4610] https://github.com/superset-sh/superset/issues/4610
- [superset#4763] https://github.com/superset-sh/superset/issues/4763
- [superset#7125] https://github.com/superset-sh/superset/issues/7125
- [superset#6398] https://github.com/superset-sh/superset/issues/6398
- [superset#691] https://github.com/superset-sh/superset/issues/691
- [superset#4696] https://github.com/superset-sh/superset/issues/4696
- [crystal] https://github.com/stravu/crystal
- [crystal#39] https://github.com/stravu/crystal/issues/39
- [crystal#152] https://github.com/stravu/crystal/issues/152
- [crystal#19] https://github.com/stravu/crystal/issues/19
- [nimbalyst] https://github.com/nimbalyst/nimbalyst
- [nimbalyst#444] https://github.com/nimbalyst/nimbalyst/issues/444
- [nimbalyst#65] https://github.com/nimbalyst/nimbalyst/issues/65
- [nimbalyst#282] https://github.com/nimbalyst/nimbalyst/issues/282
- [sculptor] https://imbue.com/sculptor
- [hn-sculptor] Show HN: Sculptor: https://news.ycombinator.com/item?id=45427697
- [opcode] https://github.com/winfunc/opcode
- [cas] https://www.codeagentswarm.com/es/guias/enjambre-de-agentes-claude-code
- [claude-code-gui] https://github.com/markes76/claude-code-gui
- [agentic-stack] https://theresanaiforthat.com/company/codejunkie99/repository/agentic-stack-desktop/
- [cow] https://docs.rs/cow-cli/0.1.4/cow ; https://github.com/nekocode/agent-worktree ; https://github.com/bkildow/wt-cli
- [git-worktree] https://git-scm.com/docs/git-worktree
