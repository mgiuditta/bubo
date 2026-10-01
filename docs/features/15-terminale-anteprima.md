# 15 — Terminale, editor e Anteprima del server

Ticket: [#127](https://github.com/mgiuditta/bubo/issues/127) (ricerca), [#133](https://github.com/mgiuditta/bubo/issues/133) (cosa entra in v1), [#139](https://github.com/mgiuditta/bubo/issues/139) (l'agente vede e pilota l'Anteprima), [#140](https://github.com/mgiuditta/bubo/issues/140) (scorciatoie). Mappa: [#125](https://github.com/mgiuditta/bubo/issues/125).
Base: [01 — Sessioni in worktree](01-sessioni-worktree.md) (worktree, 10 porte per Sessione), [ADR 0005](../adr/0005-claude-senza-i-permessi-tcc-di-bubo.md) (disclaim, esteso a ogni processo avviato da Bubo), [09 — Sistema](09-sistema.md) (`Agent/ProcessSpawner`), [05 — Permessi](05-permessi.md) (Livello di rischio).
Ricerca del 2026-09-30 su macOS 26.7 (25G229), VS Code 1.139.1, Claude desktop 2.16120.0, SwiftTerm 1.20.0. Le citazioni restano in inglese come nell'originale. Le misure A–E sono state fatte su questo Mac con piccoli programmi C nella cartella temporanea, senza installare nulla.

> **Nota sulla ricerca.** È scritta prima delle decisioni e in cinque punti è superata. L'Anteprima **non** si propone da sola quando la porta compare: c'è solo un'etichetta `localhost:NNNN` e si apre con un clic ([#133](https://github.com/mgiuditta/bubo/issues/133)). Microfono e fotocamera sono negati **senza** eccezione per Sessione in v1 ([#133](https://github.com/mgiuditta/bubo/issues/133)). L'agente pilota l'Anteprima, ma **senza** verifica forzata tipo `autoVerify` ([#139](https://github.com/mgiuditta/bubo/issues/139)). L'Anteprima di una Sessione **non** si chiude quando non è visibile, perché l'agente la usa anche a pannello chiuso ([#139](https://github.com/mgiuditta/bubo/issues/139)). Le variabili delle porte sono `PORT` e `BUBO_PORT` (prima porta, da 01) più `BUBO_PORTS` (l'intervallo, da [#133](https://github.com/mgiuditta/bubo/issues/133)). Browser generico ed editor vero sono fuori portata. Valgono la Mappa e la Specifica qui sotto.

In sintesi: tutti i concorrenti hanno terminale e anteprima, ma **nessuno isola il terminale dai permessi dell'app**. VS Code, Cursor e la desktop app di Claude usano `node-pty` senza disclaim (misura D): ogni comando nel loro terminale lavora con i permessi TCC dell'app. In Bubo il terminale vive dentro la Sessione, parte nel suo worktree e ogni processo (shell, dev server, CLI dell'editor) parte con il disclaim, tramite un lanciatore `setsid` + `TIOCSCTTY` nel bundle; **SwiftTerm** fa solo da vista, su un PTY di Bubo. I server si trovano **senza `lsof`**: `libproc` legge i socket in ascolto in 0,5–3 ms, a eventi e mai a riposo, e li attribuisce alla Sessione dalla cartella corrente o dalle sue porte. L'**Anteprima** è una `WebPage` per Sessione, solo `localhost`, con cookie propri; l'agente la vede e la pilota con strumenti MCP del ponte, sulla stessa vista e con gli stessi cookie dell'utente, e se l'utente tocca vince lui. Niente editor vero: un visore in sola lettura e "Apri nell'editor" alla riga giusta via CLI (`code -g`, `cursor -g`, `zed f:r:c`, `xed -l`), mai con `vscode://`.

## Ricerca

### Come lo fanno i concorrenti

| Prodotto | Terminale | Anteprima | Rilevamento porta | Apri nell'editor |
|---|---|---|---|---|
| **Claude desktop (scheda Code)** | Pannello con schede, ⌃\`; "opens in your session's working directory and shares the same environment as Claude"; solo Sessioni locali; staccabile in una finestra [1]. `node-pty` senza disclaim (misura D). | Pannello Browser a schede (dentro Electron). L'agente verifica da solo dopo ogni modifica: "takes screenshots, inspects the DOM, clicks elements, fills forms" (`autoVerify`, attivo di default). Avvio e arresto dei server dal menu; "Persist sessions" per cookie e localStorage; profilo pulito, separato dal browser dell'utente. Apre anche HTML, PDF, immagini e video del Progetto, e siti esterni con permesso [1]. | Dichiarato, non rilevato: `.claude/launch.json` con `runtimeExecutable`, `runtimeArgs`, `port` (default 3000), `cwd`, `env`, `autoPort`, `url`. Con `autoPort: true` sceglie una porta libera e la passa in `PORT`; senza valore chiede all'utente e salva la risposta [1]. | Menu contestuale **Open in** "an installed editor such as VS Code, Cursor, or Zed"; la doc non parla di riga [1]. Pannello file con piccole modifiche e Salva [1]. |
| **Conductor** | Terminale per workspace; "Big Terminal Mode"; "Claude can now read your terminal" e `@terminal` in chat [3]; scrollback limitato a 10 MB di default dalla 0.63 [4]. | "browser preview" dalla 0.62 [3]; più Preview URL con nome dalla 0.63; anteprime servite su `localhost` e non su `127.0.0.1` "so cookie-based auth flows work" [4]. | Nessun rilevamento: 10 porte fisse da `CONDUCTOR_PORT` [2]. "Auto port forwarding" dalla 0.83 [3]. | **Open In** o ⌘O apre la cartella del workspace in Cursor o VS Code, e mette a fuoco la finestra se è già aperta [5]. Niente riga. |
| **Superset** | xterm.js + `node-pty` in un processo `pty-daemon` separato; `@xterm/headless` per ripristinare lo schermo [7]. | Browser in-app di Electron; "Open local web servers in the in-app browser or externally from the port action" [6]. | Scoperta: `lsof -p <pid> -iTCP -sTCP:LISTEN` sui processi del workspace ogni **2,5 s**, 30 s se il terminale è inattivo da 60 s, più una scansione dopo 500 ms quando l'output contiene "listening on", "Local: http://" e simili [7]. Etichette in `.superset/ports.json` [6]. Ha avuto un bug con decine di `lsof` al 100% di CPU [8]. | `open -a`/`open -b <bundle id>` per molti editor (VS Code, Cursor, Zed in tutti i canali, Xcode, JetBrains); conserva il suffisso `:riga:colonna` nei percorsi [9]. |
| **cmux** (nativo Swift/AppKit, ~27k stelle) | libghostty da un **fork** di Ghostty [10]. | Browser WebKit in split accanto al terminale, con un'API da script presa da agent-browser: l'agente legge l'albero di accessibilità, clicca, compila e valuta JS [10]. | La shell manda un "kick" al socket di cmux; cmux unisce i kick per 200 ms e fa una raffica di 6 scansioni `ps -t <tty>` + `lsof -p <pid>` per tutti i pannelli insieme [10]. Porte in ascolto nella barra laterale [10]. | — |
| **Cursor** | Terminale di VS Code (`node-pty`, senza disclaim, misura D). | Browser integrato ("a secure web view" pilotata da un server MCP): screenshot, click, console, rete; log del browser scritti su file che l'agente cerca con grep; stato persistente per workspace [11]. | L'agente "can detect running development servers and use the correct ports instead of starting duplicate servers" [11]. | È l'editor. |
| **Warp** | Terminale in Rust, oggi open source (AGPL; UI in MIT); modello del terminale derivato da `alacritty_terminal`; le shell nascono da un processo "terminal server" avviato all'inizio "to ensure that shell processes are created in as clean of a state as possible" (niente descrittori ereditati) [12]. | Non documentata. | — | — |
| **Zed** | `alacritty_terminal` (fork di Zed) disegnato con GPUI [13]. | Nessuna. | — | È l'editor; CLI `zed file:42:10` e schema `zed://file/…` [13]. |
| **Nimbalyst** | `ghostty-web` (libghostty-vt in WASM) dentro Electron [14]. | Non documentata. | — | Editor Monaco interno [14]. |

**Cosa ne esce.**

1. **L'anteprima vera è verificata dall'agente**: Claude desktop, Cursor e cmux danno all'agente screenshot, DOM, click e console della stessa vista che vede l'utente. Chi non lo fa (Conductor, Superset) offre solo una finestra sul server.
2. **Le porte si dichiarano o si cercano con `lsof`**. Claude desktop le dichiara (`launch.json`), Conductor le riserva, Superset e cmux lanciano `lsof` a intervalli o a eventi. Nessuno legge i socket direttamente dal kernel.
3. **"Apri nell'editor" apre la cartella, raramente la riga.** Solo Superset conserva `:riga:colonna`. Nessuno documenta Xcode alla riga.
4. **Nessuno isola il terminale dai permessi TCC dell'app** (vedi sotto). È il punto più forte per Bubo, perché è già una regola (ADR 0005).

### Il terminale eredita i permessi TCC di Bubo?

**Sì, se non si fa nulla.** Per TCC il processo responsabile di un figlio è l'app che l'ha avviato. La issue VS Code #307364 lo descrive bene: dal terminale integrato "macOS traces up the process tree and identifies VS Code as the responsible process"; se l'app non ha la chiave `NS…UsageDescription` giusta, la richiesta viene negata "silently" (tccd: "Policy disallows prompt for Sub:{com.microsoft.VSCode}"). Un maintainer propone "disclaiming tcc for the pty host process" [18]. Per Bubo vale il contrario ma con lo stesso meccanismo: un `sox` nel terminale registrerebbe con il Microfono di Bubo.

**Misura A — il disclaim vale anche per il terminale.** Un programma C avvia `/bin/zsh` con `posix_spawn`, con e senza `responsibility_spawnattrs_setdisclaim`, e ogni figlio stampa `responsibility_get_pid_responsible_for_pid(getpid())`. L'app padre in questo test è iTerm2 (pid 733), che fa la parte di Bubo.

| Processo nel terminale | Senza disclaim | Con disclaim |
|---|---|---|
| `zsh` | 733 (l'app) | se stesso |
| `/bin/sleep`, Python di Xcode (binari Apple) | 733 | lo `zsh` del terminale |
| `node`, un binario compilato a mano (non Apple) | 733 | **se stesso**, dal momento dell'`exec` |
| Sottoshell `( … )` | 733 | lo `zsh` finché non fa `exec` |

Quindi con il disclaim **nessun processo del terminale ha più Bubo come responsabile**. In più, un binario non Apple diventa responsabile di sé: se chiede un permesso, l'avviso porterà il suo nome (`node`), non "zsh" né "Bubo". Il comportamento con un vero avviso TCC (per esempio Documenti) non è stato provato, per non far comparire finestre sul Mac: resta nella prova a inizio costruzione già prevista dall'ADR 0005.

**Misura B — `posix_spawn` non basta per un terminale vero.** Con `POSIX_SPAWN_SETSID` e il PTY su 0/1/2 (con `adddup2` o con `addopen` del percorso del PTY), lo `zsh` parte ma **senza terminale di controllo** (`ps -o tty=` → `??`, `/dev/tty` non si apre): niente ⌃C al processo in primo piano, niente job control. Su macOS aprire un tty non lo rende di controllo; serve `ioctl(TIOCSCTTY)`, che `posix_spawn` non sa fare. Lo scrive anche Ghostty: "posix_spawn is used for Mac, but doesn't support the necessary features for tty setup" [16]. La soluzione provata: Bubo avvia con disclaim un **lanciatore di 10 righe** (nel bundle) che fa `setsid()`, `ioctl(0, TIOCSCTTY, 0)` ed `execv` della shell. Risultato: `ctty=ttys002`, `/dev/tty` ok, e lo `zsh` resta responsabile di sé.

**Misura D — chi lo fa oggi.** `nm -u` sul modulo `pty.node` di Cursor e della desktop app di Claude (2.16120.0), e `strings` su quello di VS Code 1.139.1: `posix_spawn` sì, `responsibility_spawnattrs_setdisclaim` no. I loro terminali lavorano con i permessi dell'app.

**Rete locale.** TN3179: il loopback non è "rete locale" (una rete locale è quella di un'interfaccia "broadcast-capable" come Wi-Fi ed Ethernet), quindi un'Anteprima su `localhost` non chiede il permesso Rete locale. Ma "if your app spawns a helper tool and the helper tool performs a local network operation, macOS considers the app to be the responsible code"; sono invece esenti i "command-line tools run from Terminal or over SSH, including any child processes they spawn" [20]. Anche qui il disclaim evita che un `ssh 192.168.1.10` nel terminale di Bubo faccia chiedere il permesso a Bubo (non misurato).

### Librerie per il terminale in Swift

| Libreria | Cosa dà | Licenza | Stato | Creazione del processo |
|---|---|---|---|---|
| **SwiftTerm** (Miguel de Icaza) | Motore VT/xterm + `TerminalView` AppKit, collegabile a "any source" via `TerminalViewDelegate`; ricerca, selezione, link con ⌘-clic, Sixel, Kitty e iTerm2 per le immagini, BiDi, OSC 133 (1.17), renderer Metal facoltativo; usato da CodeEdit, Secure ShellFish, La Terminal [15]. | MIT | v1.20.0 del 2026-08-18: "one last release before we land the breaking changes" [15]. | `LocalProcess` usa `forkpty` + `execve` [15]: **niente disclaim**. Si usa `TerminalView` con un PTY nostro. |
| **libghostty-vt** (Ghostty) | Solo analisi delle sequenze e stato del terminale, C e Zig, zero dipendenze; niente disegno né input [16]. | MIT | "extremely stable … but the API signatures are still in flux"; nessuna versione con tag [16]. | Nessuna: la fa l'app. Il disegno va scritto da zero (Metal). |
| **libghostty completo / GhosttyKit** | Terminale completo con Metal, quello dell'app Ghostty. | MIT | `ghostty.h` è l'API interna: "The only consumer of this API is the macOS app … not designed for external use" [16]. cmux lo usa tramite un proprio fork [10]; esistono pacchetti SPM di terzi [17]. | `src/Command.zig` con `fork()` + `execve` [16]: il disclaim richiede un fork di Ghostty o il lanciatore come comando. |
| **alacritty_terminal** | Motore VT in Rust (Zed, Warp) [12][13]. | Apache-2.0 | Maturo. | Da ponte Rust→Swift: costo di build alto per Bubo. |
| **xterm.js in `WKWebView`** | La scelta di VS Code, Superset e (probabilmente) degli altri Electron. | MIT | Maturo. | Il PTY resta nostro; ma un terminale in una pagina web va contro "nativo" e aggiunge un processo WebContent per terminale. |

Nessuno pubblica numeri di velocità confrontabili: SwiftTerm scrive "Seems pretty fast to me" e ha uno script di benchmark PTY nel repo [15]; Superset si vanta di "Ghostty-speed scrolling" senza cifre. Le prestazioni vanno misurate su Bubo.

**Conseguenza per Bubo.** SwiftTerm `TerminalView` + `Agent/ProcessSpawner` (lo stesso che avvia `claude`) + il lanciatore `setsid`/`TIOCSCTTY`. Le letture dal PTY con `DispatchIO`, come fa già SwiftTerm [15]. `POSIX_SPAWN_CLOEXEC_DEFAULT` sostituisce il "terminal server" di Warp: nessun descrittore di Bubo passa alla shell. La shell parte come login interattiva nella cartella del worktree, con lo stesso ambiente della Conversazione dell'agente, come fa Claude desktop [1]. Se un giorno libghostty-vt avrà un'API stabile, si può sostituire il motore dietro la stessa vista.

### Come si trova la porta di un dev server

**Misura C — `libproc` contro `lsof`.** Un programma C percorre tutti i processi dell'utente con `proc_listpids`, `proc_pidinfo(PROC_PIDLISTFDS)` e `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)`, e tiene i socket TCP in stato `TSI_S_LISTEN`. Su 414 processi: **0,5–2,9 ms** per tutto, senza processi figli. `lsof -nP -iTCP -sTCP:LISTEN -a -u <uid>`: **36–43 ms** a chiamata, più un `fork`. Con `proc_pidinfo(PROC_PIDVNODEPATHINFO)` si legge anche la **cartella corrente** del processo: un `node` avviato con disclaim dentro una cartella finta di worktree è stato trovato con porta 47123 e `cwd` nel worktree.

Cosa ne segue:

- **Attribuzione alla Sessione senza albero dei processi.** Superset e cmux devono ricostruire l'albero (`ps`, `pidtree`) e gestire a parte i processi staccati [7][10]. Con la cartella corrente si attribuisce ogni server a quella Sessione il cui worktree contiene la `cwd`, anche se è stato lanciato dall'agente in background o si è staccato. Le 10 porte riservate alla Sessione (01) sono il secondo indizio: un ascolto su una di quelle è della Sessione anche con `cwd` altrove.
- **Quando guardare.** Non serve un polling fisso come Superset (2,5 s). Eventi utili: una riga di output con un'URL `localhost` (gli stessi pattern di Superset [7]), l'inizio e la fine di un comando nel terminale (OSC 133, supportato da SwiftTerm [15]), la fine di uno strumento Bash dell'agente (hook `PostToolUse` dal ponte). Dopo un evento, qualche scansione ravvicinata come la "raffica" di cmux [10]; a riposo nessuna.
- **Riuso di `.claude/launch.json`.** Se il Progetto ce l'ha già (lo crea Claude desktop [1]), Bubo può leggere comando, porta e `url` invece di indovinarli, e passare la porta della Sessione in `PORT` come fa `autoPort` [1].

### L'Anteprima in WebKit

- **API.** macOS 26 ha `WebView` per SwiftUI e `WebPage` (`@Observable`): `load`, `reload(fromOrigin:)`, `stopLoading()`, `isLoading`, `estimatedProgress`, `title`, `url`, `callJavaScript(_:arguments:in:contentWorld:)`, `navigations` come sequenza asincrona, `exported(as:)` per PDF e immagini, `isInspectable`, `customUserAgent`, `mediaType` [22]. `WebPage.Configuration` espone `userContentController` e `websiteDataStore` [22]. Il vecchio `WKWebView` resta disponibile per ciò che manca.
- **Console.** WebKit non ha un'API pubblica per leggere la console. Due strade: `isInspectable = true` (macOS 13.3+) apre la pagina nel Web Inspector di Safari, menu Sviluppo [23]; per mostrare errori e log in Bubo (e darli all'agente) serve uno script iniettato all'inizio del documento, nel mondo della pagina, che avvolge `console.*`, `window.onerror` e `unhandledrejection` e li manda a un gestore di messaggi. È la stessa idea di Cursor, che scrive i log del browser su file per l'agente [11].
- **Ricarica.** `reload(fromOrigin:)` a comando; la ricarica automatica la fa già il dev server (HMR). Utile invece ricaricare quando il server **torna** in ascolto dopo un riavvio (evento dal rilevamento porte).
- **Dimensioni dei dispositivi.** Non esiste un'API di emulazione: si ridimensiona la vista a larghezze note (telefono, tablet, desktop) e, se serve, si cambia `customUserAgent`. Il touch e il device pixel ratio non si simulano; per quelli resta il Simulatore o il Web Inspector.
- **Cookie per Sessione.** `WKWebsiteDataStore(forIdentifier:)` (macOS 14+) crea un archivio persistente per identificatore, "Use this method to get a data store for a profile" [24]. Con l'id della Sessione, due Sessioni sullo stesso `localhost` non si rubano il login. Claude desktop ha un solo "Persist sessions" per tutto [1].
- **`localhost`, non `127.0.0.1`.** Da macOS 14 ATS "no longer allows connections to IP addresses by default"; `NSAllowsLocalNetworking` riapre nomi non qualificati, `.local` e IP [21]. Conductor ha spostato l'anteprima su `localhost` perché i cookie di login funzionassero [4].
- **Microfono e fotocamera.** La pagina gira con i permessi di Bubo: se il Progetto chiama `getUserMedia`, userebbe il Microfono di Bubo. `WKUIDelegate` ha `webView(_:requestMediaCapturePermissionFor:initiatedByFrame:type:decisionHandler:)`, "If you don't implement this method … the system returns prompt" [25]; `WebPage` ha `setMicrophoneCaptureState(_:)` [22]. Per l'ADR 0005 la risposta è **negare**.
- **Link esterni.** La mappa esclude il browser generico: i link fuori da `localhost` si aprono nel browser di sistema (Claude desktop offre invece "Open in app" [1]).

### Aprire un file nell'editor alla riga giusta

| Editor | Comando | Via URL | Note |
|---|---|---|---|
| **VS Code** | `code -g <file>:<riga>[:<col>]` [19] | `vscode://file/<percorso>:<riga>:<col>` [19] | Con URL, `security.promptForLocalFileProtocolHandling` (default **true**): "a dialog will ask for confirmation whenever a local file or workspace is about to open through a protocol handler" [19]. |
| **Cursor** | `cursor -g …` (stessa CLI di VS Code, verificato con `--help`) | schema `cursor` registrato nell'Info.plist (verificato) | Fork di VS Code: stessa finestra di conferma da presumere. |
| **Zed** | `zed <file>:42:10` [13] | `zed://file/<percorso>` (gestito in `open_listener.rs`) [13] | La CLI parla con l'istanza aperta; `-a` aggiunge alla finestra attiva [13]. |
| **Xcode** | `xed -l <riga> <file>` (verificato con `--help`: "Select line <number> after opening file") | — | `xed` comunica con Xcode; se questo richieda il permesso Automazione per Bubo non è stato provato. |
| Altri | `open -b <bundle id> <file>` | — | Senza riga; è il fallback di Superset [9]. |

Cosa ne segue: la **CLI** apre alla riga senza finestre di conferma, ma è un processo figlio di Bubo e, se l'editor non è aperto, lo avvia come figlio. Va avviata con lo stesso disclaim del terminale, così l'editor non eredita i permessi di Bubo. Gli editor installati si trovano con `NSWorkspace` per bundle id (come fa Superset per i canali di Zed [9]), non cercando la CLI nel `PATH`, che per un'app avviata dal Dock è ridotto.

### Fatti che toccavano i confini, e come sono stati risolti

1. **Il disclaim serve anche al terminale, non solo a `claude`** (misure A e D, VS Code #307364). Risolto: l'ADR 0005 è stato esteso a ogni processo avviato da Bubo ([#133](https://github.com/mgiuditta/bubo/issues/133)).
2. **Il terminale richiede un lanciatore nel bundle** (`setsid` + `TIOCSCTTY` + `exec`, misura B). Risolto: entra nel bundle, firmato con l'app.
3. **La libreria è di fatto scelta**: SwiftTerm come vista con PTY di Bubo.
4. **L'agente che verifica l'anteprima è lo standard** (Claude desktop, Cursor, cmux). Risolto: l'agente vede e pilota l'Anteprima via MCP del ponte ([#139](https://github.com/mgiuditta/bubo/issues/139)).
5. **L'Anteprima usa i permessi di Bubo.** Risolto: microfono e fotocamera negati, solo `localhost` (un indirizzo LAN come il "Network:" di Vite farebbe chiedere a Bubo il permesso Rete locale [20]).
6. **`.claude/launch.json` esiste già** come formato di Claude desktop [1]. Risolto: Bubo lo legge e non ha un formato suo.

## Il meglio da battere

- **Anteprima**: Claude desktop (agente che verifica da solo, `launch.json`, `autoPort`, persistenza) [1]. Tutto dichiarato, un solo archivio di cookie, dentro Electron, strumenti presenti anche senza server.
- **Porte**: cmux (scansione a eventi, ma con `ps` + `lsof`) [10] e Superset (polling 2,5 s, bug con `lsof` a raffica) [7][8].
- **Terminale**: cmux (libghostty, nativo) [10]; Claude desktop per l'integrazione con la Sessione (stesso ambiente, stessa cartella) [1].
- **Editor**: Superset (molti editor, `:riga:colonna`) [9].
- **Isolamento TCC**: nessuno.

## Rischi e casi limite

- **SPI privata.** `responsibility_spawnattrs_setdisclaim` non è documentata. Se sparisce, il terminale eredita tutto come in VS Code; l'ADR 0005 prevede già il ripiego (solo Microfono, detto nelle Impostazioni).
- **Avvisi TCC col nome del binario.** Con il disclaim, `node` o `python` di terze parti chiedono i permessi a nome proprio; per i binari Apple l'avviso sarà per lo `zsh` del terminale. Diverso dal Terminale di sistema (dove chiede "Terminale"): va spiegato nelle Impostazioni.
- **SwiftTerm cambia API.** La 1.20 annuncia "breaking changes": versione fissata e SwiftTerm isolato dietro `Terminal/`.
- **Job control.** Senza il lanciatore `TIOCSCTTY` il terminale sembra funzionare ma ⌃C e ⌃Z no (misura B).
- **Server che non stanno nel worktree.** Docker (la porta è di `com.docker.backend`, cartella altrove), server remoti via `ssh -L`, servizi di sistema: si mostrano solo se sono nelle porte della Sessione, altrimenti niente attribuzione.
- **Server che ascoltano solo su IPv6 `::1` o su `0.0.0.0`.** Vanno letti entrambi gli indirizzi dal socket; `localhost` in WebKit prova IPv6 e IPv4.
- **HTTPS locale e `*.localhost`.** Certificati autofirmati (mkcert) e sottodomini: `url` personalizzato da `launch.json` [1]; con un certificato non fidato Bubo non aggiunge eccezioni.
- **Pagina del Progetto non fidata.** L'Anteprima esegue il codice del Progetto dentro Bubo: niente ponte JS verso Bubo oltre ai messaggi della console, mondo JS separato per gli script di Bubo, microfono e fotocamera negati.
- **Azioni dell'agente con effetti fuori dal Mac.** Un server locale collegato a un'API di produzione trasforma un clic (livello 2) in un effetto esterno. È un rischio del server, non dell'Anteprima: la classificazione resta 2 e la spec lo dichiara ([#139](https://github.com/mgiuditta/bubo/issues/139)).
- **Memoria.** Ogni `WebPage` ha un processo WebContent; ogni terminale ha scrollback in RAM (Conductor limita a 10 MB [4]). Con 10 Sessioni serve un tetto di scrollback per scheda.
- **Finestra di conferma di VS Code.** Con `vscode://file` ogni apertura chiede conferma [19]; con la CLI no.
- **`PATH` ridotto.** Un'app avviata dal Dock non ha il `PATH` della shell; Claude desktop lo ricava leggendo il profilo [1]. Il terminale, partendo come shell di login, lo ha già; la CLI dell'editor va risolta dal bundle.

## Mappa

Architettura comune in [INDEX.md](INDEX.md). Si appoggia su `Agent/ProcessSpawner` e sul ponte agente (ADR 0005, [#66](https://github.com/mgiuditta/bubo/issues/66)), su `Sessions/` e `Sessions/PortAllocator` (01), sull'Attività e le Viste delle Sessioni (06), su `Permissions/RiskClassifier` (05), sugli Allegati di `Intake/` (09) e sulla Palette (14).

### Terminale (deciso)

Fonte: [#133](https://github.com/mgiuditta/bubo/issues/133), [#140](https://github.com/mgiuditta/bubo/issues/140).

- **Dove**: pannello di vetro nel dettaglio della Sessione nell'HUD, staccabile in una finestra. Più schede per Sessione. ⌃\` apre e chiude (solo con Bubo in primo piano, voce nel menu e nella Palette).
- **Solo dentro una Sessione**: parte nel suo worktree; nella cartella del Progetto se il Progetto non è git. Nessun terminale sul checkout principale e nessuno per le Domande: per quello ci sono Terminal.app e Ghostty.
- **Shell**: `$SHELL -l` dell'utente con l'ambiente della Sessione: `PORT` e `BUBO_PORT` (prima delle 10 porte della Sessione) e `BUBO_PORTS` (l'intervallo).
- **Avvio**: `Agent/ProcessSpawner` avvia con disclaim il lanciatore del bundle, che fa `setsid` + `ioctl(0, TIOCSCTTY, 0)` + `execv` della shell; `POSIX_SPAWN_CLOEXEC_DEFAULT`, nessun descrittore di Bubo passa alla shell. SwiftTerm è solo la vista (`TerminalView`), il PTY è di Bubo e si legge con `DispatchIO`.
- **Vita**: alla chiusura di Bubo i processi muoiono, con una conferma se qualcosa è in esecuzione; lo scrollback non si salva. Niente persistenza tipo tmux (servirebbe un demone). Archivia e Fondi chiudono terminali e server con una conferma che elenca cosa è in esecuzione.
- **All'agente solo con un gesto**: la selezione o l'output dell'ultimo comando (individuato con OSC 133) diventano un **Allegato** della Sessione. Nessuna lettura automatica del terminale.
- **Percorsi**: ⌘-clic su un percorso `file:riga` nell'output apre il visore alla riga.
- **`gh` mancante** (feature 16): si apre il terminale della Sessione, dove l'utente lo installa o fa il login.

### Server e porte (deciso)

- **Rilevamento sempre attivo, a eventi**: URL `localhost` nell'output del terminale, Invio digitato nel terminale, OSC 133 (inizio e fine comando, quando la shell lo emette: zsh e bash solo con un'integrazione che arriva con #167), fine di un Bash dell'agente dal ponte (`PostToolUse` o `PostToolUseFailure`), uscita di un server già trovato, avvio di Bubo e di una Sessione sul checkout. Dopo ogni evento qualche scansione ravvicinata con `libproc`; a riposo nessuna. Mai `lsof` né `ps`.
- **Attribuzione**: un socket in ascolto è della Sessione se la `cwd` del processo sta nel suo worktree, oppure se la porta è una delle sue 10. Docker e tunnel `ssh` compaiono solo nel secondo caso. IPv4 e IPv6 letti entrambi.
- **"Avvia server"**: se esiste `.claude/launch.json`, un pulsante lancia il comando in una scheda del terminale con la `PORT` della Sessione; con `autoPort: false` (porta fissa, per esempio per un callback OAuth) `PORT` è la `port` del file. Bubo non ha un suo formato di configurazione.
- **Etichetta**: quando la porta viene trovata compare solo `localhost:NNNN` sulla Sessione e nella Board (17). L'Anteprima si apre con un clic sull'etichetta o con ⌘⇧P, mai da sola. Quando l'agente usa l'Anteprima, l'etichetta mostra "l'agente usa l'anteprima".
- **Server che torna in ascolto** dopo un riavvio: l'Anteprima aperta si ricarica.

### Anteprima (deciso)

Fonte: [#133](https://github.com/mgiuditta/bubo/issues/133), [#139](https://github.com/mgiuditta/bubo/issues/139).

- **Dove**: pannello accanto al terminale, staccabile. Una `WebPage` per Sessione, la stessa per utente e agente.
- **Cosa apre**: solo `localhost` e `*.localhost` sulle porte dei server della Sessione, più l'`url` di `launch.json` se è locale (`127.0.0.1` o `::1` diventano `localhost`). Ogni altra navigazione viene annullata; una pagina esterna aperta come pagina principale va al browser di sistema, un frame esterno no. `localhost`, mai `127.0.0.1`.
- **Cookie per Sessione**: `WKWebsiteDataStore(forIdentifier:)` con l'id della Sessione. Un login fatto nella Sessione A non esiste nella B; un login fatto dall'utente vale anche per l'agente.
- **Permessi**: microfono e fotocamera negati sempre (`WebPage.Configuration.deviceSensorAuthorization = .init(decision: .deny)`, che copre anche i sensori); nessuna eccezione in v1.
- **Strumenti per l'utente**: larghezze preimpostate (mobile, tablet, desktop, più `customUserAgent`), console visibile (script iniettato nel mondo della pagina su `console.*`, `onerror`, `unhandledrejection`, che manda a Bubo solo livello e testo), Web Inspector attivo (`isInspectable`), ricarica.
- **Certificato non fidato**: pagina "Apri nel browser", nessuna eccezione di fiducia in Bubo.
- **Vita**: la `WebPage` nasce al primo uso (clic dell'utente o primo strumento dell'agente) e resta viva anche a pannello chiuso, perché l'agente la usa fuori schermo; si chiude quando il server non è più rilevato o la Sessione diventa Fusa o Archiviata. L'archivio dei cookie resta.

### L'agente e l'Anteprima (deciso)

Fonte: [#139](https://github.com/mgiuditta/bubo/issues/139).

- **Meccanismo**: un server MCP nel processo del ponte (`createSdkMcpServer`) inoltra le chiamate a Swift con il protocollo stdio; Swift pilota la stessa `WebPage` dell'utente, con gli stessi cookie. Niente Playwright, niente Chromium headless, nessun processo esterno.
- **Strumenti e Livello di rischio**: screenshot, DOM, console e rete in lettura sono **1 Lettura**; navigare, cliccare, compilare, scorrere ed eseguire JS sono **2 Modifica reversibile**. In Modalità autonoma l'agente verifica senza Richieste di permesso. Tutti limitati ai server `localhost` della Sessione.
- **Quando esistono**: solo se la Sessione ha un server rilevato; senza server la loro descrizione non entra nel contesto (0 token). Nessuna verifica forzata e nessuna opzione nelle Impostazioni: l'agente li usa quando servono. Si rivede se l'agente verifica troppo poco.
- **Vince l'utente**: un clic o un tasto dell'utente nell'Anteprima mentre l'agente pilota fa fallire l'azione in corso con "l'utente ha preso il controllo".
- **Limiti**: screenshot ridimensionati a 1568 px sul lato lungo; console e rete come ultime 200 righe, con un filtro; ogni azione scade dopo 10 s.

### Visore ed editor (deciso)

- **Visore** in sola lettura con evidenziazione della sintassi e numeri di riga, aperto al punto giusto da Galassia (11), diff (02) e percorsi ⌘-clic nel terminale. Un pulsante "Apri nell'editor" porta alla stessa riga. Nessuna modifica: l'editor vero è fuori portata.
- **Editor**: VS Code, Cursor, Zed e Xcode rilevati con `NSWorkspace` per bundle id; predefinito il primo trovato, modificabile nelle Impostazioni. Si apre sempre con la CLI del bundle alla riga (`code -g`, `cursor -g`, `zed f:r:c`, `xed -l`), avviata con disclaim; mai con `vscode://`. Per gli altri editor `open -b`, senza riga.
- **Riuso**: "Nuovo agente" della feature 19 apre il file creato con lo stesso lanciatore.

### Moduli

- `Terminal/TerminalLauncher`: eseguibile C nel bundle (`setsid`, `TIOCSCTTY`, `execv`), firmato con l'app.
- `Terminal/PTYSession`: apre il PTY, avvia il lanciatore via `Agent/ProcessSpawner`, legge con `DispatchIO`, gestisce ridimensionamento, segnali al gruppo di processi e chiusura; ambiente dalla Sessione.
- `Terminal/CommandMarks`: OSC 133 (inizio e fine comando, output dell'ultimo comando) e URL `localhost` nell'output, come eventi.
- `Terminal/TerminalPanel`: SwiftTerm `TerminalView` in schede, pannello di vetro staccabile, ⌃\`; azioni "Allega selezione" e "Allega ultimo comando" verso `Intake/`.
- `Servers/PortWatcher`: scansione `libproc` (`proc_listpids`, `PROC_PIDLISTFDS`, `PROC_PIDFDSOCKETINFO`, `PROC_PIDVNODEPATHINFO`) a raffica dopo un evento, 0 a riposo.
- `Servers/ServerAttribution`: socket → Sessione (worktree che contiene la `cwd`, poi le 10 porte).
- `Servers/LaunchConfig`: lettura di `.claude/launch.json` e "Avvia server".
- `Preview/PreviewPage`: una `WebPage` per Sessione, archivio di cookie per id, criterio di navigazione (solo `localhost` della Sessione), microfono e fotocamera negati, script della console nel mondo della pagina (solo messaggi di log verso Bubo); gli script di Bubo che leggono il DOM in un mondo separato.
- `Preview/PreviewPanel`: pannello staccabile, larghezze, console, ⌘⇧P, pagina "Apri nel browser".
- `Preview/PreviewDriver`: lato Swift degli strumenti dell'agente (screenshot, DOM, click, compilazione, scorrimento, JS), tempi limite, interruzione quando l'utente prende il controllo.
- `bridge/` (TS): server MCP dell'Anteprima con `createSdkMcpServer`, registrato solo con un server rilevato; inoltro a Swift sul protocollo stdio esistente.
- `Viewer/CodeViewer`: visore in sola lettura.
- `Editor/EditorLauncher`: rilevamento degli editor per bundle id, comando alla riga, avvio con disclaim.
- Estensioni: `Agent/ProcessSpawner` (avvio di processi qualunque, non solo `claude`), `Sessions/PortAllocator` (`BUBO_PORTS`), `Permissions/RiskClassifier` (strumenti dell'Anteprima: 1 e 2).

### Flusso

1. ⌃\` nella Sessione → `PTYSession` → `ProcessSpawner` (disclaim) → lanciatore → `$SHELL -l` nel worktree con `PORT`, `BUBO_PORT`, `BUBO_PORTS`.
2. `npm run dev` (o "Avvia server", o l'agente con Bash) → evento (URL nell'output, OSC 133, `PostToolUse`) → raffica di `PortWatcher` → `ServerAttribution` → etichetta `localhost:NNNN` sulla Sessione entro 1 s → il ponte registra gli strumenti dell'Anteprima.
3. Clic sull'etichetta o ⌘⇧P → `PreviewPage` della Sessione → pannello.
4. L'agente chiama uno strumento → `bridge/` → stdio → `PreviewDriver` sulla stessa `WebPage` → risultato all'agente; l'etichetta mostra "l'agente usa l'anteprima".
5. Percorso ⌘-clic, stella della Galassia o riga del diff → visore alla riga → "Apri nell'editor" → `EditorLauncher` (CLI con disclaim).
6. Archivia, Fondi o uscita da Bubo → conferma con l'elenco dei processi → terminali e server chiusi, `WebPage` chiusa.

### Casi limite

- **Sessione senza server**: niente etichetta e niente strumenti MCP; ⌘⇧P non fa nulla.
- **Due Sessioni con lo stesso dev server**: porte diverse da `PORT`, cookie diversi, nessun conflitto. Se il server ignora `PORT` (Vite) la seconda prende la porta libera successiva e resta attribuita per `cwd`.
- **Server staccato o lanciato dall'agente in background**: attribuito dalla `cwd`, non dall'albero dei processi.
- **Docker, tunnel `ssh`, server fuori dal worktree**: solo se ascoltano nelle porte della Sessione.
- **Server che si riavvia**: etichetta tenuta, Anteprima ricaricata al ritorno dell'ascolto.
- **Link o redirect verso un sito esterno**, anche chiesto dall'agente: navigazione annullata; per l'utente si apre nel browser di sistema, per l'agente lo strumento fallisce.
- **HTTPS con certificato non fidato**: pagina "Apri nel browser".
- **L'utente interagisce mentre l'agente pilota**: azione dell'agente interrotta.
- **Pagina che non finisce di caricare**: l'azione scade a 10 s.
- **Shell che non termina a HUP**: Bubo chiude il gruppo di processi con un segnale più forte prima di uscire.
- **Binario nel terminale che chiede un permesso TCC**: l'avviso porta il nome del binario, non di Bubo; spiegato nelle Impostazioni.
- **Editor non installato o non trovato**: "Apri nell'editor" non compare; il visore resta.
- **Riduci movimento e VoiceOver**: il terminale segue l'accessibilità di SwiftTerm; il pannello dell'Anteprima e il visore passano l'audit AppKit e SwiftUI.

### Test

- Disclaim: test che avvia shell, un dev server `node` e la CLI dell'editor e legge `responsibility_get_pid_responsible_for_pid` e `launchctl procinfo`: 0 processi con Bubo come responsabile.
- Terminale di controllo: nella shell `ps -o tty=` restituisce un tty, `/dev/tty` si apre, ⌃C interrompe un `sleep` in primo piano.
- Tempo di apertura: ⌃\` → primo prompt disegnato, con una shell senza profilo, su 20 aperture.
- `PortWatcher`: server finti in cartelle finte di worktree e su porte della Sessione con `cwd` altrove; attribuzione giusta al 100%; monitor dei processi figli: 0 `lsof` e 0 `ps`; contatore delle scansioni a riposo: 0.
- Porte: due Sessioni avviano lo stesso server con `PORT`: entrambe in ascolto.
- Cookie: login nella Sessione A, pagina aperta nella B: non autenticata; login dell'utente, poi strumento dell'agente sulla stessa pagina: autenticato.
- Navigazione: test che prova a uscire (link, `window.location`, redirect, JS dell'agente) verso un host esterno e verso `127.0.0.1` di un'altra Sessione: 0 navigazioni riuscite.
- Strumenti MCP: elenco degli strumenti senza server rilevato = vuoto; con server = presente; tempi di screenshot e click su 50 ripetizioni.
- Interruzione: clic sintetico dell'utente durante un'azione lunga dell'agente: errore "l'utente ha preso il controllo" entro 100 ms.
- Editor: per VS Code, Cursor, Zed e Xcode, file aperto alla riga giusta, 0 finestre di conferma.
- Uscita: Bubo chiuso con terminali e server attivi → 0 processi figli vivi.
- Accessibilità: audit AppKit e SwiftUI di terminale, Anteprima e visore.

### Ordine di costruzione

1. **Terminale nel worktree**: lanciatore, `PTYSession`, `TerminalPanel` a schede, ⌃\`, chiusura con conferma all'uscita e ad Archivia/Fondi. Dipende da: ponte agente con disclaim e `Agent/ProcessSpawner` ([#66](https://github.com/mgiuditta/bubo/issues/66), ADR 0005), 01 (worktree, `PortAllocator` con `BUBO_PORTS`), shell dell'HUD.
2. **Server e porte**: `CommandMarks`, `PortWatcher`, `ServerAttribution`, `LaunchConfig`, etichetta sulla Sessione. Dipende da: passo 1, hook `PostToolUse` dal ponte, 06 (dettaglio della Sessione); l'etichetta nella Board arriva con 17.
3. **Anteprima per l'utente**: `PreviewPage` e `PreviewPanel`, cookie per Sessione, solo `localhost`, microfono e fotocamera negati, console, larghezze, ⌘⇧P. Dipende da: passo 2.
4. **L'agente pilota l'Anteprima**: server MCP in `bridge/`, `PreviewDriver`, livelli 1 e 2 in `RiskClassifier`, interruzione, limiti. Dipende da: passo 3, ponte agente, 05 (Livello di rischio, Modalità autonoma).
5. **Visore e Apri nell'editor**: `CodeViewer`, `EditorLauncher`, ⌘-clic nel terminale, ingressi da diff e Galassia. Dipende da: `Agent/ProcessSpawner`; passo 1 per il ⌘-clic; 02 e 11 per i loro ingressi (si aggiungono quando esistono).
6. **Terminale verso l'agente e Palette**: "Allega selezione" e "Allega ultimo comando" come Allegati; comandi Terminale e Anteprima nella Palette. Dipende da: passo 1, `Intake/` e Allegati ([#85](https://github.com/mgiuditta/bubo/issues/85)), Palette (14).

## Specifica "migliore di"

Miglior concorrente per l'Anteprima: **Claude desktop** (terminale nella Sessione, `launch.json`, agente che verifica da solo), che però fa ereditare i permessi dell'app, ha un solo archivio di cookie e strumenti sempre presenti. Per le porte: **cmux** e **Superset**, a colpi di `lsof`. Per l'editor: **Superset**, l'unico che tiene `:riga:colonna`. Nessuno isola il terminale da TCC.
Bubo li supera così:

1. **Isolamento TCC**: **0 processi** del terminale, dei server o dell'editor con Bubo come responsabile (`launchctl procinfo`). VS Code, Cursor e Claude desktop fanno ereditare i permessi dell'app.
2. **Apertura del terminale**: ⌃\` apre il pannello in **< 100 ms** (profilo della shell escluso dalla misura).
3. **Server rilevato**: la porta compare nella Sessione **entro 1 s** dall'inizio dell'ascolto, con **0 scansioni a riposo** e **0 `lsof`/`ps`** lanciati. Superset interroga ogni 2,5 s, cmux lancia `lsof` a ~40 ms a chiamata.
4. **Attribuzione**: **100%** dei server avviati nel worktree o nelle porte della Sessione attribuiti alla Sessione giusta, **0** attribuiti a un'altra.
5. **Porte**: due Sessioni che avviano lo stesso server con `PORT` partono entrambe, **0 conflitti**.
6. **Editor**: **1 clic** apre il file nell'editor alla riga giusta, **0 finestre di conferma**. Claude desktop non porta alla riga, Conductor apre solo la cartella.
7. **Cookie per Sessione**: un login fatto nell'Anteprima della Sessione A **non si vede** nella B.
8. **Uscita pulita**: all'uscita da Bubo restano **0 processi figli** vivi.
9. **Azioni visibili**: con il pannello aperto l'utente vede in diretta il **100%** delle azioni dell'agente. Playwright e i Chromium headless (Cursor MCP, agent-browser) non le mostrano.
10. **Confine della Sessione**: **0 navigazioni** degli strumenti fuori dai server della Sessione (test che prova a uscire).
11. **Costo a vuoto**: senza un server rilevato gli strumenti non esistono, **0 token** di descrizione. Claude desktop li ha sempre.
12. **Velocità degli strumenti**: screenshot in **< 500 ms**; click in **< 200 ms** più l'attesa del caricamento, entro **10 s**.
13. **Vince l'utente**: un clic o un tasto dell'utente interrompe l'azione dell'agente **entro 100 ms**.
14. **Login condiviso con l'agente**: un login fatto dall'utente vale anche per l'agente, **0 credenziali** ripetute.
15. **Scorciatoie**: ⌃\` e ⌘⇧P compaiono nei menu e nella Palette; **0 scorciatoie globali** nuove.

## Fonti

1. Claude Code, "Desktop application" (terminale, Browser, `launch.json`, `autoPort`, `autoVerify`, Open in, ambiente) — https://code.claude.com/docs/en/desktop
2. Conductor, "Run Scripts, Terminals, and Ports" — https://conductor.build/docs/reference/scripts
3. Conductor, changelog (titoli delle versioni 0.29.5, 0.38.1, 0.46.0, 0.48.0, 0.62.0, 0.83.0) — https://www.conductor.build/changelog
4. Conductor v0.63.0, note di rilascio (copia su releases.sh, fonte secondaria del changelog ufficiale) — https://releases.sh/release/rel_SUYMvfUijNDa8dJyq_sAc
5. Conductor, "Use with Cursor" — https://www.conductor.build/docs/guides/use-with-cursor
6. Superset, "Ports" — https://docs.superset.sh/ports
7. Superset, codice: `packages/port-scanner/src/port-manager.ts` (`SCAN_INTERVAL_MS = 2500`, `IDLE_SCAN_INTERVAL_MS`, `PORT_HINT_PATTERNS`) e `scanner.ts` (`lsof`, `pidtree`); `packages/pty-daemon`; `apps/desktop/src/main/lib/terminal/session.ts` (`@xterm/headless`) — https://github.com/superset-sh/superset/tree/main/packages/port-scanner/src
8. Superset, issue #3372 "lsof excessive use" — https://github.com/superset-sh/superset/issues/3372
9. Superset, `apps/desktop/src/lib/trpc/routers/external/helpers.ts` (`open -a`/`open -b`, bundle id di Zed e JetBrains, suffissi `:riga:colonna`) — https://github.com/superset-sh/superset/blob/main/apps/desktop/src/lib/trpc/routers/external/helpers.ts
10. cmux, README, `.gitmodules` (fork di Ghostty), `Sources/PortScanner.swift` — https://github.com/manaflow-ai/cmux
11. Cursor, "Browser" — https://cursor.com/docs/agent/browser
12. Warp, README (licenze, dipendenze) e `crates/warp_terminal/src/local_tty/server/mod.rs` — https://github.com/warpdotdev/warp
13. Zed, `Cargo.toml` (`alacritty_terminal`), "CLI reference" — https://zed.dev/docs/reference/cli ; `crates/zed/src/zed/open_listener.rs` — https://github.com/zed-industries/zed/blob/main/crates/zed/src/zed/open_listener.rs
14. Nimbalyst, README e `packages/electron/src/renderer/components/Terminal/ghosttyInstance.ts` — https://github.com/nimbalyst/nimbalyst
15. SwiftTerm, README, `Sources/SwiftTerm/Pty.swift` (`forkpty`), `LocalProcess.swift`, release v1.17–v1.20 — https://github.com/migueldeicaza/SwiftTerm
16. Ghostty, README (sezione libghostty), `include/ghostty.h`, `src/Command.zig` — https://github.com/ghostty-org/ghostty ; M. Hashimoto, "Libghostty is coming" (2025-09-22) — https://mitchellh.com/writing/libghostty-is-coming
17. awesome-libghostty (elenco di progetti, fonte secondaria) — https://github.com/Uzaaft/awesome-libghostty
18. VS Code, issue #307364 "macOS: Child processes cannot access TCC-protected resources" — https://github.com/microsoft/vscode/issues/307364
19. VS Code, "Command Line Interface" (`--goto`, `vscode://file`) — https://code.visualstudio.com/docs/configure/command-line ; `src/vs/workbench/electron-browser/desktop.contribution.ts` (`security.promptForLocalFileProtocolHandling`) — https://github.com/microsoft/vscode/blob/main/src/vs/workbench/electron-browser/desktop.contribution.ts
20. Apple, TN3179 "Understanding local network privacy" (rev. 2026-02-17) — https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
21. Apple, `NSAllowsLocalNetworking` — https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking
22. Apple, `WebPage` e `WebPage.Configuration` (macOS 26) — https://developer.apple.com/documentation/webkit/webpage ; `WebView` — https://developer.apple.com/documentation/webkit/webview-swift.struct
23. Apple, `WKWebView.isInspectable` — https://developer.apple.com/documentation/webkit/wkwebview/isinspectable
24. Apple, `WKWebsiteDataStore.init(forIdentifier:)` — https://developer.apple.com/documentation/webkit/wkwebsitedatastore/init(foridentifier:)
25. Apple, `WKUIDelegate.webView(_:requestMediaCapturePermissionFor:initiatedByFrame:type:decisionHandler:)` — https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:requestmediacapturepermissionfor:initiatedbyframe:type:decisionhandler:)
26. Qt, "The curious case of the responsible process" (disclaim) — https://www.qt.io/blog/the-curious-case-of-the-responsible-process

Misure (questo Mac, macOS 26.7, 2026-09-30):
- **A**: `posix_spawn` di `/bin/zsh` con e senza `responsibility_spawnattrs_setdisclaim`; ogni figlio legge `responsibility_get_pid_responsible_for_pid`. Binari provati: `sleep`, Python di Xcode, `node`, un binario C.
- **B**: stesso avvio con PTY (`openpty`, `POSIX_SPAWN_SETSID`, `adddup2` o `addopen`) e poi con un lanciatore che fa `setsid` + `TIOCSCTTY` + `execv`; controllo con `ps -o tty=` e apertura di `/dev/tty`.
- **C**: scansione `libproc` (`proc_listpids`, `PROC_PIDLISTFDS`, `PROC_PIDFDSOCKETINFO`, `PROC_PIDVNODEPATHINFO`) su 414 processi, tre esecuzioni; `lsof -nP -iTCP -sTCP:LISTEN -a -u <uid>`, tre esecuzioni.
- **D**: `nm -u` e `strings` su `node-pty/…/pty.node` di Cursor, Claude desktop 2.16120.0 e VS Code 1.139.1.
- **E**: `code --help` 1.139.1, `cursor --help`, `xed --help`, `CFBundleURLSchemes` di VS Code e Cursor.
