# Ricerca #444 — Accesso agli Allegati: la cartella intera o il solo file

Ticket: [#444](https://github.com/mgiuditta/bubo/issues/444). Collegati: [#98](https://github.com/mgiuditta/bubo/issues/98) (trascinamento, PR #443), [#66](https://github.com/mgiuditta/bubo/issues/66) (disclaim), [#216](https://github.com/mgiuditta/bubo/issues/216) (blocchi della Sandbox). Spec: [`docs/features/09-sistema.md`](../features/09-sistema.md#allegati-e-fornitori), [`docs/features/22-sandbox.md`](../features/22-sandbox.md). ADR: [0005](../adr/0005-claude-senza-i-permessi-tcc-di-bubo.md).
Ricerca del 2026-10-02, su Linux: nessuna prova sul Mac. SDK del ponte `@anthropic-ai/claude-agent-sdk` 0.3.286. Fonti lette alla stessa data.

**Domanda.** Quando l'utente trascina un file, `claude` deve poterlo leggere senza ricevere la cartella intera che lo contiene. Come si fa, che cosa cambia per TCC, e chi cancella i PNG salvati in `Domande/Allegati`?

## In sintesi

- **`additionalDirectories` dà più della lettura.** L'SDK passa ogni cartella come `--add-dir` [C3]. La cartella diventa una cartella di lavoro: si legge senza chiedere, le modifiche seguono la modalità (`acceptEdits` le approva da sola, la Modalità autonoma le approva senza classificatore) [C1][C2]. Con la Sandbox accesa i comandi ci possono anche scrivere (spec 22). Con la sorgente `project`, `claude` carica inoltre skill, comandi e subagent dal suo `.claude/` [C1][C3]. Se trascino `~/Downloads/fattura.pdf` in una Sessione autonoma, l'agente può modificare tutto `~/Downloads`.
- **Per TCC la copia è la sola strada pulita.** `claude` parte con il disclaim e non ha l'accesso per intento (`com.apple.macl`) che il trascinamento dà a Bubo [M1]. Per leggere in Scrivania, Documenti o Download chiede File e cartelle a nome proprio (spec 09). Il permesso vale per **tutta** la cartella protetta e resta, per `claude` e per ogni suo comando. Un clone APFS dentro `Application Support/Bubo` non è una cartella protetta: niente avviso, niente permesso largo.
- **Strada consigliata.** File e immagini: **clone** (`FileManager.copyItem`, che su APFS fa `clonefile` [A1]) in `Domande/Allegati/<uuid>/`, al momento dell'invio. Cartelle: regola di sessione `Read(//percorso/**)` al posto di `additionalDirectories`, con una **conferma** se la cartella è ampia (home, radice, primo livello della home, radice di un volume). PNG e cloni: **pulizia per età**, 7 giorni, all'avvio di Bubo.
- **Da escludere:** symlink (`claude` controlla anche il bersaglio [C1], TCC guarda il percorso vero), hard link (stesso file, una modifica tocca l'originale, niente link tra volumi diversi), `additionalDirectories` della cartella del file (lo stato attuale).

## Vincoli già decisi

- **ADR 0005:** `claude` e i suoi comandi partono con il disclaim. Non ereditano Microfono né File e cartelle di Bubo e chiedono File e cartelle a nome proprio. Provato in #66.
- **Spec 09, Allegati e fornitori:** "Claude riceve i file **per percorso** e l'agente li legge: Bubo gli apre in lettura la cartella di ogni Allegato (`additionalDirectories`)". Un'immagine senza file diventa un PNG nella cartella delle Domande. Dal gesto all'Orb in Ascolto: **< 300 ms**.
- **Spec 22:** con la Sandbox si scrive "nella cartella di lavoro, nelle cartelle aggiunte e in una temp per utente". [Consenti in questo Progetto] apre scritture solo per la cartella del file, "mai la radice, una cartella di primo livello o la home": la stessa soglia serve qui.
- **Codice su `main`:**
  - `QuestionModel.readableDirectories(for:)` (`Bubo/Question/QuestionModel.swift`) restituisce, per ogni Allegato con percorso, la cartella stessa o `deletingLastPathComponent()` del file. La stessa funzione serve le Domande (`QuestionModel`) e i trascinamenti nell'HUD con una Sessione davanti (`SessionStore`).
  - Il ponte (`bridge/src/main.ts`, `ask`) mette `dirs` in `additionalDirectories`.
  - Le Domande girano in `~/Library/Application Support/Bubo/Domande` (`QuestionModel.directory()`). `OrbDropTarget` salva le immagini senza file in `Domande/Allegati/<uuid>/Immagine.png` e niente le cancella.
  - Le Domande non salvano la conversazione (`persistSession: false`); gli Allegati vivono solo in memoria (`lastAttachments`).

## Come `claude` decide che cosa può leggere

Dalla documentazione di Claude Code, che è il motore dell'Agent SDK:

| Meccanismo | Effetto | Fonte |
|---|---|---|
| Cartelle di lavoro (`cwd` + `--add-dir`/`additionalDirectories`) | Read, Grep e Glob senza chiedere; modifiche secondo la modalità; `acceptEdits` approva anche `mkdir`, `touch`, `rm`, `mv`, `cp`, `sed` lì dentro; in auto mode "read-only actions and file edits in your working directory are auto-approved" | [C1][C2] |
| `--add-dir` (anche dall'SDK) | Carica da `.claude/` della cartella skill, comandi e subagent (con la sorgente `project`), e da `settings.json` le chiavi `enabledPlugins` ed `extraKnownMarketplaces` | [C1][C3] |
| Sandbox | Le cartelle aggiunte sono scrivibili per Bash; le regole `Read`/`Edit` confluiscono nella configurazione della sandbox | [C1], spec 22 |
| Regola `Read(path)` in `allowedTools` | Approva la lettura del solo percorso. `//percorso` è assoluto, `/percorso` parte dalla cartella di lavoro principale, sintassi gitignore. Copre Read, best effort Grep e Glob, i comandi Bash riconosciuti (`cat`, `head`, …) e i redirect `< file` | [C1] |
| Regola `Read` deny | Vale anche per `cat`, `head`, `tail`, `sed`, `tee` e per i redirect, ma non per un `grep -r .` lanciato dalla cartella né per uno script Python o Node che apre i file da sé | [C1] |
| Comandi Bash di sola lettura (`ls`, `cat`, `head`, `grep`, `find`, …) | Partono **senza chiedere in ogni modalità**, anche fuori dalle cartelle di lavoro, a meno di `permissions.blockReadsOutsideWorkingDirectories` | [C1][C2] |
| Symlink | Una regola allow vale solo se combaciano **sia** il percorso chiesto **sia** quello risolto; una deny se ne combacia uno dei due | [C1] |
| `canUseTool` | Bubo viene chiamato solo quando nessuna regola né modalità ha già deciso | [C3] |

Due conseguenze:

1. **Togliere la cartella non chiude la lettura.** Senza `additionalDirectories`, un `cat ~/Downloads/altro.pdf` parte comunque senza chiedere [C1]. Il confine vero per la lettura dei comandi è TCC, cioè il disclaim (sotto), oppure la Sandbox con `denyRead`. Quello che la cartella aggiunta regala davvero è **Read/Grep/Glob senza Richiesta, modifiche facili, scritture in Sandbox e caricamento di configurazione**. La issue parla di "accesso in lettura", ma il rischio maggiore sono le scritture.
2. **Una regola `Read(//…)` fa da `additionalDirectories` di sola lettura**: lettura senza Richiesta, nessuna modifica approvata in automatico, nessun `.claude/` caricato. Nell'SDK non esiste un'opzione "cartella in sola lettura"; Claude desktop su 3P ha `mode: "ro"`, ma solo per i file tool [D1].

## TCC: che cosa vede `claude` partito con il disclaim

- Il trascinamento su un'app non in sandbox mette sul file l'attributo `com.apple.macl`, che dà **all'app che riceve** l'accesso al file per sempre, anche fuori da TCC, e passa ai processi di cui l'app è responsabile [M1]. Con il disclaim `claude` è responsabile di sé, quindi non lo eredita. La spec 09 lo dice già; non è provato a parte in #66, che ha provato File e cartelle e Microfono.
- Download, Scrivania e Documenti sono classi di archiviazione della policy di piattaforma, con controlli legati al percorso e al processo responsabile [M2][M3]. Il primo `Read` di `claude` su `~/Downloads/x.pdf` mostra quindi l'avviso "claude vorrebbe accedere ai file nella cartella Download". Il consenso vale **per tutta la cartella**, per `claude` e per ogni comando che lancia, e resta finché l'utente non lo toglie nelle Impostazioni.
- **La copia lo evita.** Bubo legge il file grazie al `macl` del trascinamento e lo clona in `Application Support/Bubo/Domande/Allegati/<uuid>/`, che non è protetta. `claude` legge la copia: nessun avviso, nessun consenso largo. È anche l'unico modo in cui "un file solo" resta davvero un file solo per TCC.
- **Hard link:** TCC lega la classe di archiviazione al vnode e al percorso [M2]. Non ho trovato fonti su come tratta un hard link creato fuori dalla cartella protetta verso un file dentro. Non provato, e comunque scartato per gli altri motivi (tabella sotto).
- **Symlink:** TCC risolve il percorso, quindi l'avviso parte lo stesso. In più la regola allow di `claude` non combacia, perché il bersaglio è fuori [C1].

## Le opzioni per un file

| # | Strada | Lettura del solo file | Scrittura nella cartella | Avviso TCC per Download/Scrivania/Documenti | Costo | Note |
|---|---|---|---|---|---|---|
| 0 | `additionalDirectories` della cartella del file (oggi) | No, tutta la cartella | Sì: secondo la modalità, in Sandbox, in auto mode | Sì, consenso per tutta la cartella | — | Carica anche `.claude/` della cartella |
| 1 | **Clone** in `Domande/Allegati/<uuid>/nome` (`FileManager.copyItem`) | **Sì** | No (solo sulla copia) | **No** | Clone APFS: istantaneo e 0 byte sullo stesso volume [A1]; copia vera da un altro volume | Le modifiche dell'agente non toccano l'originale |
| 2 | Regola `Read(//percorso/del/file)` in `allowedTools`, nessuna cartella | Sì (Read senza Richiesta) | No: le modifiche passano da `canUseTool` | **Sì**, consenso per tutta la cartella | Nessuno | Va escapata la sintassi gitignore (`*`, `?`, `[`, `]`, `\`, `!` e `#` iniziali); da provare con `(` e `)` nel nome |
| 3 | Hard link in `Domande/Allegati` | Sì | Sull'originale: è lo stesso file | Non noto | Nessuno | Non funziona tra volumi diversi; il `macl` e gli attributi sono condivisi. Scartato |
| 4 | Symlink in `Domande/Allegati` | No: la regola allow non combacia [C1] | — | Sì | Nessuno | Scartato |
| 5 | Nessun accesso: solo il percorso nel prompt | Sì, con una Richiesta di permesso per ogni Read | No | Sì | Nessuno | Le Richieste nelle Domande sono rumore |
| 6 | Contenuto nel prompt (come per gli altri fornitori) | — | — | No | Token; impossibile per immagini e binari via percorso | Lo fanno ChatGPT e, per i documenti, Cursor (sotto) |

**Cartelle.** Una cartella non si clona: può essere enorme, e con `copyItem` si clona solo sullo stesso volume. Per le cartelle:

- **Regola `Read(//cartella/**)`** al posto di `additionalDirectories`. Si legge tutto, si scrive solo dopo una Richiesta, niente `.claude/` caricato.
- **Conferma se la cartella è ampia**: `~`, `/`, `/Users`, un primo livello della home (`~/Desktop`, `~/Documents`, `~/Downloads`, `~/Library`, …), la radice di un volume (`/Volumes/X`). Nella chip, prima dell'invio: "Claude potrà leggere tutto in Download". È la soglia della spec 22.
- L'avviso TCC per `claude` resta per le cartelle protette, come già descritto nella spec 09.

## Come fanno gli altri client

| Client | Allegato fuori dal progetto | Accesso dell'agente |
|---|---|---|
| **Claude desktop / Cowork** | Si allegano **cartelle di lavoro**: l'agente legge, crea e modifica tutto lì dentro. Su 3P `allowedWorkspaceFolders` limita le radici, con `mode: "ro"` e controllo sul percorso **risolto** (niente fuga con symlink o `..`) [D1] | Cartella intera; nella VM di Cowork solo le cartelle montate |
| **Claude Code CLI** | Le immagini incollate o allegate vanno in una cartella `images/` per sessione nella temp (`CLAUDE_CODE_TMPDIR`); prima in `~/.claude/image-cache/<sessione>/`, cancellate dopo `cleanupPeriodDays` (30 giorni) [C4] | Copia di Claude Code, non l'originale |
| **Cursor** (3.17) | I documenti trascinati da fuori (`.md`, `.yaml`, …) diventano un **caricamento del contenuto**, non un riferimento al percorso. Per il percorso: aggiungere la cartella allo spazio di lavoro [U1] | Contenuto nel prompt, oppure tutta la cartella |
| **Zed** | Immagini trascinate o incollate nel pannello; file con `@` dal progetto [Z1] | Contenuto nel contesto; gli strumenti lavorano sul progetto |
| **ChatGPT per Mac** | Il file si carica nella conversazione (graffetta o trascinamento) [O1] | Contenuto sul server, nessun accesso al disco |
| **Codex CLI** | `--add-dir` aggiunge radici **scrivibili** alla sandbox [X1] | Cartella intera, in scrittura |

Nessuno dà all'agente "il solo file" con il suo percorso originale: o si **copia o carica il contenuto** (Claude Code per le immagini, Cursor, ChatGPT, Zed), o si dà **tutta la cartella** con un confine chiaro (Cowork, Codex). L'opzione 1 tiene il meglio di tutte e due: per l'agente è un file su disco, per l'utente il suo originale non si tocca.

## Pulizia: `Immagine.png` e i cloni

- Le Domande non salvano la conversazione e gli Allegati vivono solo in memoria: dopo la chiusura di Bubo nessuno usa più `Domande/Allegati/<uuid>/`.
- Fanno eccezione i trascinamenti nell'HUD con una Sessione davanti: il transcript della Sessione conserva il percorso, e una ripresa giorni dopo potrebbe rileggerlo.
- **Politica proposta:**
  - All'avvio, fuori dal percorso critico (dopo l'Orb, come la spec 25 vuole per `claude`), Bubo cancella le cartelle `Domande/Allegati/<uuid>/` più vecchie di **7 giorni** (data di creazione della cartella).
  - Claude Code usa 30 giorni per le immagini [C4]. Qui 7 bastano: un clone sullo stesso volume non occupa spazio, una copia da un altro volume sì.
  - Se le Sessioni devono rileggere gli Allegati più a lungo, possono metterli in una cartella propria (`Sessioni/<id>/Allegati`) che segue la vita della Sessione (archiviata → cancellata).
- **Diagnostica:** un log `Logger` con il numero di cartelle e i byte liberati, senza nomi di file (`privacy: .private` se servisse un nome).

## Raccomandazione

1. **File e immagini → clone in `Domande/Allegati/<uuid>/`**, al momento dell'invio e non al rilascio (il rilascio deve restare sotto i 300 ms). Con `FileManager.copyItem(at:to:)`, che clona su APFS.
   - Il prompt indica la copia e l'originale: "- …/Allegati/<uuid>/fattura.pdf (copia di ~/Downloads/fattura.pdf)". Se l'utente chiede di modificare l'originale, l'Edit fuori dalle cartelle di lavoro arriva a Bubo come Richiesta di permesso.
   - Nelle **Domande** non serve nessuna cartella aggiunta: `Allegati` sta già dentro la `cwd`.
   - Nelle **Sessioni** basta `Read(//…/Allegati/<uuid>/**)` come regola di sessione.
   - `Allegato` resta com'è; cambia solo `readableDirectories(for:)`, che diventa la preparazione della copia più le regole.
2. **Tetto per la copia vera da un altro volume.** Il clone è gratis, una copia da un disco esterno no. Sopra una soglia (da fissare, per esempio 200 MB) si passa all'opzione 2, `Read(//file)` sull'originale; per i dischi esterni macOS chiede comunque "Volumi rimovibili".
3. **Cartelle → `Read(//cartella/**)`** invece di `additionalDirectories`, più la **conferma nella chip** per le cartelle ampie (soglia della spec 22). `additionalDirectories` resta solo per i Progetti, dove serve scrivere.
4. **Pulizia a 7 giorni** di `Domande/Allegati` all'avvio. Vale per i PNG di oggi e per i cloni.
5. **Aggiornare la spec 09** ("Bubo gli apre in lettura la cartella di ogni Allegato") e scrivere un ADR breve: "un Allegato file arriva a `claude` come copia, mai come cartella".

## Rischi

- **L'agente lavora su una copia.** "Correggi questo file" in una Sessione modificherebbe la copia. Va detto nel prompt (copia + originale), e l'Edit dell'originale passa da una Richiesta.
- **Allegati di altre Domande leggibili.** `Domande/Allegati` sta dentro la `cwd` di tutte le Domande: una Domanda può leggere i cloni delle altre degli ultimi 7 giorni. Se è un problema, la `cwd` di ogni Domanda diventa `Domande/<uuid>`, oppure si nega `Read(./Allegati/**)` tranne il proprio.
- **Sintassi delle regole.** Un nome con `[`, `*`, `!` o parentesi può rompere `Read(//…)` [C1]. Va escapato e provato. Una regola allow non valida "doesn't approve anything": si chiude su una Richiesta, non si apre.
- **Rilettura dopo la pulizia**: una Sessione ripresa dopo 7 giorni trova il percorso sparito. L'agente lo dice; accettabile, oppure c'è la cartella per Sessione.
- **Spazio**: copie vere da volumi diversi o da file system non APFS. Tetto e pulizia.
- **Comandi di sola lettura**: `cat` fuori dalle cartelle di lavoro parte comunque senza chiedere [C1]. Questa issue non chiude la lettura del disco da parte di `claude`: lo fanno TCC (disclaim) e la Sandbox.
- **Il `macl` resta su Bubo** per sempre e non si revoca [M1]. Non cambia con questa scelta, ma va saputo.

## Domande per chi decide (`ready-for-human`)

1. Va bene che l'agente lavori sulla **copia** anche nelle Sessioni, o lì il file trascinato dentro il Progetto resta per percorso? Un file già nel Progetto non ha bisogno di nulla: sta nella `cwd`.
2. Soglia del **tetto** per la copia vera (200 MB?) e cosa fare sopra: regola sull'originale con avviso TCC, o rifiuto con "trascina una cartella"?
3. **Retention**: 7 giorni per tutto, o cartella per Sessione con la vita della Sessione?
4. Elenco esatto delle **cartelle ampie** che chiedono conferma: anche `~/Library`, `iCloud Drive`, `/Volumes/X`?
5. Si vuole anche `blockReadsOutsideWorkingDirectories` nelle Domande? Chiuderebbe `cat` fuori dalla `cwd`, ma i file tool **rifiutano** invece di chiedere [C1][C2], e non è chiaro se una regola `Read(//…)` passi lo stesso.

## Da verificare sul Mac (non provato qui)

- `claude` con il disclaim che legge un file trascinato su Bubo da `~/Downloads`: compare l'avviso TCC a nome di `claude`? E se si legge il clone, nessun avviso?
- `FileManager.copyItem` da `~/Downloads` (con il solo `macl` di Bubo) in `Application Support`: riesce, ed è un clone (`st_blocks`, `stat -f %f`)?
- `Read(//percorso/con spazi (1).pdf)` in `allowedTools`: la regola combacia?
- Tempo del clone di un file da 1 GB sullo stesso volume (atteso: pochi ms).

## Fonti

Claude Code e Agent SDK
- C1. "Configure permissions" (cartelle di lavoro, `--add-dir`, regole Read/Edit, symlink, comandi di sola lettura, sandbox) — https://code.claude.com/docs/en/permissions
- C2. "Choose a permission mode" (`acceptEdits`, auto mode, prima lettura fuori dalle cartelle di lavoro) — https://code.claude.com/docs/en/permission-modes
- C3. Agent SDK TypeScript, `Options` (`additionalDirectories` passato come `--add-dir`, `allowedTools`, `canUseTool`) — https://code.claude.com/docs/en/agent-sdk/typescript
- C4. "Explore the .claude directory", Cleaned up automatically (`image-cache`, `cleanupPeriodDays` 30 giorni) — https://code.claude.com/docs/en/claude-directory ; "Settings reference" (`permissions.additionalDirectories`, `blockReadsOutsideWorkingDirectories`, `sandbox.filesystem.*`) — https://code.claude.com/docs/en/settings-reference
- D1. Claude Desktop su 3P, "Desktop and filesystem access" (`allowedWorkspaceFolders`, `mode: "ro"`, percorso risolto) — https://claude.com/docs/third-party/claude-desktop/local-access

Apple e macOS
- A1. "About Apple File System" (`copyItem` crea un clone su APFS) — https://developer.apple.com/documentation/foundation/about-apple-file-system ; Apple Developer Forums 784446 (clonefile e cartelle) — https://developer.apple.com/forums/thread/784446
- M1. Mysk, "CVE-2026-28910" (trascinamento, `com.apple.macl`, accesso permanente dell'app che riceve, maggio 2026) — https://mysk.blog/2026/05/19/cve-2026-28910/
- M2. bdash, "TCC and the platform sandbox policy" (classi di archiviazione di Download, Scrivania, Documenti) — https://bdash.net.nz/posts/tcc-and-the-platform-sandbox-policy/
- M3. Supporto Apple, "Controllare l'accesso a file e cartelle sul Mac" — https://support.apple.com/guide/mac-help/control-access-to-files-and-folders-on-mac-mchld5a35146/mac

Altri client
- U1. Cursor Forum, "External .md/.yaml multi-attach now shows upload chip" (risposta dello staff, 3.17) — https://forum.cursor.com/t/external-md-yaml-multi-attach-now-shows-upload-chip-pdf-icon-instead-of-path-pills/169491
- Z1. Zed, "Agent Panel" — https://zed.dev/docs/ai/agent-panel.html
- O1. OpenAI Help, "ChatGPT macOS app: file uploads and photos" — https://help.openai.com/en/articles/9295234-chatgpt-macos-app-file-uploads-and-photos
- X1. "Multi-Folder Projects in Codex: … Writable Roots" (luglio 2026) — https://codex.danielvaughan.com/2026/07/24/codex-multi-folder-projects-primary-folder-writable-roots-cross-repo-workspace-configuration/
