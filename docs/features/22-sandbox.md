# 22 — Esecuzione in Sandbox

Ticket: [#180](https://github.com/mgiuditta/bubo/issues/180) (ricerca), [#185](https://github.com/mgiuditta/bubo/issues/185) (decisioni), [#184](https://github.com/mgiuditta/bubo/issues/184) (Plugin fuori dalla sandbox), [#186](https://github.com/mgiuditta/bubo/issues/186) (soglie di prestazione). Mappa: [#178](https://github.com/mgiuditta/bubo/issues/178).
Ricerca del 2026-09-30 su macOS **26.7**, CLI `claude` **2.1.285**, Agent SDK TS **0.3.285** (`sdk.d.ts` letto in locale), `@anthropic-ai/sandbox-runtime` **0.0.78**, Apple `container` **1.5.0**, Codex CLI **0.159.2**. Testo completo della ricerca: [research/22-sandbox.md](https://github.com/mgiuditta/bubo/blob/research/22-sandbox/docs/features/research/22-sandbox.md) sul branch `research/22-sandbox`.

> **Nota sulla ricerca.** È scritta prima delle decisioni e in alcuni punti è superata. Il meccanismo non è la sola sandbox di Bash: Bubo aggiunge un proprio cancello sulle scritture di Edit, Write e NotebookEdit ([#185](https://github.com/mgiuditta/bubo/issues/185)). `sandbox-runtime` attorno a tutto `claude` è fuori dalla v1 finché resta in beta. `swift build` non è più un blocco: con `--disable-sandbox` e scrittura nella cache utente funziona (verifica del 2026-09-30 in [#185](https://github.com/mgiuditta/bubo/issues/185)); le dipendenze remote SwiftPM si risolvono fuori dalla Sandbox alla creazione del worktree. `gh` funziona solo con `enableWeakerNetworkIsolation`, che resta spento: `gh` va in `excludedCommands`. `SandboxNetworkAccess` arriva a `canUseTool` solo con `strictAllowlist: false`. I blocchi non stanno in `permission_denials` ma solo nel testo del risultato del comando. Valgono la Mappa e la Specifica qui sotto.

In sintesi: su macOS il meccanismo è già pronto ed è quello di Claude Code. La **sandbox integrata** chiude ogni comando Bash e i suoi figli in un profilo Seatbelt e fa passare la rete da un proxy che ammette solo certi domini. L'SDK la accende con `Options.sandbox` e, passata così, si ferma invece di proseguire senza protezione. Copre però solo Bash: Edit e Write girano nel processo `claude` e li governano le Regole di permesso. Bubo chiude il buco con un cancello proprio sulle scritture degli strumenti incorporati. Il resto è rendere la Sandbox usabile: un preset fisso che fa funzionare `npm`, `swift build` e i dev server senza configurazione, ogni blocco spiegato in una riga con il percorso o l'host, e nelle Automazioni zero attese. Codex e Cursor usano la stessa tecnologia; nessuno dei due spiega i blocchi in chiaro né la accende da solo per il lavoro senza nessuno davanti.

## Ricerca

Riassunto; dettagli, prove e tabelle complete nel file di ricerca.

### Sandbox integrata di Claude Code

- **Cosa isola** [1][2]: Bash, PowerShell, Monitor e tutti i loro processi figli, con Seatbelt su macOS (nessuna installazione). Read, Edit, Write e WebFetch girano nel processo `claude`: li governano le Regole di permesso. Server MCP e hook di tipo command girano liberi. I subagent condividono la sandbox della sessione madre.
- **Filesystem** [1]: scrittura nella cartella di lavoro, nelle cartelle aggiunte e in una temp per utente. Lettura ovunque tranne i percorsi negati; `~/.ssh` e `~/.aws` restano leggibili senza `sandbox.credentials`. In un worktree collegato si scrive anche nella `.git` comune, ma non in `hooks/` e `config`. Percorsi protetti anche dentro le cartelle scrivibili: `.claude/`, `.mcp.json`, file di avvio della shell, `.gitconfig`, `.git/hooks`, `.git/config`.
- **Rete** [1][5]: proxy HTTP/SOCKS fuori dalla sandbox; il profilo permette solo la sua porta locale. Nessun dominio ammesso di default. `allowedDomains` con jolly; `strictAllowlist` nega invece di chiedere e vale solo dal livello `--settings` o superiore. Il proxy decide dal nome host e non apre il TLS: domini larghi come `github.com` permettono esfiltrazione.
- **Scappatoie** [1][3]: `autoAllowBashIfSandboxed` (default `true`) fa partire i comandi in sandbox senza chiedere, tranne deny, ask con contenuto e percorsi critici. `allowUnsandboxedCommands` (default `true`) permette il ritentativo con `dangerouslyDisableSandbox`, che passa dal flusso di permesso normale. `excludedCommands` fa girare comandi fuori, sempre dai permessi. `failIfUnavailable` di default è spento: la CLI avvisa e prosegue senza sandbox. Apple Events (`open`, `osascript`) bloccati di default.
- **Un repo non la allenta** [1]: `filesystem.disabled`, `strictAllowlist`, `mask`, `tlsTerminate`, `allowAppleEvents` non valgono da `.claude/settings.json`.
- **Regole di permesso come sorgente** [1][4]: le allow `Edit(...)` diventano `allowWrite`, le allow `WebFetch(domain:…)` pre-ammettono domini. Le fonti si uniscono: una Regola scritta nei settings allarga anche la sandbox.

### Agent SDK

- `Options.sandbox` con lo schema delle impostazioni [4]. Con `enabled: true` passato così, `failIfUnavailable` vale `true`: se la sandbox non parte, `query()` emette un errore ed esce.
- `Options.settings` è il livello `--settings`: da lì valgono `strictAllowlist` e `credentials.mask` [4].
- `spawnClaudeCodeProcess` avvolge tutto il processo (per esempio con `srt`) [4]. Fuori dalla v1.
- `dangerouslyDisableSandbox` è un campo dell'input di Bash: una Richiesta che lo porta è un tentativo fuori sandbox [4].

### Altri meccanismi

| Meccanismo | Cosa isola | Rete per dominio | Strumenti macOS dentro | Stato |
|---|---|---|---|---|
| Sandbox Bash di Claude Code [1] | Bash + figli | Sì (proxy) | Sì, con eccezioni | Integrata; `Options.sandbox` |
| `srt` attorno a `claude` [2][5] | Tutto il processo, MCP e hook compresi | Sì | Come sopra | Beta |
| `sandbox-exec` scritto a mano [18] | Quello che dice il profilo | No senza proxy | Sì | Deprecato, SBPL non documentato |
| Apple `container` [9][10] | VM Linux | Da costruire | **No** | macOS 26, pkg da amministratore |
| VM macOS [11][12] | Sistema intero | Da costruire | Senza Portachiavi né app dell'utente | Massimo 2 VM per licenza |
| App Sandbox di Bubo | — | — | — | Esclusa: i figli la erediterebbero ([09](09-sistema.md)) |

### Cosa si rompe (prove con CLI 2.1.285)

| Comando | In sandbox | Rimedio verificato |
|---|---|---|
| Scrittura fuori dalla cwd | `operation not permitted` | Voluto |
| `curl` verso dominio non ammesso | `CONNECT tunnel failed, response 403` | Voluto |
| `gh api …` | TLS `OSStatus -26276` (i CLI in Go non raggiungono `trustd`) | Solo `enableWeakerNetworkIsolation`, oppure fuori sandbox |
| `npm view …` | `EPERM` su `~/.npm/_cacache` | `allowWrite` su `~/.npm` |
| Dev server + `curl localhost` | Fallisce | `allowLocalBinding: true` |
| `swift build` | `sandbox_apply: Operation not permitted` (Seatbelt non si annida) | `--disable-sandbox` + scrittura su temp e cache utente ([#185](https://github.com/mgiuditta/bubo/issues/185)) |
| Checkout remoto SwiftPM | Bloccato da `.git/hooks` e `.git/config` protetti | `swift package resolve` fuori sandbox |
| `security find-generic-password` | Raggiunge il Portachiavi | — |
| `xcrun --find clang`, `swift --version` | OK | — |

Costo: `sandbox-exec` aggiunge **circa 5,5 ms per processo** (50 avvii di `/usr/bin/true`). Anthropic dichiara un overhead "minimo"; nessuno pubblica la latenza [1][6].

### Convivenza con il disclaim e con i permessi

- **Disclaim** (ADR 0005): riguarda chi è responsabile per TCC; Seatbelt riguarda le regole del processo, ereditate dai figli. `claude` parte con il disclaim e applica lui `sandbox-exec` ai suoi comandi. La combinazione sullo stesso `claude` non è provata: serve il lanciatore vero.
- **Apple Events** chiusi di default: è lo stesso canale che l'ADR 0005 teme (`osascript` che controlla le app).
- **Senza nessuno davanti** la documentazione chiede un container, una VM o `srt`: la sola sandbox di Bash "non basta" [2]. Rilevante per le Automazioni (`permissionPrompts: 'none'`, [19](19-agenti-automazioni.md)).
- **Dinieghi visibili**: la CLI mette il percorso o l'host negato nel risultato del comando [1]. Cursor ha dovuto riscrivere come mostra i blocchi perché l'agente "ritentava lo stesso comando senza cambiare permessi" [8].

### Concorrenti

| Prodotto | Meccanismo su macOS | File | Rete | Predefinito |
|---|---|---|---|---|
| **Claude Code CLI/SDK** [1][2] | Seatbelt per Bash + proxy | cwd e temp | Nessun dominio, poi prompt | Spenta |
| **Claude Desktop, Cowork** [13][14] | VM con rete propria | Nella VM | `coworkEgressAllowedHosts` | VM per Cowork; Code come la CLI |
| **Codex** [7][15] | `sandbox-exec` + proxy | `workspace-write`; `.git` in sola lettura | Spenta in `workspace-write`, allow/deny con proxy | Accesa |
| **Cursor** (2.0+) [8][16] | `sandbox-exec`, profilo generato | Workspace + temp; `.git/config`, `.git/hooks` protetti | Circa 80 domini predefiniti o "Allow All" | Accesa in Auto-review |
| **Conductor** [17] | Nessuna | Worktree come isolamento logico | Nessun filtro | — |

Unico numero pubblico: Cursor dichiara "il 40% di interruzioni in meno" con la sandbox [8].

## Il meglio da battere

Il riferimento è **Cursor**: stessa tecnologia (Seatbelt + proxy), un elenco di domini predefiniti che fa funzionare i gestori di pacchetti, protezione di `.git/hooks` e `.git/config`, sandbox accesa di default nella modalità automatica. Codex è simile ma spegne del tutto la rete in `workspace-write`. Nessuno dei due chiude le scritture degli strumenti incorporati con un confine verificato, nessuno spiega ogni blocco con il percorso o l'host in chiaro, nessuno pubblica un costo in latenza. Claude Code ha il motore ma lo lascia spento, e da CLI prosegue senza sandbox se questa non parte.

## Rischi e casi limite

- **Perimetro solo Bash**: Edit e Write scrivono fuori se una Regola lo consente o la modalità lo approva. Senza il cancello di Bubo, "Sandbox accesa" sarebbe una promessa falsa.
- **Le Regole di permesso allargano la Sandbox**: una allow `Edit(~/x/**)` o `WebFetch(domain:…)` scritta nei settings dall'utente o dalla CLI apre anche la sandbox, e Bubo non può impedirlo senza riscrivere i file dell'utente.
- **Esfiltrazione su domini larghi**: il proxy non apre il TLS. Per questo `github.com` non entra nel preset.
- **Sandbox che non parte in silenzio**: da CLI il default è proseguire senza. Da SDK con `enabled: true` si ferma, ma va verificato con un test che si rompe se il default cambia.
- **Formato dei blocchi non documentato**: `sandbox_violations` e `SandboxNetworkAccess` possono cambiare nome o forma a ogni versione della CLI.
- **Seatbelt non si annida**: ogni strumento che usa già `sandbox-exec` (SwiftPM, alcuni test runner) fallisce dentro.
- **CLI in Go** (`gh`, `terraform`, `kubectl`): TLS rotto dentro la sandbox per `trustd`.
- **MCP e hook fuori**: un Server MCP stdio o un hook di un Plugin gira con tutti i permessi dell'utente anche a Sandbox accesa ([#184](https://github.com/mgiuditta/bubo/issues/184)).
- **Automazioni senza nessuno davanti**: un dominio sconosciuto non può chiedere; se chiedesse, sarebbe lo stallo che la 19 vieta.
- **Disclaim + Seatbelt** mai provati insieme sullo stesso `claude`.
- **Checkout principale protetto**: in un worktree la `.git` comune è scrivibile tranne `hooks/` e `config`; `git merge` o `checkout` che toccano percorsi protetti (per esempio `.claude/skills`) falliscono con `unable to unlink old` [1].
- **Symlink** dentro il worktree che puntano fuori: il cancello deve risolvere il percorso reale, non quello scritto.
- **Terminale e server della 15**: sono processi dell'utente, non dell'agente. Restano fuori, e l'utente deve saperlo.

## Mappa

Architettura comune in [INDEX.md](INDEX.md). Si appoggia sul ponte agente ([#66](https://github.com/mgiuditta/bubo/issues/66)) con il disclaim (ADR 0005), sulle Sessioni in worktree e sullo script di setup (01), sulle Richieste, sulle Regole e sul Livello di rischio (05), sulle Automazioni e sul resoconto dei dinieghi (19), sulla finestra Plugin (20) e sulle soglie di prestazione (25, [#186](https://github.com/mgiuditta/bubo/issues/186)).

### Meccanismo e perimetro (deciso)

Fonte: [#185](https://github.com/mgiuditta/bubo/issues/185).

- **Due strati**:
  - **Sandbox integrata di Claude Code** per Bash e figli, accesa con `Options.sandbox` a ogni avvio della Conversazione dell'agente.
  - **Cancello delle scritture di Bubo** (05): con la Sandbox accesa nega Edit, Write e NotebookEdit fuori dal worktree e dai percorsi ammessi, **anche in Modalità autonoma**.
- **`failIfUnavailable: true`**: se la Sandbox non parte, la Sessione non parte e lo dice in 1 riga. Mai un comando senza sandbox quando l'indicatore dice "accesa".
- **`srt` attorno a tutto `claude`**: fuori dalla v1, si riconsidera quando esce dalla beta.
- **Terminale e server della 15**: fuori dalla Sandbox (processi dell'utente).

### Plugin, Server MCP e hook (deciso)

- Restano tutti attivi. Gli hook sono codice dell'utente e girano fuori.
- Con la Sandbox accesa la Modalità autonoma **non** approva da sola gli strumenti dei Server MCP locali (stdio): serve una Regola di permesso esplicita, altrimenti diniego. In un'Esecuzione il diniego finisce nel resoconto.
- La finestra Plugin marca ogni Plugin con codice eseguibile come "gira fuori dalla sandbox" ([#184](https://github.com/mgiuditta/bubo/issues/184)).

### Configurazione (deciso)

- **Dove vive**: percorsi e domini ammessi nello store di Bubo, per Progetto. Passano a ogni Sessione in un solo `Options.sandbox`: l'SDK lo mette al posto di tutto il `sandbox` di `Options.settings` (merge superficiale), nel livello `--settings`, dove valgono anche `strictAllowlist` e `credentials`. Bubo **non** scrive `.claude/settings*.json` per la Sandbox.
- **Limite dichiarato**: le Regole di permesso `Edit(...)` e `WebFetch(domain:…)` scritte nei settings allargano anche la Sandbox. Le Impostazioni del Progetto le elencano sotto "Regole di Claude Code che allargano la Sandbox", lette con `listPermissionRules()` (05).
- **Preset fisso**, sempre presente con la Sandbox accesa, non modificabile:
  - scrittura in `DARWIN_USER_TEMP_DIR`, `DARWIN_USER_CACHE_DIR` e nelle cache dei pacchetti, ai percorsi predefiniti su macOS ([#217](https://github.com/mgiuditta/bubo/issues/217)): `~/.npm` (npm), `~/Library/pnpm/store` e `~/Library/Caches/pnpm` (pnpm), `~/Library/Caches/Yarn` (Yarn 1), `~/.yarn/berry` (Yarn 2+), `~/.bun/install/cache` (Bun), `~/.cargo/registry`, `~/.cargo/git` e i file `.package-cache`, `.package-cache-mutate`, `.global-cache`, `.global-cache-journal` di `~/.cargo` (Cargo), `~/Library/Caches/pip` (pip), `~/.cache/uv` (uv), `~/go/pkg/mod` e `~/Library/Caches/go-build` (Go). Solo le cache, mai la cartella intera di uno strumento: `~/.cargo/bin`, `~/.bun/bin`, `~/go/bin` e le impostazioni degli strumenti contengono codice che gira fuori. Fuori dal preset: DerivedData di Xcode (nota di sistema), Gradle e Maven (la JVM non passa dal proxy, il wrapper di Gradle scarica da `github.com`), Homebrew (scrive nel prefisso dei programmi);
  - `allowLocalBinding: true`;
  - domini dei registri di pacchetti: `registry.npmjs.org`, `registry.yarnpkg.com` (Yarn), `pypi.org`, `files.pythonhosted.org`, `crates.io`, `index.crates.io`, `static.crates.io`, `rubygems.org`, `index.rubygems.org`. **Non** `github.com`.
  - Limiti verificati con `sandbox-runtime` 0.0.78 (lo stesso motore, 2026-10-01): pip ≥ 24.2 (truststore), pnpm 12 e i CLI in Go verificano il TLS con `trustd` e non raggiungono i registri in sandbox (`OSStatus -26276`), come `gh`; Yarn 2+ ignora `HTTPS_PROXY` e va in rete solo con `YARN_HTTPS_PROXY`. Senza rete restano utili le cache: vale il ritentativo fuori sandbox. La cartella che contiene la cache deve già esistere (`~/.cache` per uv, `~/.bun/install` per Bun): la crea il primo uso dello strumento fuori sandbox.
- **Swift**: nei Progetti con `Package.swift` una nota di sistema dice all'agente di usare `swift build --disable-sandbox` (e `swift test --disable-sandbox`).
- **Credenziali**: letture libere, ma `sandbox.credentials` nega `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.netrc` e le variabili d'ambiente con token.

### Uscite dalla Sandbox (deciso)

- **Sessione interattiva**: `allowUnsandboxedCommands: true`. Il ritentativo con `dangerouslyDisableSandbox` è una Richiesta di permesso marcata "fuori dalla sandbox", **mai** coperta dalla Modalità autonoma.
- **Esecuzione**: `allowUnsandboxedCommands: false`, diniego.
- **`gh`** in `excludedCommands`: gira fuori e passa da Richiesta o Regola. In un'Esecuzione serve una Regola dell'Automazione. `enableWeakerNetworkIsolation` resta spento (aprirebbe `trustd`).
- **Dipendenze remote SwiftPM**: se il Progetto ha `Package.resolved`, Bubo esegue `swift package resolve` **fuori** dalla Sandbox alla creazione del worktree, prima dell'agente. Altrimenti vale il ritentativo fuori sandbox.

### Rete (deciso)

- **Sessione**: dominio sconosciuto → `canUseTool("SandboxNetworkAccess", {host})` → Richiesta di permesso "Rete: host", **livello 3**, risposte solite (No, Solo ora, Per questa Sessione, Sempre in questo Progetto). Serve `strictAllowlist: false`.
- **Esecuzione**: `strictAllowlist: true` via `Options.settings`; diniego subito e riga nel resoconto con "Consenti per questa Automazione".

### Cosa vede l'utente (deciso)

- **Indicatore "Sandbox"** acceso o spento, sempre visibile nella Sessione.
- **Blocco**: una riga nel blocco del comando, "Bloccato dalla sandbox: scrittura in `~/x`" oppure "Bloccato dalla sandbox: rete verso `host`", con [Consenti in questo Progetto]. Lo stesso testo arriva all'agente.
- **Da dove si leggono i blocchi**: non da `permission_denials`. Il ponte li legge dal blocco `sandbox_violations` nel risultato del comando. Formato e nome `SandboxNetworkAccess` non sono documentati: un test del ponte si rompe se cambiano. Senza blocco il comando resta un errore generico.

### Default (deciso)

- **Spenta di default nelle Sessioni**; interruttore per Progetto.
- **Accesa di default nelle Automazioni** (mappa [#178](https://github.com/mgiuditta/bubo/issues/178)).
- La Modalità autonoma **non** richiede la Sandbox. Quando l'utente la accende e la Sandbox è spenta, Bubo propone anche la Sandbox con un solo interruttore.

### Dettagli di costruzione

Scelti scrivendo la spec, non nelle issue. Si possono cambiare senza toccare le decisioni sopra.

- **Interruttore per Progetto** in Impostazioni del Progetto › Sandbox, con l'elenco dei percorsi e dei domini ammessi (rimovibili), il preset in sola lettura e le Regole di Claude Code che allargano la Sandbox. L'indicatore della Sessione apre questa pagina.
- **Quando vale un cambio**: `Options.sandbox` si fissa all'avvio del processo `claude`, e oggi ogni turno della Sessione avvia il suo. Accendere, spegnere o aggiungere un percorso vale dal turno successivo; con un turno in corso l'indicatore dice "accesa/spenta dal prossimo turno" ([#214](https://github.com/mgiuditta/bubo/issues/214)). Se la Sessione terrà un processo vivo tra i turni, torna "Riavvia per applicare", che chiude e riprende con `resume` (~0,5 s, [#186](https://github.com/mgiuditta/bubo/issues/186)). I domini si applicano subito: la risposta alla Richiesta "Rete: host" porta anche una regola `WebFetch(domain:host)` di sessione in `updatedPermissions`.
- **"Sempre in questo Progetto"** su una Richiesta "Rete: host" e **[Consenti in questo Progetto]** su un blocco salvano il dominio o il percorso nello store di Bubo, mai nei settings. Percorso aggiunto = la cartella esatta del blocco, mai un genitore.
- **Cancello delle scritture** come hook `PreToolUse` del ponte (come `UnattendedGate` della 19): risolve il percorso reale (symlink compresi) e nega fuori da worktree, percorsi del preset e percorsi ammessi. Il messaggio di diniego è la stessa riga "Bloccato dalla sandbox: scrittura in …".
- **Server MCP stdio** in Modalità autonoma: `setMcpPermissionModeOverride` funziona solo in streaming input, mentre il ponte apre un `query()` con prompt stringa a ogni turno (preflight di [#215](https://github.com/mgiuditta/bubo/issues/215)). Il `SandboxGate` restituisce quindi `ask` per ogni `mcp__<server>__*` di un server stdio (trasporto da `mcpServerStatus().config`; se non si sa, come stdio), così le chiamate vanno alla Richiesta (Sessione) o al diniego (Esecuzione). Un `ask` dell'hook vince sulle Regole allow nella CLI 2.1.286: anche una Regola esplicita porta alla Richiesta.
- **`autoAllowBashIfSandboxed`** resta `true` (meno Richieste, come Cursor). I livelli 4–5 del `RiskClassifier` (05) chiedono comunque: l'hook della Sandbox restituisce `ask` per loro in una Sessione. Il livello lo dà Bubo: l'hook lo chiede con l'evento `risk` e senza risposta lo considera 4–5. Un `ask` dell'hook non passa mai dal classificatore della Modalità autonoma (CLI 2.1.286).
- **Modalità autonoma**: interruttore per Sessione, solo nel worktree della Sessione, dal prossimo turno. Il ponte passa sempre `permissionMode` esplicito alle Sessioni: `auto` accesa, `default` spenta (contraddizione 3 di [#330](https://github.com/mgiuditta/bubo/issues/330)).
- **Ritentativo fuori sandbox**: l'hook restituisce `ask` per ogni Bash con `dangerouslyDisableSandbox: true`. La Richiesta offre solo No e Solo ora, con il segno "fuori dalla sandbox".
- **Variabili con token negate**: nomi che finiscono in `_TOKEN`, `_API_KEY`, `_SECRET`, `_PASSWORD` più `AWS_*`, calcolati dall'ambiente al lancio. L'API key di Bubo non è nell'ambiente dei comandi (INDEX, ponte agente).
- **Xcode**: nei Progetti con `.xcodeproj` o `.xcworkspace` la stessa nota di sistema chiede `-derivedDataPath .build/DerivedData`, perché `~/Library/Developer/Xcode/DerivedData` non è nel preset.
- **`swift package resolve`** alla creazione del worktree gira dallo script di setup di 01 ([#70](https://github.com/mgiuditta/bubo/issues/70)), con disclaim e tetto di 120 s. Se fallisce, la Sessione parte comunque e mostra una riga con l'errore.
- **Blocchi** ([#216](https://github.com/mgiuditta/bubo/issues/216)): il ponte li legge negli hook `PostToolUse`/`PostToolUseFailure` di Bash, dall'ultimo `<sandbox_violations>` dell'output (righe di Seatbelt `proc(pid) deny(1) file-write-create /percorso` e del proxy `deny network-outbound host:porta (motivo)`), e restituisce le righe "Bloccato dalla sandbox: …" all'agente come `additionalContext`. La riga nella Sessione mostra gli ultimi blocchi del turno; [Consenti in questo Progetto] solo per scritture (la cartella del file, mai la radice, una cartella di primo livello o la home) e per host semplici; le letture negate (credenziali) non si consentono.
- **Rete: host in Modalità autonoma**: la CLI fa decidere `SandboxNetworkAccess` al suo classificatore, quindi la Richiesta compare solo a Modalità autonoma spenta. "Solo ora" vale comunque per il resto del turno: la CLI, approvato un host, lo ammette per tutta la vita del processo `claude` (`addSessionAllowedHost`).
- **Regole che allargano la Sandbox**: `listPermissionRules()` esiste a runtime ma non in `sdk.d.ts` 0.3.286; il ponte lo chiama con un tipo locale e un test si rompe se l'SDK lo toglie.
- **Sandbox che non parte**: nella Sessione "Sandbox non disponibile: <motivo>. La Sessione non è partita." con [Riprova]. In un'Esecuzione l'esito è **Saltata (sandbox non disponibile)** con notifica.
- **Automazioni**: interruttore "Sandbox" nella scheda dell'Automazione, acceso di default qualunque sia l'impostazione del Progetto. Un'Esecuzione usa i percorsi e i domini del Progetto più quelli "in questa Automazione".
- **Tooltip dell'indicatore**: percorsi scrivibili, domini ammessi e la riga "Il terminale e i server non sono in Sandbox".

### Moduli

Architettura comune in [INDEX.md](INDEX.md). Moduli nuovi:

- `Sandbox/SandboxPolicy`: codice puro. Da preset, store del Progetto, eventuali voci dell'Automazione e tipo di Sessione (interattiva o Esecuzione) produce un solo `Options.sandbox` (preset, `strictAllowlist`, `credentials`, `excludedCommands`) e la nota di sistema (Swift, Xcode). `Options.settings` non porta chiavi `sandbox`.
- `Sandbox/SandboxStore`: interruttore, percorsi e domini ammessi per Progetto; voci "in questa Automazione" accanto ad `AutomationStore` (19).
- `Sandbox/SandboxGate`: hook `PreToolUse` nel ponte. Cancello delle scritture di Edit, Write e NotebookEdit, `ask` sui ritentativi `dangerouslyDisableSandbox`, sui livelli 4–5 e sugli strumenti dei Server MCP stdio in Modalità autonoma.
- `Sandbox/ViolationParser`: legge `sandbox_violations` dal risultato del comando e produce un `SandboxBlock` (scrittura con percorso, rete con host). Test che si rompe se il formato cambia.
- `HUD/SandboxIndicator` e `HUD/SandboxBlockRow`: indicatore nella Sessione, riga del blocco con [Consenti in questo Progetto].
- `Settings/ProjectSandboxPane`: pagina Sandbox delle Impostazioni del Progetto.
- Estensioni: `Agent/AgentBridge` (passa `sandbox` e `settings`, errore di avvio della sandbox → motivo in 1 riga), `Sessions/WorktreeManager` (`swift package resolve` fuori sandbox), `Permissions/RequestCenter` e `HUD/PermissionView` (Richiesta "Rete: host" e segno "fuori dalla sandbox"), `Automations/ExecutionRunner` e `HUD/DenialReport` (blocchi della Sandbox nel resoconto, esito Saltata per sandbox non disponibile).
- Riuso: `Permissions/RiskClassifier` e `RuleStore` (05), `Automations/UnattendedGate` (19), `Agent/ProcessSpawner` con disclaim (ADR 0005), finestra Plugin (20).

### Flusso

1. **Avvio della Conversazione**: `SandboxStore` dice "accesa" → `SandboxPolicy` costruisce le opzioni → `AgentBridge` avvia `claude` con disclaim, `Options.sandbox` e `Options.settings` → la sandbox non parte? La Sessione non parte, 1 riga col motivo.
2. **Scrittura con Edit/Write**: `SandboxGate` risolve il percorso → dentro: prosegue verso Regole e modalità (05) → fuori: diniego con la riga "Bloccato dalla sandbox".
3. **Comando Bash**: gira in Seatbelt senza Richiesta (tranne livelli 4–5 e Regole ask) → blocco? `ViolationParser` → riga nel blocco del comando + testo all'agente.
4. **Rete verso un host nuovo**: Sessione → Richiesta "Rete: host" (livello 3) → risposta → eventuale dominio nello store. Esecuzione → diniego subito → riga nel resoconto.
5. **Ritentativo fuori sandbox**: Sessione → Richiesta "fuori dalla sandbox" (No, Solo ora). Esecuzione → diniego.
6. **[Consenti in questo Progetto]** o "Consenti per questa Automazione" → voce nello store → vale dalla prossima Conversazione ("Riavvia per applicare" nella Sessione aperta).

### Casi limite

- **Sandbox accesa in un Progetto non git**: si scrive solo nella cartella del Progetto e nei percorsi ammessi; nessun worktree da proteggere.
- **Symlink nel worktree verso fuori**: il cancello nega (percorso reale fuori).
- **Regola `Edit(~/altro/**)` nei settings**: allarga la Sandbox di Claude Code, ma il cancello di Bubo nega comunque le scritture di Edit e Write fuori dai percorsi ammessi nello store. I comandi Bash invece passano: la pagina Sandbox lo mostra tra le Regole che la allargano.
- **`gh` in un'Esecuzione senza Regola dell'Automazione**: diniego nel resoconto con "Consenti per questa Automazione".
- **`swift build` senza `--disable-sandbox`**: il blocco arriva all'agente come riga; la nota di sistema lo previene.
- **`Package.resolved` con dipendenze nuove aggiunte dall'agente**: il resolve iniziale non basta; vale il ritentativo fuori sandbox (Sessione) o il diniego (Esecuzione).
- **`git merge` o `checkout` su percorsi protetti** (`.claude/`): fallisce con `unable to unlink old`; la riga lo spiega col percorso.
- **Subagent**: condividono la sandbox della Sessione e passano dallo stesso cancello; la riga del blocco porta il nome dell'agente (19).
- **Server MCP stdio senza Regola** in Modalità autonoma: Richiesta in Sessione, diniego nel resoconto in Esecuzione.
- **Sandbox spenta a Sessione aperta**: l'indicatore diventa "spenta (dalla prossima Conversazione)" finché non si riavvia; mai "spenta" mentre i comandi girano ancora in sandbox, né il contrario.
- **Formato di `sandbox_violations` cambiato** con una CLI nuova: il comando resta un errore generico, il test del ponte fallisce in CI.
- **CLI `claude` troppo vecchia** per `Options.sandbox` o `failIfUnavailable`: la Sessione con Sandbox non parte e chiede di aggiornare `claude` (versione minima della 27).

### Test

- `SandboxPolicy`: tabella Progetto × Automazione × tipo di Sessione → opzioni attese (preset sempre presente, `strictAllowlist` solo nelle Esecuzioni, `allowUnsandboxedCommands` falso nelle Esecuzioni, nessun `github.com`, `gh` in `excludedCommands`).
- **End-to-end sul ponte** con Sandbox accesa, in un worktree finto, anche in Modalità autonoma: Bash, Edit, Write e NotebookEdit provano a scrivere in `~/fuori`, in `/tmp/altro` e via symlink → 0 file creati fuori; ogni tentativo produce la riga col percorso.
- **Rete**: `curl` verso un dominio fuori lista → 0 connessioni riuscite (Sessione: Richiesta "Rete: host"; Esecuzione: diniego nel resoconto).
- **Credenziali**: `cat ~/.ssh/id_*`, `cat ~/.aws/credentials`, `echo $GH_TOKEN` in sandbox → 0 contenuti letti.
- **Strumenti senza configurazione** su un Progetto finto: `npm install`, `swift build --disable-sandbox` (senza dipendenze remote o già risolte), `xcodebuild -version`, `python3 -m http.server` + `curl localhost` → tutti OK.
- **Sandbox che non parte** (profilo forzato a fallire o CLI simulata): la Sessione non parte, 1 riga, 0 comandi eseguiti.
- **Esecuzione con Sandbox**: comando fuori lista, scrittura fuori, `gh`, MCP stdio → fine del turno senza attesa, un blocco per ciascuno nel resoconto con percorso o host; "Consenti per questa Automazione" → nella successiva, in un worktree nuovo, 0 blocchi per quella voce.
- **`ViolationParser`**: risultati di comando registrati dalla CLI 2.1.285 → blocchi attesi; un test fallisce se il blocco `sandbox_violations` sparisce o cambia forma.
- **Overhead**: 50 comandi `true` via ponte con Sandbox accesa e spenta, durata da `PreToolUse` a `PostToolUse` → differenza p50 ≤ 10 ms sul Mac di riferimento (target XCTest di prestazione, [#186](https://github.com/mgiuditta/bubo/issues/186)).
- **Disclaim + Sandbox** col lanciatore vero: `claude` avviato con disclaim e Sandbox accesa → blocchi di scrittura e rete come sopra; nessun permesso TCC di Bubo ereditato.
- **Nessun file scritto**: monitor su `.claude/settings*.json` e `~/.claude/settings.json` durante tutti i test → 0 scritture di Bubo per la Sandbox.
- Accessibilità: audit SwiftUI dell'indicatore, della riga del blocco e della pagina Sandbox.

### Ordine di costruzione

1. **Sandbox accesa in una Sessione**: `SandboxStore` (solo interruttore), `SandboxPolicy` con preset e credenziali, `AgentBridge` che passa `Options.sandbox`/`settings` con `failIfUnavailable`, errore di avvio in 1 riga, `HUD/SandboxIndicator`, interruttore nelle Impostazioni del Progetto, indicatore "dal prossimo turno". Finché mancava il passo 2, `autoAllowBashIfSandboxed: false` (ogni Bash passava dalle Richieste; dal passo 2 è `true`); finché mancava il 3, `strictAllowlist: true` (un host fuori lista era negato subito; dal passo 3, [#216](https://github.com/mgiuditta/bubo/issues/216), nelle Sessioni è `false`). Test di Bash che non scrive fuori, `curl` bloccato, credenziali negate, disclaim + Sandbox col lanciatore vero. Dipende dal ponte agente ([#66](https://github.com/mgiuditta/bubo/issues/66)) e da 01 ([#69](https://github.com/mgiuditta/bubo/issues/69)).
2. **Cancello delle scritture e uscite**: se manca ancora, l'interruttore della Modalità autonoma nella Sessione (solo in un worktree, livelli 4–5 chiedono comunque, come in [05](05-permessi.md)); `SandboxGate` (Edit, Write, NotebookEdit fuori negati anche in Modalità autonoma; livelli 4–5 in `ask`; ritentativo `dangerouslyDisableSandbox` come Richiesta "fuori dalla sandbox"; MCP stdio fuori dalla Modalità autonoma), proposta della Sandbox quando si accende la Modalità autonoma. Dipende da 1 e da 05 ([#78](https://github.com/mgiuditta/bubo/issues/78), [#79](https://github.com/mgiuditta/bubo/issues/79)).
3. **Blocchi spiegati e rete**: `ViolationParser`, `HUD/SandboxBlockRow` con [Consenti in questo Progetto], Richiesta "Rete: host" di livello 3 da `SandboxNetworkAccess`, percorsi e domini nello store, pagina Sandbox completa con le Regole di Claude Code che la allargano. Dipende da 2.
4. **Strumenti di sviluppo senza configurazione**: verifica del preset su `npm`, dev server e `xcodebuild -version`; nota di sistema per Swift e Xcode; `gh` in `excludedCommands`; `swift package resolve` fuori sandbox nello script di setup; test di overhead ≤ 10 ms. Dipende da 1 e da 01 ([#70](https://github.com/mgiuditta/bubo/issues/70)); il test di overhead dal target di prestazione della 25.
5. **Sandbox nelle Automazioni**: interruttore acceso di default nella scheda, `allowUnsandboxedCommands: false`, `strictAllowlist: true`, blocchi e `gh` nel resoconto con "Consenti per questa Automazione", voci per Automazione nello store, esito Saltata (sandbox non disponibile). Dipende da 3 e da 19 ([#168](https://github.com/mgiuditta/bubo/issues/168), [#169](https://github.com/mgiuditta/bubo/issues/169)).

## Specifica "migliore di"

Miglior concorrente: **Cursor** (Seatbelt + proxy, domini dei registri predefiniti, `.git/hooks` e `.git/config` protetti, accesa in Auto-review), che però lascia fuori le scritture degli strumenti incorporati, non pubblica il costo e ha dovuto rifare la spiegazione dei blocchi. Claude Code ha lo stesso motore ma spento, e da CLI prosegue senza sandbox se non parte.
Bubo li supera così:

1. **Scritture chiuse davvero**: con la Sandbox accesa, **0 scritture** fuori dal worktree e dai percorsi ammessi da Bash, Edit, Write e NotebookEdit, anche in Modalità autonoma (test end-to-end).
2. **Rete chiusa**: **0 connessioni** verso domini non ammessi dai comandi in Sandbox (test `curl` fuori lista).
3. **Automazioni senza stalli**: Esecuzione con Sandbox **0 stalli**; **100%** dei blocchi nel resoconto con percorso o host e "Consenti per questa Automazione" in **1 clic**.
4. **Pronta all'uso**: `npm install`, `swift build` (senza dipendenze remote o già risolte), `xcodebuild -version` e un dev server su localhost funzionano con **0 passi** di configurazione.
5. **Mai senza protezione di nascosto**: Sandbox che non parte → Sessione non parte, motivo in **1 riga**, **0 comandi** eseguiti senza sandbox.
6. **Costo misurato**: overhead **≤ 10 ms** per comando in Sandbox sul Mac di riferimento (misurato ~5,5 ms); nessun concorrente pubblica il suo.
7. **Sempre chiaro**: indicatore visibile nel **100%** delle Sessioni; ogni blocco spiegato in **1 riga** con percorso o host.
8. **Credenziali fuori portata**: **0 letture** riuscite di `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.netrc` e delle variabili con token dai comandi in Sandbox.
9. **File dell'utente intatti**: **0 scritture** di Bubo in `.claude/settings*.json` o `~/.claude/settings.json` per configurare la Sandbox.

## Fonti

1. Claude Code, "Configure the sandboxed Bash tool" — https://code.claude.com/docs/en/sandboxing
2. Claude Code, "Choose a sandbox environment" — https://code.claude.com/docs/en/sandbox-environments
3. Claude Code, "Settings reference" (`sandbox.*`, `permissions.blockReadsOutsideWorkingDirectories`) — https://code.claude.com/docs/en/settings-reference
4. `@anthropic-ai/claude-agent-sdk` 0.3.285, `sdk.d.ts` (`Options.sandbox`, `SandboxSettingsSchema`, `spawnClaudeCodeProcess`) e `sdk-tools.d.ts` (`dangerouslyDisableSandbox`) — https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk
5. `anthropics/sandbox-runtime`, README (0.0.78) — https://github.com/anthropics/sandbox-runtime
6. Agent SDK, "Securely deploying AI agents" — https://code.claude.com/docs/en/agent-sdk/secure-deployment
7. OpenAI Codex, "Agent approvals & security" — https://learn.chatgpt.com/docs/agent-approvals-security
8. Cursor, "Implementing a secure sandbox for local agents" (2026-02-18) — https://cursor.com/blog/agent-sandboxing
9. `apple/container`, README e release 1.5.0 — https://github.com/apple/container
10. `apple/containerization`, README — https://github.com/apple/containerization
11. Apple Developer, Virtualization — https://developer.apple.com/documentation/virtualization ; entitlement `com.apple.security.virtualization` — https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.virtualization
12. Apple, contratti di licenza software di macOS (copie in VM) — https://www.apple.com/legal/sla/
13. Claude Desktop, configurazione (`requireCoworkFullVmSandbox`, `coworkEgressAllowedHosts`) — https://claude.com/docs/third-party/claude-desktop/configuration
14. Claude Code, "Use Claude Code Desktop" — https://code.claude.com/docs/en/desktop
15. `openai/codex` 0.159.2, `codex-rs/network-proxy/README.md` e `codex-rs/sandboxing/src/seatbelt_*.sbpl` — https://github.com/openai/codex
16. Cursor, "Run Modes" (Sandboxing, `sandbox.json`, domini predefiniti) — https://cursor.com/docs/agent/security/run-modes
17. Conductor, "Security and permissions" — https://www.conductor.build/docs/reference/security-and-permissions
18. Pagine man di macOS 26.7: `sandbox-exec(1)`, `sandbox_init(3)`; esperimenti locali del 2026-09-30 (`claude -p` 2.1.285 con `--settings`) e verifiche di [#185](https://github.com/mgiuditta/bubo/issues/185) (Xcode 26.6)
