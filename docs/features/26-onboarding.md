# 26 — Onboarding di 60 secondi

Ticket: [#182](https://github.com/mgiuditta/bubo/issues/182) (ricerca), [#187](https://github.com/mgiuditta/bubo/issues/187) (prototipo e flusso), [#186](https://github.com/mgiuditta/bubo/issues/186) (soglie di prestazione). Mappa: [#178](https://github.com/mgiuditta/bubo/issues/178). Si appoggia su [#38](https://github.com/mgiuditta/bubo/issues/38) e [#39](https://github.com/mgiuditta/bubo/issues/39) (feature 03, PR [#176](https://github.com/mgiuditta/bubo/pull/176) e [#177](https://github.com/mgiuditta/bubo/pull/177)).
Ricerca del 2026-09-30 su macOS 26.7, CLI `claude` **2.1.285** (installazione nativa) e Agent SDK TS **0.3.285**; documentazione di Claude Code, OpenAI, Conductor, Cursor, Warp, Zed e Apple alla stessa data.

> **Nota sulla ricerca.** La ricerca riporta solo fatti; le decisioni sono in [#187](https://github.com/mgiuditta/bubo/issues/187) e [#186](https://github.com/mgiuditta/bubo/issues/186). Tre punti di documenti precedenti sono superati. In [03](03-account-uso.md) il caso "CLI assente" diceva di usare un `claude` incluso nel bundle: Bubo non porta nessun `claude` e guida l'installazione. In 03 `claude auth status` si leggeva "all'avvio": ora il rilevamento parte **dopo** l'HUD interattivo e fuori dall'onboarding non si lancia nessun `claude` all'avvio ([#186](https://github.com/mgiuditta/bubo/issues/186)). La PR [#176](https://github.com/mgiuditta/bubo/pull/176) cerca `claude` solo con la shell di login e lancia `claude auth login` come processo figlio: qui si cercano prima i percorsi assoluti e il login si apre nel Terminale. Valgono la Mappa e la Specifica qui sotto.

In sintesi: nessun concorrente pubblica un tempo "dal primo avvio alla prima risposta" e nessuno lo misura. I passi documentati vanno da 3 a 6. Tutti i concorrenti con un agente CLI si portano dietro il binario; solo Conductor controlla gli strumenti già presenti sul Mac e guida chi non li ha. Nessuno chiede permessi di sistema prima della prima risposta, ma molti li fanno comparire fuori contesto durante il lavoro. I guasti veri stanno nel **login**: callback che non torna, schermate "Authenticating…" senza timeout, loop di retry. Per Bubo il rilevamento è semplice e veloce: `claude --version` in 0,01 s, `claude auth status` in 0,19 s con exit 0/1. Però `loggedIn: true` dice solo che c'è una credenziale, non che funziona: la vera verifica è la prima richiesta. Bubo quindi fa tre cose: l'Orb guida dentro l'HUD senza finestre, il rilevamento non tocca il budget di avvio, e ogni guasto ha un riquadro con il rimedio che non perde la domanda.

## Ricerca

### Concorrenti al primo avvio

| Prodotto | Passi fino alla prima risposta | Binario dell'agente | Permessi di sistema al primo avvio | Tempo pubblicato |
|---|---|---|---|---|
| **Claude Desktop, scheda Code** [1][2] | 2 di installazione (DMG, accesso) + 4 per la prima sessione: scheda Code, ambiente Local e cartella, modello, prompt | Incluso: "you don't need to install Node.js or the CLI" [2] | Nessuno; Accessibilità e Registrazione schermo solo per il computer use | Nessuno |
| **ChatGPT con Codex** (v26.707) [3][4][5] | 4: installa, accedi, "Choose where to work", invia | Incluso: `codex` nel bundle [5] | Nessuno obbligatorio; notifiche "may ask", Microfono alla prima chat vocale | Nessuno |
| **Conductor** [6][7] | 3 di installazione + controlli automatici + aggiunta del repo | Claude Code preinstallato; si può indicare un binario di sistema | Nessuno documentato | Nessuno |
| **Cursor** [8] | "Download Cursor. Open the app and sign in. Then pick a folder" | Agente proprio | Nessuno documentato | Nessuno |
| **Warp** [9] | Installa, login facoltativo, ⌘↩ | Rileva `claude` solo se l'utente lo lancia | Nessuno documentato | Nessuno |
| **Zed** [10][11] | Welcome, pannello agente, installa "Claude Agent" dal registro ACP, `/login` | Adattatore npm con l'SDK (~224 MB per piattaforma [23]), con un `claude` suo | Nessuno documentato | Nessuno ufficiale |

**Conductor è l'unico che guarda il Mac.** Al primo avvio "it checks for the tools and credentials it needs. If anything is missing, Conductor walks you through setup": `gh auth status` e login di Claude Code [6]. Il changelog mostra quanto è fragile [7]: onboarding rotto per chi non aveva Claude Code (0.25.9), "Claude Code authentication to hang … during onboarding" (0.27.2).

### Lamentele ricorrenti

| Tema | Casi |
|---|---|
| **Login bloccato** | Zed #64852: "Authenticating to Claude Agent…" per ~50 minuti, senza timeout [11]. Codex #12263 (callback su localhost), #29636 [12]. Cursor: login riuscito nel browser, app ferma sull'accesso [13]. Codex 26.707 corregge "onboarding retry loops" [4] |
| **Permessi fuori contesto** | Cursor: "would like to access data from other apps" a ogni avvio, Apple Music [13]. Warp #13647 (Documenti, "Allow does nothing"), Zed #48746 (Foto "out of the blue") [14]. Codex: FAQ su Apple Music [5] |
| **PATH degli strumenti** | Claude Desktop: npm e node non trovati, il PATH viene dal profilo della shell [1] |
| **Account e piano** | Claude Desktop "Error 403: Forbidden" o piano non a pagamento [1] |

### Rilevare `claude`

**Dove si installa** [15][16]:

| Canale | Binario |
|---|---|
| Installer nativo (consigliato) | `~/.local/bin/claude` → `~/.local/share/claude/versions/<versione>` |
| Homebrew | `/opt/homebrew/bin/claude` (cask `claude-code`) |
| npm | cartella `bin` globale di npm (con Node di Homebrew: `/opt/homebrew/bin`) |
| Legacy | `~/.claude/local/claude` |

Un'app aperta dal Finder non legge `~/.zshrc`: il suo PATH è `/usr/bin:/bin:/usr/sbin:/sbin` e non contiene `~/.local/bin` [24]. `claude` va quindi cercato per percorso assoluto o chiedendo il PATH a una shell di login.

**Comandi** (prove in locale [24], riferimento [17]):

| Comando | Risultato | Tempo |
|---|---|---|
| `claude --version` | `2.1.285 (Claude Code)`, exit 0 | 0,01 s |
| `claude auth status` | JSON con `loggedIn`, `authMethod`, `subscriptionType`, `apiKeySource`; nessun token. Exit 0 con credenziale, 1 senza | 0,19 s |
| `claude -p` senza credenziali | Exit 1 subito, `Not logged in · Please run /login` | 38 ms |
| `claude -p` con una chiave finta | Nessuna risposta entro 120 s | — |
| `claude -p` loggato, a freddo | 4,04 s reali | — |

**Cosa non dice `loggedIn`** [18][16]:
- Una `ANTHROPIC_API_KEY` finta risulta "logged in" e prende il posto dell'abbonamento.
- Login scaduto (`Login expired · Please run /login`), piano non attivo (`403 Request not allowed`) e organizzazione disattivata (`400`) si scoprono solo alla prima richiesta.
- `auth status` non è di sola lettura: nella cartella di configurazione scrive `.claude.json`, `backups/` e un lock.

**Guidare chi non è pronto** [15][16][19]:
- Installazione: `curl -fsSL https://claude.ai/install.sh | bash` oppure `brew install --cask claude-code`.
- Login: `claude auth login` apre il browser di Anthropic; se il callback non torna, si incolla il codice su stdin.
- Il piano Free di claude.ai non include Claude Code.
- "Anthropic does not allow third party developers to offer claude.ai login" [19]: niente "Accedi con Claude" dentro Bubo (ADR 0003).

### Permessi di sistema al primo avvio

| Permesso | Quando scatta | Scelta dei concorrenti |
|---|---|---|
| File e cartelle (Scrivania, Documenti, Download, iCloud, volumi) | Al primo accesso a una posizione protetta; il pannello Apri e il trascinamento concedono per intento dell'utente [20] | Nessuno all'avvio; molti durante il lavoro |
| Notifiche | Apple: meglio chiedere in contesto; esiste l'autorizzazione **provvisoria**, senza prompt [21] | Codex "may ask" |
| Microfono | Alla prima cattura audio | Codex alla prima chat vocale |
| Accessibilità, Registrazione schermo | Solo al primo uso della funzione | Claude Desktop e Codex solo per il computer use |
| Automazione (Apple Events) | A ogni app controllata, se manca l'entitlement il popup si ripete [13] | Cursor per un difetto |

Apple (HIG Privacy): "asking for data before a person shows interest in the feature — can make it hard for people to trust your app" [22]. Per Bubo vale anche l'ADR 0005: `claude` parte con il disclaim e chiede File e cartelle a nome suo.

## Il meglio da battere

Il riferimento è **Conductor** per il controllo degli strumenti e **Claude Desktop** per la brevità (4 passi dopo l'installazione). Nessuno dei due pubblica un tempo, e nessuno dei due usa il `claude` dell'utente senza portarne una copia. Criteri candidati usciti dalla ricerca (quelli decisi sono nella Specifica):

1. **Un tempo pubblicato e misurato**: ≤ 60 s dal lancio alla prima risposta con `claude` già pronta, ripetibile con un test.
2. **Meno azioni**: Progetto, domanda, invio.
3. **Zero permessi** prima della prima risposta, contro i popup fuori contesto di Cursor, Warp e Zed.
4. **Nessuna attesa muta**: contro le schermate di autenticazione senza timeout di Zed e Conductor.
5. **Nessuna domanda persa**: dopo il rimedio la domanda riparte da sola.
6. **Nessun binario in più**: Bubo usa la `claude` dell'utente, e se manca lo dice.

## Rischi e casi limite

- **Credenziale presente ma non valida**: `auth status` dice sì, la prima richiesta fallisce o resta appesa (oltre 120 s con una chiave finta).
- **Login che non torna**: il callback di `claude auth login` può non arrivare. Bubo non può incollare il codice al posto dell'utente senza intermediare il login (ADR 0003).
- **Più installazioni di `claude`** con versioni diverse (nativo + Homebrew + npm): la shell dell'utente e Bubo potrebbero usarne due diverse.
- **Shell di login lenta o rumorosa**: `.zshrc` che stampa, chiede input o tocca cartelle protette.
- **`auth status` che scrive** nella cartella di configurazione: innocuo per un utente già attivo, ma è una scrittura.
- **Progetti recenti in cartelle protette**: controllare che esistano può far comparire l'avviso TCC di Bubo per Documenti o Scrivania prima della prima risposta.
- **Aprire il Terminale con `osascript`** richiede Apple Events: sarebbe un permesso di sistema (caso Nimbalyst #57 in [03](03-account-uso.md)).
- **Budget di avvio**: un rilevamento sincrono all'avvio lo romperebbe ([#186](https://github.com/mgiuditta/bubo/issues/186): ≤ 500 ms caldo, ≤ 1 s freddo, nessun `claude` finché non si apre una Sessione).
- **Utente che chiude Bubo a metà** onboarding, o che lo riapre dopo aver già lavorato.

## Mappa

Architettura comune in [INDEX.md](INDEX.md). Si appoggia sull'account (03: [#38](https://github.com/mgiuditta/bubo/issues/38), [#39](https://github.com/mgiuditta/bubo/issues/39)), sul ponte agente con disclaim ([#66](https://github.com/mgiuditta/bubo/issues/66)), sulle Sessioni in worktree (01, [#69](https://github.com/mgiuditta/bubo/issues/69)), sulle notifiche (06), sui segnali di prestazione della 25 ([#186](https://github.com/mgiuditta/bubo/issues/186)) e sulla versione minima di `claude` della 27 ([#188](https://github.com/mgiuditta/bubo/issues/188)).

### Il flusso (deciso)

Fonte: [#187](https://github.com/mgiuditta/bubo/issues/187), variante A "L'Orb guida" con due pezzi della C.

- **Nessuna finestra di benvenuto.** Al primo avvio si apre l'HUD con l'Orb grande. L'Orb dice "Controllo cosa c'è sul Mac…".
- **Rilevamento dopo l'HUD interattivo**: parte al signpost `HUD interattivo` della 25, quindi non pesa sul budget di avvio. Una **pastiglia di stato** in cima all'HUD mostra `claude <versione> · <metodo>` (per esempio `claude 2.1.285 · Max` oppure `· API key`).
- **Primo Progetto**: l'Orb chiede "Su cosa lavoriamo?". Propone fino a 3 Progetti recenti, più "Scegli un'altra cartella… ⌘O". Il pannello Apri vale come consenso: nessun popup TCC.
- **Prima domanda**: la barra di input è attiva da subito, con 3 domande suggerite: "Spiegami com'è fatto questo Progetto", "Trova i TODO più vecchi", "Cosa è cambiato nell'ultima settimana?". All'invio nasce la Sessione (worktree se git, feature 01) e la risposta arriva lì.
- **Domanda prima del Progetto** (dalla variante C): si può scrivere e inviare prima di scegliere. La domanda aspetta, l'Orb chiede "In quale Progetto?", e alla scelta parte.
- **Cronometro**: dal lancio al primo token della risposta nella Sessione.

### Rilevamento di `claude` (deciso)

Fonte: [#187](https://github.com/mgiuditta/bubo/issues/187), ADR 0003.

- **Ricerca per percorso assoluto**, in quest'ordine: `~/.local/bin/claude`, `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`, cartella `bin` globale di npm, `~/.claude/local/claude`. Solo se nessuno esiste: `command -v claude` nel PATH di una shell di login (`$SHELL -l -i -c`, timeout 5 s, avviata con disclaim). **Mai** il PATH dell'app.
- Poi `claude --version` e `claude auth status` (exit 0/1 + JSON), con lo stesso ambiente costruito da zero che riceverà la Sessione (INDEX). Nessuna lettura del Portachiavi né di `.credentials.json`.
- Il percorso trovato è lo stesso che il ponte passa come `pathToClaudeCodeExecutable`: la pastiglia mostra la `claude` che risponderà davvero.
- Esiti: **pronta** (versione + metodo), **mancante**, **non loggata**, **vecchia** (sotto la versione minima della 27).

### Quando `claude` non è pronta (deciso)

Fonte: [#187](https://github.com/mgiuditta/bubo/issues/187). Tutto questo sta fuori dai 60 s. Un **riquadro** nell'HUD, sotto la riga dell'Orb, mai una finestra modale.

- **CLI mancante**: "Serve Claude Code". Mostra `curl -fsSL https://claude.ai/install.sh | bash`, il pulsante "Copia e apri Terminale" e l'alternativa "Uso una API key". Bubo osserva le cartelle di installazione con FSEvents, senza polling, e prosegue da solo appena `claude` compare.
- **Non loggata**: "Accedi a Claude Code". Il pulsante apre il Terminale su `claude auth login`. Bubo non intermedia il login (ADR 0003) e rilegge `auth status` quando l'utente torna in Bubo. Alternativa: API key.
- **Credenziale presente ma non valida**: la verifica vera è la prima richiesta. Un errore di autenticazione (401, 403, 400, login scaduto) mostra "La chiave non funziona" oppure "Login scaduto", con "Accedi con l'abbonamento" o "Cambia chiave". La domanda **non si perde**: riparte da sola dopo il rimedio.
- **API key**: va nel Portachiavi, scelta dall'utente (ADR 0003, [#39](https://github.com/mgiuditta/bubo/issues/39)). È l'unico caso in cui Bubo tocca una credenziale. Arriva alla Sessione solo nell'ambiente del figlio.
- **Timeout del primo token**: oltre 30 s senza il primo token, riquadro "Claude non risponde" con Riprova e Diagnostica (`claude doctor`).

### Permessi di sistema (deciso)

Nessuno prima della prima risposta.

- **Notifiche**: autorizzazione provvisoria, senza prompt (feature 06).
- **Microfono**: alla prima pressione di ⌥ per parlare (feature 08).
- **Accessibilità e le altre funzioni della 09**: quando si attiva la funzione.
- **File e cartelle**: li chiede `claude` a nome suo (ADR 0005), oppure si concedono dal pannello Apri.

### Scelte di dettaglio

Prese scrivendo la spec, coerenti con le decisioni sopra.

- **Quando c'è l'onboarding**: al primo avvio e finché non arriva la prima risposta in una Sessione. Se Bubo si chiude a metà, alla riapertura l'onboarding riprende dal punto giusto, con la domanda in attesa salvata. Se esiste già un Progetto con almeno una Sessione, non compare.
- **Nessun `claude` all'avvio fuori dall'onboarding**: dopo, il rilevamento si ripete all'apertura della prima Sessione di ogni avvio (costa ~0,2 s dentro il budget "Sessione pronta ≤ 1 s") e in Impostazioni › Account (03). L'invariante "0 `claude` all'avvio" della 25 si misura a onboarding completo e resta vero; durante l'onboarding `--version` e `auth status` sono processi brevi, lanciati nell'`Avvio differito` della 25.
- **Signpost nuovi** nel catalogo `Perf/Signposts` della 25: intervallo `Rilevamento claude`, evento `Primo token onboarding`. Il budget va in `BuboPerfTests/PerfBudgets.swift`.
- **Pastiglia**: resta visibile finché dura l'onboarding, poi sparisce; lo stato dell'account vive in Impostazioni › Account.
- **Progetti recenti**: solo le chiavi `projects` di `~/.claude.json`; il resto del file non si tiene in memoria. Si scartano i percorsi che non esistono, la home, `/` e i worktree (cartelle in cui `.git` è un file). Ordine: data di modifica della cartella `~/.claude/projects/<percorso codificato>`, calcolata dal percorso e mai ricostruita al contrario dal nome (opcode #465 in [04](04-settaggi-claude.md)).
- **Recenti in cartelle protette** (Scrivania, Documenti, Download, iCloud Drive, `/Volumes`): Bubo **non** controlla che esistano, per non far comparire l'avviso TCC. Il clic apre il pannello Apri già puntato su quella cartella: un clic su Apri vale come consenso. Da verificare in costruzione che il consenso resti tra un avvio e l'altro.
- **Aprire il Terminale senza Apple Events**: Bubo scrive un file `.command` (permessi 0700, cartella temporanea di Bubo) e lo apre con `NSWorkspace` nell'app predefinita per quei file. Nessun `osascript`, quindi nessun permesso Automazione. Il Terminale parte da launchd, non da Bubo: nessuna eredità TCC.
  - Login: il `.command` esegue `claude auth login`. Se il callback non torna, l'utente incolla il codice nel suo Terminale: Bubo non lo vede.
  - Installazione: "Copia e apri Terminale" copia il comando negli appunti e apre il Terminale vuoto. Il `curl | bash` lo lancia l'utente.
  - Diagnostica: il `.command` esegue `claude doctor`, perché il formato dell'uscita e il codice d'uscita non sono documentati.
- **Ritorno dal Terminale**: si rilegge `auth status` quando Bubo torna attivo e quando cambia la data di modifica di `~/.claude.json` (solo l'evento FSEvents, nessuna lettura), con un intervallo di 1 s tra due controlli.
- **Osservare l'installazione**: FSEvents sulla cartella esistente più vicina a `~/.local/bin` e su `/opt/homebrew/bin`; il flusso riparte entro 2 s dalla comparsa di `claude`.
- **"Uso una API key" con la CLI mancante**: la chiave si salva, ma `claude` resta necessaria. Il riquadro lo dice. Dopo l'installazione il passo del login si salta: la Sessione riceve la chiave nell'ambiente.
- **API key senza finestre**: un campo sicuro dentro il riquadro, non il foglio di Impostazioni › Account; stesso `APIKeyStore` di [#39](https://github.com/mgiuditta/bubo/issues/39).
- **Tre varianti del riquadro "non valida"**, dall'errore dell'SDK (`authentication_failed`, `billing_error`, `oauth_org_not_allowed`, testo `Login expired`, 401/403/400):
  - metodo API key → "La chiave non funziona", con "Cambia chiave" e "Accedi con l'abbonamento";
  - metodo claude.ai e login scaduto → "Login scaduto", con "Accedi di nuovo";
  - 403 "Request not allowed" con claude.ai → "Questo account non include Claude Code", con "Accedi con un altro account" e "Uso una API key".
- **La domanda riparte nella stessa Sessione**, con una nuova Conversazione dell'agente. Il worktree già creato resta.
- **Versione vecchia**: riquadro "Aggiorna Claude Code" con `claude update` nel Terminale. La soglia la fissa la 27.
- **Timeout di 30 s solo nell'onboarding** in v1.

### Moduli

Architettura comune in [INDEX.md](INDEX.md). Moduli nuovi:

- `Account/ClaudeLocator`: percorsi assoluti nell'ordine sopra, poi shell di login; restituisce percorso, versione ed eventuali altre installazioni. Lo usano `Account/ClaudeCLI` (03, al posto della sola shell di login di [#176](https://github.com/mgiuditta/bubo/pull/176)) e `Agent/AgentBridge` per `pathToClaudeCodeExecutable`.
- `Account/ClaudeReadiness`: stato chiuso pronta / mancante / non loggata / vecchia, da `ClaudeLocator` + `AuthStatus` (03). Lo leggono l'onboarding, Impostazioni › Account e la versione minima della 27.
- `Account/AuthFailure`: traduce gli errori del primo turno (errori dell'SDK e testi della CLI) in: chiave non valida, login scaduto, account senza Claude Code, non loggata, sconosciuto.
- `System/SystemTerminal`: apre il Terminale con un comando tramite un file `.command`, oppure vuoto. Riusabile dalla 16 per "`gh` mancante" da ⌘I ([#156](https://github.com/mgiuditta/bubo/issues/156)).
- `System/InstallWatcher`: FSEvents sulle cartelle di installazione e su `~/.claude.json` (solo eventi, nessun contenuto).
- `Onboarding/OnboardingFlow`: modello `@Observable` con i passi, la domanda in attesa (persistita), il segno di onboarding completo, il timeout del primo token.
- `Onboarding/RecentProjects`: chiavi `projects` di `~/.claude.json`, filtri e ordine; codice puro sopra un file system iniettato.
- `Onboarding/OnboardingStage`: vista SwiftUI dentro l'HUD: riga dell'Orb, pastiglia, elenco dei Progetti, barra di input con le 3 domande.
- `Onboarding/FixCard`: il riquadro dei rimedi (mancante, non loggata, vecchia, non valida, non risponde), con il campo per l'API key.
- Riuso: `Account/AuthStatus`, `ClaudeCLI`, `APIKeyStore` (03), `Agent/AgentBridge` e `ProcessSpawner` (ponte con disclaim), `Sessions/` e `WorktreeManager` (01), `System/Notifier` (06), `Perf/Signposts` e `BuboPerfTests` (25).

### Flusso

1. Lancio → HUD con l'Orb → signpost `HUD interattivo`.
2. `ClaudeReadiness`: `ClaudeLocator` → `claude --version` → `claude auth status` → pastiglia.
3. Pronta → "Su cosa lavoriamo?" + Progetti recenti + ⌘O; barra di input attiva da subito.
   Non pronta → `FixCard` → Terminale o API key → `InstallWatcher` o ritorno in Bubo → di nuovo il passo 2.
4. Progetto scelto + domanda (in qualunque ordine) → Sessione in worktree → primo turno nel ponte.
5. Primo token → signpost `Primo token onboarding` → onboarding completo.
   Errore di autenticazione → `AuthFailure` → `FixCard` → rimedio → la stessa domanda riparte nella stessa Sessione.
   30 s senza token → "Claude non risponde" → Riprova o Diagnostica.

### Casi limite

- **Più installazioni**: vince la prima dell'ordine. Se le versioni sono diverse, Impostazioni › Account le elenca con il percorso.
- **Shell di login lenta** (oltre 5 s) o con errori: esito mancante, con il riquadro di installazione e la nota "se l'hai già installata, Riprova".
- **Nessun Progetto recente** (utente nuovo di Claude Code): solo "Scegli un'altra cartella… ⌘O".
- **Cartella scelta non git**: Sessione senza worktree (01); la risposta arriva uguale.
- **Rete assente**: il primo turno fallisce con un errore di rete, non di autenticazione. Riquadro "Sei offline" con Riprova; nessun passaggio a pagamento (03).
- **`ANTHROPIC_API_KEY` o `apiKeyHelper`** nei settings dell'utente: `auth status` dice `api_key`; la pastiglia lo mostra, così l'utente sa che pagherà a consumo (03).
- **Login fatto in un altro terminale** mentre Bubo mostra il riquadro: l'evento su `~/.claude.json` fa rileggere lo stato e il flusso prosegue da solo.
- **Domanda inviata durante il rilevamento**: aspetta come quella inviata prima del Progetto.
- **Bubo chiuso durante il primo turno**: alla riapertura la Sessione esiste già; l'onboarding mostra la domanda con Riprova.
- **Utente che salta l'onboarding** (chiude l'HUD): il Panel torna come sempre; l'onboarding riprende alla prossima apertura dell'HUD finché non arriva una prima risposta.

### Test

- `ClaudeLocator` su un file system finto: ogni canale, più canali insieme, nessuno, shell di login in timeout. Nessun accesso al PATH dell'app.
- `ClaudeReadiness` e `AuthFailure` con `ProcessRunner` iniettato e campioni registrati: pronta con Max, API key, non loggata (exit 1), versione vecchia, 401, 403 "Request not allowed", 400 organizzazione disattivata, `Login expired`, errore di rete.
- `RecentProjects`: percorsi spariti, worktree, home, cartelle protette mai toccate (monitor delle chiamate al file system), ordine.
- `OnboardingFlow`: domanda prima del Progetto, domanda durante il rilevamento, rimedio che fa ripartire la stessa domanda, riapertura a metà, timeout di 30 s con orologio finto.
- **Prestazione** (`BuboPerfTests` della 25, `claude` finto in CI e vero sul Mac di riferimento): dal lancio al primo token con clic automatici. Budget di avvio della 25 invariato con l'onboarding attivo. Costruito in `OnboardingPerfTests`: ogni onboarding gira in una home nuova in `/tmp` (`CFFIXED_USER_HOME`), con un Progetto recente e `claude-finto.zsh`; tre azioni (Progetto, prima domanda suggerita, Invio), fine quando la pastiglia sparisce. Poi Bubo si riapre sulla stessa home a onboarding completo e il `claude` finto conta le proprie esecuzioni: devono essere 0.
- **Permessi**: controllo statico in `scripts/check.sh` che le richieste di Microfono, Accessibilità, Registrazione schermo e notifiche non provvisorie partano solo dai punti d'ingresso delle loro feature (`scripts/permissions-check.sh`, con l'elenco dei file ammessi). Prova a mano su un account macOS nuovo: 0 avvisi di sistema fino alla prima risposta.
- **Prova con persone**: 5 persone che non hanno mai visto Bubo, `claude` già pronta; cronometro dal lancio al primo token.
- **Credenziali**: test che nessun codice legga il Portachiavi di Claude né `.credentials.json`, e che di `~/.claude.json` resti solo l'elenco dei percorsi.
- Accessibilità: audit SwiftUI dell'`OnboardingStage` e del `FixCard`; tutto il flusso si fa da tastiera (↑↓, ↩, ⌘O).

### Ordine di costruzione

1. **Rilevamento di `claude`**: `ClaudeLocator`, `ClaudeReadiness`, avvio dopo il signpost `HUD interattivo`, pastiglia nell'HUD, `ClaudeCLI` e ponte che usano il percorso trovato. Dipende da [#38](https://github.com/mgiuditta/bubo/issues/38) e dal ponte ([#66](https://github.com/mgiuditta/bubo/issues/66)).
2. **Primo avvio nell'HUD**: `OnboardingFlow`, `RecentProjects`, `OnboardingStage`, domande suggerite, domanda prima del Progetto, Sessione e primo turno, notifiche provvisorie, signpost `Primo token onboarding`. Dipende da 1 e da [#69](https://github.com/mgiuditta/bubo/issues/69).
3. **Guida quando `claude` non è pronta**: `FixCard` per mancante, non loggata e vecchia; `SystemTerminal`, `InstallWatcher`, API key nel riquadro. Dipende da 1, 2 e [#39](https://github.com/mgiuditta/bubo/issues/39).
4. **Credenziale non valida e timeout**: `AuthFailure`, tre varianti del riquadro, la domanda che riparte da sola, 30 s senza token con Riprova e Diagnostica, rete assente. Dipende da 3.
5. **Misura dei 60 secondi**: test di prestazione dal lancio al primo token, controllo statico dei permessi, prova su account nuovo e con 5 persone, audit di accessibilità. Dipende da 2–4 e dal target di prestazione della 25.

## Specifica "migliore di"

Miglior concorrente: **Conductor**, l'unico che controlla gli strumenti dell'utente e guida chi non li ha, ma porta il suo Claude Code, si è bloccato più volte proprio nel login e non pubblica tempi. **Claude Desktop** ha meno passi (4), ma non pubblica tempi e non usa la CLI dell'utente.
Bubo li supera così:

1. **60 secondi**: **≤ 60 s** dal lancio al primo token della risposta in una Sessione, sul Mac di riferimento (M4 Max), con `claude` già pronta. Nella prova con 5 persone nuove, **5 su 5** entro 60 s.
2. **Parte macchina**: con i clic automatici, dal lancio al primo token **≤ 10 s p95** con `claude` vera (misurati 4–5 s nel prototipo).
3. **Tre azioni**: **≤ 3 azioni** dell'utente (Progetto, domanda, invio) con un Progetto recente fuori dalle cartelle protette.
4. **Zero permessi**: **0 avvisi di sistema** prima della prima risposta, su un account macOS nuovo.
5. **Zero finestre**: **0 finestre o fogli modali** di Bubo nell'onboarding; il pannello Apri compare solo se l'utente lo sceglie.
6. **Avvio intatto**: con l'onboarding attivo l'avvio resta **≤ 500 ms p95** caldo e **≤ 1 s** freddo fino all'HUD interattivo (25); rilevamento completo **≤ 1 s** dopo.
7. **Nessuna attesa muta**: entro **30 s** dall'invio arriva il primo token o un riquadro con il rimedio; **0** schermate ferme senza uscita.
8. **Nessuna domanda persa**: CLI mancante, login mancante, versione vecchia e credenziale non valida hanno un riquadro; dopo il rimedio la domanda riparte **da sola nel 100%** dei casi. Dopo l'installazione il flusso riparte **entro 2 s** dalla comparsa di `claude`, senza polling.
9. **Credenziali intatte**: **0 letture** del Portachiavi di Claude o di `.credentials.json`; di `~/.claude.json` si usano **solo** i percorsi dei Progetti (test automatico).

## Fonti

1. Claude Code, "Use Claude Code Desktop" (troubleshooting: 403, PATH) — https://code.claude.com/docs/en/desktop
2. Claude Code, "Get started with the desktop app" — https://code.claude.com/docs/en/desktop-quickstart
3. OpenAI, "ChatGPT desktop app" — https://learn.chatgpt.com/docs/app.md
4. OpenAI, Changelog (26.707 del 2026-07-09) — https://learn.chatgpt.com/docs/changelog#codex-2026-07-09-app
5. OpenAI, "Troubleshooting" (binario nel bundle, Apple Music) — https://learn.chatgpt.com/docs/reference/troubleshooting.md
6. Conductor, "Installation" e "First workspace" — https://www.conductor.build/docs/installation.md , https://www.conductor.build/docs/first-workspace.md
7. Conductor, Changelog (0.11.3, 0.25.9, 0.27.2) — https://www.conductor.build/changelog.md
8. Cursor, "Quickstart" — https://cursor.com/docs/get-started/quickstart
9. Warp, "Quickstart" e "Lifting the login requirement" — https://docs.warp.dev/getting-started/quickstart , https://warp.dev/blog/lifting-login-requirement
10. Zed, "External agents" — https://zed.dev/docs/ai/external-agents
11. zed-industries/zed #64852 — https://github.com/zed-industries/zed/issues/64852
12. openai/codex #12263, #29636 — https://github.com/openai/codex/issues/12263 , https://github.com/openai/codex/issues/29636
13. Forum Cursor, login bloccato e permessi — https://forum.cursor.com/t/desktop-app-stuck-on-login-screen-after-successful-browser-authentication/164774 , https://forum.cursor.com/t/cursor-would-like-to-access-data-from-other-apps-popup-shows-everytime-i-launch-cursor/140662
14. warpdotdev/warp #13647; zed-industries/zed #48746 — https://github.com/warpdotdev/warp/issues/13647 , https://github.com/zed-industries/zed/issues/48746
15. Claude Code, "Advanced setup" — https://code.claude.com/docs/en/setup
16. Claude Code, "Troubleshoot installation and login" — https://code.claude.com/docs/en/troubleshoot-install
17. Claude Code, "CLI reference" (`auth status`, `doctor`) — https://code.claude.com/docs/en/cli-reference
18. Claude Code, "Authentication" (precedenza delle credenziali, scadenza) — https://code.claude.com/docs/en/authentication
19. Claude Code, "Agent SDK overview" — https://code.claude.com/docs/en/agent-sdk/overview
20. Apple Developer Forums, Quinn "The Eskimo!", "On File System Permissions" — https://developer.apple.com/forums/thread/678819
21. Apple, "Asking permission to use notifications" — https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications
22. Apple, Human Interface Guidelines, "Privacy" — https://developer.apple.com/design/human-interface-guidelines/privacy
23. `@anthropic-ai/claude-agent-sdk` 0.3.285 (pacchetto `darwin-arm64`, 223,8 MB) — https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk
24. Prove in locale del 2026-09-30, `claude` 2.1.285 su macOS 26.7: ricerca [#182](https://github.com/mgiuditta/bubo/issues/182), [26-onboarding.md](https://github.com/mgiuditta/bubo/blob/research/26-onboarding/docs/features/research/26-onboarding.md)
