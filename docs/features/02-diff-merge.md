# 02 — Revisione diff e merge in-app, approvazione per blocco

Ticket: [#13](https://github.com/mgiuditta/bubo/issues/13) · Mappa: [#11](https://github.com/mgiuditta/bubo/issues/11) · Ricerca del 2026-09-29.

## Ricerca

Domanda: come fanno i concorrenti a far rivedere il diff dell'agente e a riportarlo su `main`? Chi permette di approvare un singolo blocco (hunk)?

Risposta breve: **nessuno dei concorrenti principali ha l'approvazione per hunk nella vista diff di una sessione**. Tutti lavorano per file (tieni/scarta il file) oppure mandano commenti all'agente. Il merge passa quasi sempre da una PR su GitHub, non da un merge locale.

### App desktop ufficiale di Claude Code (scheda Code)

**Come lo fa**
- Un indicatore `+12 -1` nella sessione apre il pannello diff (anche con ⌘⇧D). Lista file a sinistra, modifiche a destra. [F1]
- Clic su una riga → casella di commento. Invio aggiunge il commento, ⌘Invio li manda tutti insieme a Claude. Claude risponde con un nuovo diff. [F1]
- Pulsante **Review code**: Claude commenta il diff da solo (solo errori, bug, sicurezza; niente stile). [F1]
- In modalità **Manual** l'utente vede ogni modifica prima che venga scritta e la accetta o la rifiuta, ma per singola chiamata allo strumento, non per hunk. [F1]
- Merge: niente merge locale. Si apre una PR; una barra CI mostra i check. **Auto-merge** fa squash quando i check passano (serve l'auto-merge attivo sul repo GitHub). **Auto-fix** prova a sistemare i check rossi. [F1]
- Worktree in `<repo>/.claude/worktrees/`. Dopo il merge: archivio manuale dalla sidebar o **Auto-archive dopo merge o chiusura della PR**. [F1]
- I pannelli diff si possono staccare in una finestra separata. [F1]

**Cosa piace**
- Ciclo corto: commento sulla riga → nuovo diff, senza cambiare app. [F1][F20]
- Review automatica e PR con CI nello stesso posto. [F1]

**Cosa lamentano** (issue GitHub, 2026)
- Il diff non si aggiorna dopo una modifica di Claude: resta vecchio finché non lo riapri (viewer ricostruito il 2026-04-14). [F2]
- Il diff confronta con il ramo base su `origin`, non con `HEAD`: dopo alcuni commit non vedi più "cosa ha fatto questa sessione". [F3] Richiesta di un diff per sessione, indipendente da git. [F4] Richiesta di un diff per singolo messaggio. [F5]
- Il lavoro committato nei worktree dei subagent non si vede, e non si può scegliere il ref di confronto. [F6] Il pannello `/diff` legge la cartella di avvio invece del worktree. [F7]
- Solo vista inline: chiesto lo split side-by-side. [F8] Chiesto di comprimere le righe invariate. [F9] Chiesti "Espandi/Comprimi tutto" e raggruppamento per cartella. [F10][F11]
- **Prestazioni**: su un monorepo (26 GB di `.git`) l'app rilancia `git ls-files --others` ogni ~0,45 s senza attendere la fine della precedente: 32–51 processi `git` in parallelo, load average 265 su un M2 Pro a 10 core, ~190.000 scansioni al giorno per trovare 3 file. [F12] Su Windows 15–20 processi `git` al secondo, sempre. [F13] Il `git diff -M` periodico su repo grandi può usare più GB di RAM e contendere `.git/index.lock`. [F14]
- File illeggibili dalla sandbox mostrati come "Binary file - cannot display diff". [F15]

**Cosa manca**
- Approvazione o rifiuto per hunk o per riga. Le richieste sull'estensione VS Code sono tante e ancora aperte (#61794 14 👍, #67430 12 👍, #33932 37 commenti). [F16][F17][F18]
- Merge locale (squash/rebase su `main` senza GitHub). Gestione conflitti visiva.

**Numeri**
- Commento → invio: 1 clic sulla riga + Invio + ⌘Invio. [F1]
- Merge: 0 clic con auto-merge attivo, ma serve una PR e la CI. [F1]

### Conductor

**Come lo fa**
- Diff Viewer con ⌘⇧D. Vista unificata, filtro per singolo commit, commenti sulle righe cambiate che vanno all'agente, risoluzione dei thread di review GitHub, revert di un file intero. [F21][F22]
- Merge: flusso centrato sulla PR. Scheda **Checks** con stato git, CI, commenti, todo; poi **Create PR**, merge quando è verde, poi **archivia** il workspace (recuperabile dalla History). [F22]
- Conflitti: "fai pull del ramo target, guarda i conflitti, chiedi all'agente di risolverli". Nessuna UI dedicata. [F23]
- Dal changelog: motore diff sostituito con **Pierre Diffs** (0.36.0, feb 2026); raggruppamento per cartella e nascondi-spazi (0.54.0); auto-merge quando la CI passa (0.55.0, mag 2026); modifica dei file direttamente nel diff (0.84.0, set 2026). [F24][F25][F26]

**Cosa piace**
- Ciclo "commento sulla riga → agente" e commenti di GitHub nello stesso pannello. [F21]
- Motore diff virtualizzato (Pierre): solo le righe visibili sono nel DOM. [F27]

**Cosa lamentano**
- Pochi reclami pubblici trovati su diff e merge. Problemi noti documentati: un ramo non può stare in due worktree; output del terminale corrotto. [F23]
- Molte versioni con "fix inaccuratezze su diff grandi" e "performance" (0.9.3, 0.10.1, 0.14.1): il diff era un punto debole ricorrente. [F24]

**Cosa manca**
- Approvazione per hunk. Merge locale senza PR. Risoluzione conflitti visiva.

### Nimbalyst (ex Crystal)

**Come lo fa**
- Crystal (deprecato feb 2026) aveva: un commit per ogni iterazione, **Rebase from main**, **Squash and rebase to main** con nuovo messaggio. [F30]
- Nimbalyst: pannello git accanto alla sessione con file non committati, **Commit with AI**, pulsante **Merge to master**. Rebase anche con modifiche non committate (auto-stash). [F31][F32]
- Nell'editor ogni modifica AI è un diff rosso/verde con **Keep** / **Revert**, una per una o tutte. Ma: la modifica è **già scritta su disco**; Revert ripristina e **non avvisa l'agente**, che continua a credere che la sua modifica ci sia. [F33]
- Diff Peek: popover di diff unificato su ogni file, ridimensionabile. [F34]
- Modalità Pull Request: vista file completa o diff compresso stile GitHub, unificato o split; "diff molto grandi caricati su richiesta"; merge con squash, merge commit o rebase (quelli permessi dal repo), sempre con conferma. [F35]

**Cosa piace**
- È l'unico con keep/revert per singola modifica e un pulsante di merge locale. [F32][F33]
- Squash + rebase su main in un clic (Crystal). [F30]

**Cosa lamentano / limiti dichiarati**
- Il revert non torna all'agente: rischio che l'agente lavori su testo che non c'è più. [F33]
- Commenti inline sulle PR non ancora scrivibili; niente "request changes". [F35]

**Cosa manca**
- Rifiuto per hunk che diventa feedback per l'agente. Conflitti visivi.

### Sculptor (Imbue)

**Come lo fa**
- Pannello **Files** con schede Browse / Changes / Commits. Changes mostra il diff cumulativo non committato. [F36]
- Per correggere: messaggio all'agente. **Discard changes** per file; nessun "scarta tutto". [F36]
- **Commit N changes**: l'agente scrive il messaggio e fa il commit sul ramo del workspace. [F36]
- Ramo target configurabile per workspace; alla cancellazione del workspace il ramo si elimina "mai / solo se sicuro / sempre". [F37]
- **Create PR** via `gh`, con stato PR e CI nel pulsante. [F38] In passato: container Docker, pulsante **Merge** con scelta del ramo e aiuto dell'agente sui conflitti; oggi il default è il worktree, Docker è sperimentale. [F39][F40]

**Cosa manca**
- Hunk, split view, merge locale guidato.

### Superset

**Come lo fa**
- Diff Viewer con vista **split** o **unificata**; file modificati, in stage, non tracciati; stage/unstage **per file**; commit, push, pull, PR. [F41]
- **Focus mode**: un file alla volta con avanti/indietro e posizione ("2/5 in Staged"). [F41]
- Scheda **Review** per i commenti della PR, sincronizzata con GitHub; si mandano righe selezionate a un agente in esecuzione. [F41]

**Cosa manca**
- Stage per hunk non documentato. Strategie di merge e conflitti non documentati. [F41]

### opcode (ex Claudia)

- App Tauri 2 (Rust + React). Nessun worktree, nessun merge.
- **Timeline a checkpoint** con diff tra checkpoint, ripristino in 1 clic, fork di sessione. [F42]
- Utile come idea: il diff "per turno" o "per checkpoint" che Claude Desktop non ha. [F5][F42]

### CodeAgentSwarm

- Più terminali affiancati, board di task, "live file diffs", notifiche native. [F43]
- Dichiara che i conflitti tra terminali sullo stesso file "li risolve Claude automaticamente". Nessuna revisione per hunk documentata. [F43]

### ClaudeGUI e Agentic Stack Desktop

- ClaudeGUI: nome usato per wrapper tipo Claudia/opcode; nessuna funzione di diff/merge documentata oltre a quella di opcode. [F44]
- Agentic Stack Desktop: workspace macOS nativo (macOS 14+) centrato su memoria condivisa e contesto tra agenti. Nessuna funzione di diff/merge documentata. [F45]

### Riepilogo

| | Vista | Per hunk | Commenti → agente | Merge locale | Conflitti | Dopo il merge |
|---|---|---|---|---|---|---|
| Claude Desktop | inline | no (solo per tool call in Manual) | sì, per riga | no, PR + auto-merge squash | no UI | auto-archive |
| Conductor | unificata | no, revert per file | sì, per riga | no, PR + auto-merge | "chiedi all'agente" | archivia |
| Nimbalyst | unif./split (PR) | keep/revert per modifica, già su disco | no dal revert | sì, Merge to master | no UI | — |
| Sculptor | inline | no, discard per file | via chat | no, PR | agente (vecchio flusso) | policy sul ramo |
| Superset | unif./split | no, stage per file | sì, righe PR | no, PR | — | — |

## API e librerie native

**Calcolo del diff**
- `git diff` dalla CLI resta la fonte più sicura: rinomine (`-M`), binari, algoritmi `--histogram` / `--patience`. Attenzione al costo su repo grandi: vedi i bug di Claude Desktop. [F12][F14]
- In Swift, `BidirectionalCollection.difference(from:)` (Myers). Caso peggiore O(n·m): va bene per un file, non per un repo intero. [F50]

**Approvazione per hunk**
- `git apply --cached` applica una patch solo all'indice, senza toccare i file. `--check` la prova a secco. `--recount` ricalcola i conteggi degli header dopo aver tagliato la patch. `--reverse` la annulla. `-3` tenta un merge a 3 vie. [F51]
- Schema: genera il diff, taglia gli hunk scelti, `git apply --cached --recount` per "accetta", `git apply --reverse` sul working tree per "rifiuta". È ciò che fa `git add -p`.

**Merge senza toccare il worktree**
- `git merge-tree --write-tree A B` fa un merge completo (rinomine, 3 vie) **senza leggere né scrivere indice o working tree**. Esce con 0 se pulito, 1 se ci sono conflitti, ed elenca i file in conflitto. Poi `git commit-tree` + `git update-ref` per creare il commit. Permette di mostrare in anticipo "questo merge ha conflitti" anche se `main` è avanzato. [F52] (Introdotto in Git 2.38; la git di Xcode su macOS 26 è 2.54, Apple Git-157. [F6])

**Rewind lato agente (Agent SDK)**
- `enableFileCheckpointing: true` + `rewindFiles(uuid)`: ripristina i file toccati da Write/Edit/NotebookEdit. **Non** traccia Bash né i subagent. Non riavvolge la conversazione. [F53]
- Il permesso `canUseTool` riceve l'input dello strumento (per Edit: `old_string`/`new_string`) prima della scrittura; può negare con un messaggio o approvare con un input modificato. In `acceptEdits` o `bypassPermissions` il callback **non** viene chiamato. [F54][F55] Serve per l'approvazione "prima di scrivere"; per il rifiuto a posteriori di un hunk bisogna dire all'agente cosa è stato tolto (il problema di Nimbalyst). [F33]

**Git: libgit2 o CLI**
- libgit2 ha binding Swift mantenuti (swift-libgit2 1.0.1, gen 2026; fork di SwiftGit2 aggiornati 2026). [F56] Ma non rispetta sempre config, hook e fsmonitor dell'utente come la CLI.
- La CLI `git` è quella che usano tutti i concorrenti e l'Agent SDK stesso. Il rischio sono i processi: serve single-flight, debounce e FSEvents al posto del polling. [F12][F13]

**Vista e syntax highlight**
- TextKit 2 fa layout solo del viewport; di default in macOS da Ventura. Ma ci sono segnalazioni di scroll lento oltre ~3.000 righe e più RAM di TextKit 1 (~1,2 GB contro ~0,5 GB in un test). [F57][F58]
- **STTextView**: sostituto di NSTextView su TextKit 2, con numeri di riga e plugin. [F59]
- **CodeEditTextView / CodeEditSourceEditor**: layout iniziale veloce, tree-sitter, diff incluso; dichiarato "non pronto per la produzione". [F60]
- **SwiftTreeSitter + Neon** (ChimeHQ): highlight incrementale, invalidazione minima, compatibile TextKit 1 e 2; l'autore avverte che il calcolo dei range con TextKit 2 è difficile. [F61]
- Alternativa per diff enormi: vista a righe virtualizzata (NSTableView/`List` con righe riciclate o Metal) invece di un unico text view. È la stessa idea di Pierre Diffs sul web. [F27]

## Il meglio da battere

1. **Hunk**: nessuno approva/rifiuta per hunk nel diff della sessione. Candidato: accetta/rifiuta un hunk in ≤ 1 clic o 1 tasto, con il rifiuto riportato all'agente in automatico (Nimbalyst non lo fa). [F33]
2. **Merge locale**: i concorrenti ci arrivano via PR + CI (Claude Desktop, Conductor). Candidato: squash-merge su `main` in ≤ 2 clic, con anteprima conflitti prima del clic via `merge-tree` in < 500 ms su un repo medio. [F1][F22][F52]
3. **Diff grandi**: candidato 60 fps di scroll (120 su ProMotion) su un diff da 50.000 righe; primo frame < 200 ms; highlight visibile < 100 ms dopo lo scroll. Riferimento: Pierre virtualizza, TextKit 2 rallenta oltre ~3.000 righe. [F27][F57]
4. **Costo a riposo**: candidato 0 processi `git` al secondo a riposo, al massimo 1 scansione in corso per worktree, CPU < 1 % con app inattiva. Contro 15–20 processi/s e load 265 di Claude Desktop. [F12][F13]
5. **Diff giusto**: diff sempre aggiornato (< 300 ms dopo una scrittura) e scelta del confronto: sessione, turno, `HEAD`, ramo base. Contro diff stantio e confronto fisso di Claude Desktop. [F2][F3][F4]

## Rischi e casi limite

- **Modifiche via Bash e subagent**: il checkpoint dell'SDK non le vede. Il diff va calcolato da git, non dal log degli strumenti. [F53]
- **Rifiuto a posteriori**: se un hunk viene tolto dopo la scrittura, l'agente non lo sa e la prossima Edit può fallire (`old_string` non trovato). Bisogna dirglielo. [F33]
- **`main` avanzato**: il diff "contro il ramo base" cambia sotto i piedi. Serve un merge-base fisso per la sessione e un avviso "main è avanzato di N commit". [F3][F52]
- **Conflitti**: tutti delegano all'agente. Serve almeno la lista dei file in conflitto prima del merge e un'opzione "risolvi con l'agente nel worktree".
- **Ramo già usato**: un ramo può stare in un solo worktree alla volta. [F23]
- **Dopo il merge**: rimuovere worktree e ramo solo se il merge è confermato e non ci sono modifiche locali. Sculptor ha la policy "mai / se sicuro / sempre". [F37]
- **Squash e ascendenza**: dopo uno squash-merge, un rebase successivo dello stesso ramo rigenera conflitti. Meglio chiudere il ramo dopo lo squash.
- **Repo enormi, submodule, LFS**: scansioni costose; `.git` da decine di GB. Serve single-flight, debounce, FSEvents e un timeout. [F12][F14]
- **`index.lock`**: operazioni git in background possono bloccare quelle dell'utente o dell'agente. [F14]
- **Binari e file illeggibili**: distinguere "binario" da "non leggibile per permessi o sandbox". [F15]
- **Rinomine**: `-M` costa su diff grandi; va mostrato come rinomina, non come elimina + crea.
- **Fine riga e spazi**: CRLF e whitespace (Conductor ha dovuto aggiungere "nascondi spazi" e fix CRLF). [F25]
- **TextKit 2**: rischio di scroll lento e RAM alta su file lunghi senza a capo. [F57][F58]

## Mappa

### Revisione per blocco (decisa)

Fonte: [Prototipo: revisione diff per blocco](https://github.com/mgiuditta/bubo/issues/21), branch `prototype/diff-blocchi`. Scelta delegata dall'autore.

- **Base**: lista dei file a sinistra (barretta per blocco: accettato, rifiutato, da decidere; ⚠ sui file in conflitto) + diff continuo a destra, righe virtualizzate.
- **Focus** (`f`): un blocco alla volta, grande, con Rifiuta / Nota / Accetta e la fila dei blocchi sotto.
- **Affiancato** (`s`): prima e dopo in due colonne, per schermi larghi.
- Ogni blocco mostra il **perché** scritto dall'agente, `+n −m` e i pulsanti Accetta / Rifiuta.
- Tastiera: `j`/`k` blocco, `a` accetta, `x` rifiuta, `c` nota all'agente (rifiuta e rimanda con la nota), `⇧A` accetta il file, `⌘↩` fondi.
- Dopo una decisione il cursore salta al prossimo blocco non deciso.
- Testata: conflitti previsti con `git merge-tree` prima del merge, progresso `n/N`, "Fondi" attivo solo a blocchi tutti decisi; i rifiutati tornano all'agente come nuovo turno della stessa Sessione.
- Misura da tenere: azioni e secondi dalla prima decisione al merge (contatore del prototipo).

### Resto della mappa

### Merge (deciso)

Fonte: [Strategia di merge e conflitti](https://github.com/mgiuditta/bubo/issues/23).

- Squash predefinito, merge commit a scelta per Progetto; messaggio proposto dall'agente dai "perché" dei blocchi accettati, modificabile.
- Conflitti previsti con `merge-tree`: li risolve l'agente nel worktree portando dentro il branch di partenza; la risoluzione arriva come blocchi nuovi da rivedere. Nessun editor di conflitti.
- Checkout principale con modifiche non salvate sugli stessi file: merge bloccato con spiegazione; su altri file procede. Mai stash automatici.
- "Fondi" senza conferma aggiuntiva (reversibile), "Annulla merge" per 10 s; mai push automatico.
- Blocchi rifiutati → "Rimanda all'agente" (niente merge, Sessione continua, accettati restano approvati). "Fondi" solo con tutto accettato; "Fondi gli accettati e scarta il resto" nel menu secondario, con conferma.

## Specifica "migliore di"

Miglior concorrente: **Nimbalyst** (tieni/annulla per modifica) e **Claude Desktop** (diff + PR), ma nessuno approva per blocco, nessuno mostra i conflitti prima e il diff di Claude Desktop è spesso stantio.
Bubo lo supera così:
- **1 tasto per blocco** (`a`/`x`), rifiuto rimandato all'agente con nota; revisione di 10 file / 14 blocchi in **≤ 16 azioni** da tastiera.
- **Conflitti previsti prima del clic** con `merge-tree` in **< 500 ms**; squash-merge locale in **≤ 2 azioni**.
- Diff aggiornato **< 300 ms** dopo una scrittura; **60 fps** di scroll su 50.000 righe, primo frame **< 200 ms**.
- **0 processi `git` a riposo**, contro 15–20 al secondo di Claude Desktop.

## Fonti

- [F1] Claude Code Desktop, docs: https://code.claude.com/docs/en/desktop
- [F2] anthropics/claude-code #52740, diff stantio: https://github.com/anthropics/claude-code/issues/52740
- [F3] #52179, diff contro origin e non HEAD: https://github.com/anthropics/claude-code/issues/52179
- [F4] #62655, diff per sessione: https://github.com/anthropics/claude-code/issues/62655
- [F5] #53628, diff per messaggio: https://github.com/anthropics/claude-code/issues/53628
- [F6] #93786, worktree dei subagent invisibili: https://github.com/anthropics/claude-code/issues/93786
- [F7] #89395, `/diff` senza cwd: https://github.com/anthropics/claude-code/issues/89395
- [F8] #85514, split view: https://github.com/anthropics/claude-code/issues/85514
- [F9] #65311, comprimi righe invariate: https://github.com/anthropics/claude-code/issues/65311
- [F10] #48744, Espandi/Comprimi tutto: https://github.com/anthropics/claude-code/issues/48744
- [F11] #54499, raggruppa per cartella: https://github.com/anthropics/claude-code/issues/54499
- [F12] #95124, `git ls-files` 2,2 volte/s su macOS: https://github.com/anthropics/claude-code/issues/95124
- [F13] #94478, ~17 processi git/s su Windows: https://github.com/anthropics/claude-code/issues/94478
- [F14] #96184, `git diff -M` periodico costoso: https://github.com/anthropics/claude-code/issues/96184
- [F15] #92101, file illeggibili mostrati come binari: https://github.com/anthropics/claude-code/issues/92101
- [F16] #61794, per-hunk accept/reject (VS Code): https://github.com/anthropics/claude-code/issues/61794
- [F17] #67430, accept/reject per riga: https://github.com/anthropics/claude-code/issues/67430
- [F18] #33932, review UI stile Copilot: https://github.com/anthropics/claude-code/issues/33932
- [F20] Riepilogo terzo sul flusso preview/review/merge: https://www.gend.co/blog/claude-code-preview-review-merge
- [F21] Conductor, Diff Viewer: https://www.conductor.build/docs/core/diff-viewer
- [F22] Conductor, Review and merge: https://www.conductor.build/docs/guides/review-and-merge
- [F23] Conductor, Troubleshooting: https://www.conductor.build/docs/troubleshooting/issues
- [F24] Conductor, changelog: https://www.conductor.build/changelog
- [F25] Conductor, changelog pag. 5 (0.50–0.59): https://www.conductor.build/changelog/page/5
- [F26] Conductor 0.36.0, Pierre Diffs: https://www.conductor.build/changelog/0.36.0-sonnet-4-6-pierre-diffs
- [F27] Pierre Diffs: https://diffs.com/ · https://diffs.com/llms.txt
- [F30] stravu/crystal README v0.3.0: https://github.com/stravu/crystal/blob/v0.3.0/README.md
- [F31] Nimbalyst, Worktrees: https://docs.nimbalyst.com/developer-features/worktrees.md
- [F32] Nimbalyst, Working with Git: https://docs.nimbalyst.com/developer-features/working-with-git.md
- [F33] Nimbalyst, AI Editing, Red/Green Diff, Approval: https://docs.nimbalyst.com/visual-editors-powered-by-ai/markdown-wysiwyg/ai-editing-red-green-diff-approval.md
- [F34] Nimbalyst, File Edits Sidebar: https://docs.nimbalyst.com/file-management/file-edits-sidebar.md
- [F35] Nimbalyst, Pull Request Reviews: https://docs.nimbalyst.com/developer-features/pull-request-reviews.md
- [F36] Sculptor, Changes: https://github.com/imbue-ai/sculptor/blob/main/docs/help/changes.md
- [F37] Sculptor, Workspaces: https://github.com/imbue-ai/sculptor/blob/main/docs/help/workspaces.md
- [F38] Sculptor, Pull Requests: https://github.com/imbue-ai/sculptor/blob/main/docs/help/pull_requests.md
- [F39] Sculptor, README: https://github.com/imbue-ai/sculptor
- [F40] Imbue, pagina prodotto: https://imbue.com/product/sculptor
- [F41] Superset, Diff Viewer: https://docs.superset.sh/diff-viewer
- [F42] opcode README: https://github.com/winfunc/opcode
- [F43] CodeAgentSwarm, guida sessioni multiple: https://www.codeagentswarm.com/en/guides/run-multiple-claude-code-sessions · https://www.codeagentswarm.com/en/guides/claude-code-gui
- [F44] Claudia su ClaudeLog: https://claudelog.com/addons/claudia
- [F45] Agentic Stack Desktop: https://theresanaiforthat.com/company/codejunkie99/repository/agentic-stack-desktop/
- [F50] Swift `difference(from:)`: https://developer.apple.com/documentation/swift/bidirectionalcollection/difference(from:)
- [F51] `git apply`: https://git-scm.com/docs/git-apply
- [F52] `git merge-tree`: https://git-scm.com/docs/git-merge-tree
- [F53] Agent SDK, file checkpointing: https://code.claude.com/docs/en/agent-sdk/file-checkpointing
- [F54] Agent SDK, permessi: https://code.claude.com/docs/en/agent-sdk/permissions
- [F55] Agent SDK, approvazioni e input utente: https://code.claude.com/docs/en/agent-sdk/user-input
- [F56] swift-libgit2 / SwiftGit2: https://swiftpackageregistry.com/Formkunft/swift-libgit2 · https://swiftpackageregistry.com/light-tech/SwiftGit2
- [F57] Apple Developer Forums, prestazioni TextKit 2: https://developer.apple.com/forums/thread/729491
- [F58] WWDC22, What's new in TextKit and text views: https://developer.apple.com/videos/play/wwdc2022/10090/
- [F59] STTextView: https://github.com/krzyzanowskim/STTextView
- [F60] CodeEditSourceEditor: https://swiftpackageregistry.com/CodeEditApp/CodeEditSourceEditor
- [F61] Neon (ChimeHQ): https://github.com/ChimeHQ/Neon
