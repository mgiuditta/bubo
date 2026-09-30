# 19 — Agenti personalizzati e Automazioni programmate

Ticket: [#130](https://github.com/mgiuditta/bubo/issues/130) (ricerca), [#136](https://github.com/mgiuditta/bubo/issues/136) (decisioni), [#135](https://github.com/mgiuditta/bubo/issues/135) (Budget), [#132](https://github.com/mgiuditta/bubo/issues/132) (Board), [#140](https://github.com/mgiuditta/bubo/issues/140) (ingressi). Mappa: [#125](https://github.com/mgiuditta/bubo/issues/125).
Ricerca del 2026-09-30 su Agent SDK TS **0.3.282** (`sdk.d.ts` letto in locale), CLI `claude` **2.1.285**, documentazione Claude Code e Apple alla stessa data.

> **Nota sulla ricerca.** È scritta prima delle decisioni e in alcuni punti è superata. Niente tetto di costo per Automazione: valgono i Budget della feature 18 e l'Esecuzione si salta a Budget esaurito ([#135](https://github.com/mgiuditta/bubo/issues/135)). Automazioni diverse allo stesso orario partono insieme, non si saltano come in Claude Desktop ([#136](https://github.com/mgiuditta/bubo/issues/136)). "Tieni sveglio il Mac" vale solo se c'è un'Automazione nelle prossime 2 ore ed è spento di default. Gli agenti stanno in una finestra Agenti, non in un pannello dell'HUD ([#140](https://github.com/mgiuditta/bubo/issues/140)). Valgono la Mappa e la Specifica qui sotto.

In sintesi: il formato degli agenti c'è già ed è buono. I file `.claude/agents/*.md` hanno 18 campi, l'SDK li carica da solo e li elenca con `supportedAgents()`. Bubo non deve inventare niente: deve mostrarli, farli scegliere e far vedere di chi è ogni richiesta di permesso. Per le Automazioni il riferimento è l'**app desktop di Claude Code**, che fa già quasi esattamente ciò che la mappa ha scelto: attività locali solo con l'app aperta, worktree facoltativo, una sola esecuzione di recupero, modalità di permesso per attività. Ha però due punti deboli documentati. Se nessuno risponde a un permesso, l'esecuzione resta ferma. E le approvazioni "consenti sempre" si perdono tra un'esecuzione e l'altra (issue con 38 commenti). L'SDK ora ha la primitiva giusta per le Esecuzioni senza nessuno davanti: `permissionPrompts: 'none'`. Con quella opzione ogni richiesta non coperta dalle regole viene negata subito, Claude viene avvisato e il lavoro continua; i dinieghi finiscono in `permission_denials`. Su macOS l'unico modo di svegliare il Mac a un'ora precisa richiede root. È un'altra conferma che "niente demone" è il confine giusto: se il Mac dorme, l'Esecuzione si salta e si recupera al risveglio.

## Ricerca

### Subagent di Claude Code: formato e capacità

**Dove vivono e chi vince** [1]. File Markdown con frontmatter YAML. In ordine di priorità: impostazioni gestite (org), flag `--agents` (JSON, solo sessione), `.claude/agents/` del progetto, `~/.claude/agents/` dell'utente, cartella `agents/` di un plugin (nome `plugin:agente`). A parità di nome vince la sorgente più alta. Le cartelle di progetto si cercano risalendo dalla `cwd` fino alla radice del repo; vince la più vicina. Due file con lo stesso `name` nella stessa cartella: se ne carica uno solo, "in base all'ordine di lettura del filesystem" e senza una regola documentata [1].

**Campi del frontmatter** [1]. Obbligatori solo `name` e `description`.

| Campo | Cosa fa |
|---|---|
| `name`, `description` | Identità; la descrizione dice a Claude quando delegare. Oltre 15.000 token di descrizioni in totale compare un avviso all'avvio. |
| `tools`, `disallowedTools` | Lista di strumenti ammessi o tolti. `Agent(worker, researcher)` limita quali subagent può lanciare; `mcp__server` toglie un intero server MCP. |
| `model` | `sonnet`, `opus`, `haiku`, `fable`, id completo o `inherit`. |
| `effort` | `low`…`max`, sovrascrive lo sforzo della sessione. |
| `permissionMode` | `default`, `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`, `plan`, `manual`. Vale solo se la sessione madre è in `default`, `dontAsk` o `plan` (vedi sotto). |
| `maxTurns` | Limite di turni; al limite il risultato è marcato come parziale. |
| `skills` | Skill caricate per intero all'avvio del subagent. |
| `mcpServers` | Server MCP solo per questo agente (in linea o per nome): non pesano sul contesto della sessione principale. |
| `hooks` | Hook del ciclo di vita dell'agente (ignorati per gli agenti dei plugin). |
| `memory` | `user`, `project` o `local`: cartella `agent-memory/<nome>/` con `MEMORY.md` (prime 200 righe o 25 KB nel prompt). |
| `background` | Sempre in background, anche se Claude chiede il primo piano. |
| `isolation` | `worktree`: l'agente lavora in un worktree git isolato. |
| `omitClaudeMd` | Salta i CLAUDE.md di utente e progetto. |
| `color`, `initialPrompt`, `experimental` | Colore in UI; primo turno automatico quando l'agente guida la sessione principale; opzioni avanzate (`cacheTtl`). |

**Cosa riceve un subagent** [1][2]. Un contesto nuovo: il suo prompt di sistema, il prompt di delega scritto da Claude, i CLAUDE.md (se non `omitClaudeMd`), lo stato git, le skill elencate, l'elenco degli altri agenti attivi. Non riceve la cronologia della conversazione madre, né il suo prompt di sistema, né la memoria automatica. Alla madre torna solo il messaggio finale. Dalla v2.1.210 Claude Code controlla quel messaggio e neutralizza i tag che imitano l'harness (`<system-reminder>`) e le righe `Human:`/`Assistant:` [2].

**Limiti** [2]. Annidamento fino a 3 livelli (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`). Al massimo 20 subagent insieme (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`), poi `Concurrent subagent limit reached`. `maxBudgetUsd` sulla `query()` conta anche la spesa dei subagent: al tetto rifiuta nuovi subagent, ferma quelli in background e chiude con `error_max_budget_usd`. Con Opus 5 e il preset `claude_code` il prompt di sistema dice a Claude di non delegare se non gli viene chiesto [2].

**Permessi dei subagent** [1][3].
- Se la sessione madre è in `bypassPermissions`, `acceptEdits` o `auto`, il subagent gira nella **stessa modalità** e il suo `permissionMode` viene ignorato.
- Se la madre è in `default`, `dontAsk` o `plan`, vale il `permissionMode` dell'agente, ma un `bypassPermissions` scritto nel file **non viene mai applicato** (da v2.1.267) [3].
- Le Regole di permesso della sessione valgono anche per i subagent.
- Un subagent in background che chiede un permesso fa comparire la richiesta **nella sessione principale, con il nome dell'agente** [1]. Nell'SDK la callback `canUseTool` riceve `agentID` (vedi [05](05-permessi.md)).
- In background il subagent ha solo un sottoinsieme di strumenti incorporati (Read, Grep, Glob, Bash, Edit, Write, WebFetch, …) più tutti gli MCP [1]. `AskUserQuestion` non esiste nei subagent [4].

**Nell'Agent SDK** [2][5].
- I file di `.claude/agents/` si caricano con `settingSources` che include `user`/`project` (il default). Nuovi file o modifiche si vedono in pochi secondi senza riavvio, tranne quando la cartella `agents/` nasce a sessione aperta: serve un riavvio [2].
- Opzione `agents` per definirli nel codice. Un agente definito così **vince** su un file con lo stesso nome [2]. Il tipo `AgentDefinition` di `sdk.d.ts` 0.3.282 **non ha** `isolation`, `hooks` né `color`: queste tre cose esistono solo nei file [5].
- `query.supportedAgents()` → `AgentInfo` (`name`, `description`, `model`): l'elenco per la UI senza leggere i file [5]. Sorgente e strumenti non ci sono: vanno letti dai file.
- `Options.agent`: fa guidare l'intera sessione da un agente (prompt, strumenti, modello) [5]. Un'Automazione può quindi "girare come" un agente dell'utente.
- Riconoscimento in streaming: `tool_use` con nome `Agent` (in `system/init` compare ancora come `Task`), messaggi interni con `parent_tool_use_id`; hook `SubagentStart`/`SubagentStop` con `agent_type`, `agent_id`, `last_assistant_message` [2][6].
- Ripresa: il risultato del tool contiene `agentId: <id>`; si riprende con `resume` della sessione. Explore e Plan non si possono riprendere [2].
- `/agents` nella CLI non apre più il wizard dalla v2.1.198: stampa un promemoria per chiedere a Claude o modificare i file [1]. **Nessuno ha più un editor di agenti in GUI.**

### Automazioni programmate: come fanno i concorrenti

| Prodotto | Dove gira | Serve il Mac acceso / app aperta | Esecuzioni perse | Permessi senza nessuno davanti | Isolamento |
|---|---|---|---|---|---|
| **Claude Code Desktop — attività locali** [7] | Sul Mac, nuova sessione per ogni esecuzione | Sì e sì. Controllo ogni minuto; ritardo fisso di qualche minuto per sparpagliare il traffico | Al riavvio o al risveglio: **una sola** esecuzione di recupero per l'orario perso più recente negli ultimi 7 giorni, le altre si scartano; notifica | Modalità per attività. In Manual l'esecuzione **resta ferma** finché non approvi; la sessione resta nella barra laterale. Consiglio ufficiale: "Run now" e "consenti sempre" su ogni prompt. Gli MCP `requiresUserInteraction` bloccano ogni volta | Worktree facoltativo per esecuzione |
| **Claude Code — Routines** [8] | Cloud Anthropic (o self-hosted), clone fresco | No | Non applicabile | Nessun selettore: **nessun prompt**, tutto autonomo; i connettori scrivono senza chiedere | Rami `claude/…`; push su altri rami controllato |
| **Claude Code — `/loop` e `CronCreate`** [9] | Nella sessione aperta | Sì, e la sessione deve restare aperta | **Nessun recupero**; scade dopo 7 giorni; max 50 per sessione | Eredita la sessione | Nessuno |
| **Codex (app ChatGPT)** [10] | Sul Mac per i progetti locali | Sì e sì | Non documentato | `approval_policy = "never"` quando ammesso; se l'admin lo vieta, torna alla modalità scelta. Sandbox: sola lettura, scrittura nel workspace, accesso completo | Locale o worktree; i worktree si accumulano e vanno archiviati a mano |
| **Cursor Automations** [11] | Cloud agent (sandbox) | No | — | Autonomo; può anche approvare PR se lo abiliti. Memoria tra esecuzioni della stessa automazione | Sandbox cloud |
| **Devin** [12] | VM cloud | No | — | Autonomo | VM; ricorrenza in RRULE UTC via API, la vecchia API `/schedules` risponde 403 dal 2026-09-24 |
| **Conductor** [13] | — | — | — | — | Nessuna automazione programmata nella documentazione: workspace in parallelo, cloud e API |

**Cosa ne esce.**
1. **Il cloud è autonomo per scelta**: Routines, Cursor, Devin non chiedono mai. La sicurezza viene dall'ambiente usa e getta.
2. **In locale nessuno ha risolto l'assenza dell'utente.** Claude Desktop si ferma; Codex usa "never" e affida tutto alla sandbox.
3. **Il recupero di Claude Desktop è il modello giusto** (uno solo, il più recente, con notifica) e la documentazione avverte che un'attività delle 9 può partire alle 23 [7].
4. **Tutti trattano l'esecuzione come una sessione normale** in una sezione "Programmate" o "Scheduled" (inbox con non letti in Codex [10]).

### Lamentele ricorrenti (issue di anthropics/claude-code)

- **"Consenti sempre" ignorato**: nelle attività programmate i prompt ricompaiono a ogni esecuzione (#47180, aperta, 38 commenti) [14]. Simile: `defaultMode` ignorato, attività che partono in Manual (#86907) [15].
- **Stalli senza fine**: agenti in background bloccati su un permesso senza risposta, "nessun auto-deny, timeout o watchdog", 55 minuti di stallo silenzioso (#78487) [16]. Chiamate MCP che non tornano mai nelle sessioni programmate (#95428) [17].
- **Il classificatore auto rifiuta azioni autorizzate** dal proprietario nell'attività, senza un "consenti" per attività (#98287) [18].
- **Modello del progetto ignorato**: le attività girano sul modello di default invece di quello di `settings.json` (#97875) [19].
- **Esecuzioni inutili**: richiesta di saltare l'esecuzione quando un controllo economico trova che non c'è niente da fare (#96635) [20].
- **Subagent**: richieste di permesso dei subagent invisibili su web o mobile, sessione appesa (#69482, #81237) [21][22].

### Programmare un lavoro su macOS con l'app aperta

| Strumento | Cosa fa | Uso per Bubo |
|---|---|---|
| `NSBackgroundActivityScheduler` | Lavoro **differibile**: il sistema sceglie il momento in base a energia, calore e CPU; `tolerance` di default = metà dell'intervallo; si usa per salvataggi, backup, attività da 10 minuti in su [23][24]. | **Non adatto** a "alle 9:00". Utile solo per la manutenzione (pulizia dei worktree delle Automazioni). |
| Timer sull'ora del calendario + ricalcolo | Un timer per il prossimo orario, ricalcolato quando serve. | Scelta per l'orario. Si ricalcola su `NSWorkspace.didWakeNotification` [25], su `NSSystemClockDidChange` (ora cambiata a mano) [26] e al cambio di fuso. |
| App Nap | Un'app non in primo piano subisce il **rallentamento dei timer**. Ne è esclusa se tiene un'asserzione `NSProcessInfo` o IOKit [27]. | Durante un'Esecuzione: `ProcessInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled])`. |
| `NSWorkspace.willSleepNotification` | Arriva prima del sonno; si può ritardarlo **al massimo 30 s** [28]. | Salvare lo stato e segnare l'Esecuzione come interrotta. |
| `IOPMAssertionCreateWithName` | Impedisce il sonno per inattività; "nessun privilegio speciale" [29]. | Interruttore facoltativo "Tieni sveglio il Mac" (come in Claude Desktop [7]). Chiudere il coperchio lo fa dormire comunque. |
| `IOPMSchedulePowerEvent` | Sveglia o accende il Mac a un'ora precisa. **"Must be called as root."** [30] | Fuori confine: servirebbe un helper privilegiato, cioè un demone. |
| `SMAppService.mainApp` | Registra l'app come elemento di login (macOS 13+) [31]. Può restare in stato `requiresApproval` finché l'utente non agisce in Impostazioni di Sistema, che può anche revocarlo [32]. | "Apri Bubo al login" facoltativo: rende "solo con Bubo aperto" quasi sempre vero, senza demone. |

### Permessi senza nessuno davanti: cosa offre l'SDK

| Leva | Comportamento | Adatta alle Automazioni? |
|---|---|---|
| `canUseTool` normale | Può restare in attesa **senza limite** [4]. | Sì, ma solo con una scadenza decisa da Bubo: altrimenti è lo stallo di #78487. |
| `permissionPrompts: 'none'` (v2.1.259+) | Nessuno risponde. Modalità, classificatore auto, regole e hook decidono ancora. Il resto è **negato subito**, Claude sa che non c'è chi approva e non riprova. `AskUserQuestion` sparisce. Dinieghi in `result.permission_denials` [5][33]. | **Sì**: è il comportamento "nessuno davanti" pulito. |
| `permissionMode: 'dontAsk'` | Tutto ciò che chiederebbe è negato; `canUseTool` mai chiamato [3]. | Sì per le Automazioni in sola lettura con strumenti fissati. |
| `auto` | Il classificatore approva o nega. Nell'SDK una rimozione su percorso critico è negata senza chiedere; senza host, dopo 3 blocchi di fila o 20 totali l'azione non parte e il lavoro continua [34]. | Sì, dentro il worktree: coincide con la **Modalità autonoma** fino al livello 3. |
| Hook `PreToolUse` → `defer` | Ferma il processo con `tool_deferred`; si riprende con `--resume`. Solo in `-p`/SDK, e **solo se nel turno c'è una sola chiamata a strumento**: con più chiamate `defer` viene ignorato [6]. | **No** come base: inaffidabile con chiamate parallele. |
| Hook `PermissionRequest` | Per mandare notifiche mentre una sessione aspetta [4]. | Sì, per la notifica. |

Il tipo `AgentDefinition.permissionMode` segue le stesse regole di eredità viste sopra: in un'Automazione in `auto` tutti i subagent girano in `auto` [3].

## Il meglio da battere

Il riferimento è **Claude Code Desktop**: fa già Automazioni locali con recupero e worktree. Bubo lo batte dove Desktop si ferma o dimentica. Criteri candidati usciti dalla ricerca (quelli decisi sono nella Specifica):

1. **Zero stalli.** Un'Automazione non resta mai ferma in attesa. Decidono le Regole del Progetto, poi le Regole dell'Automazione, poi la Modalità autonoma (fino al livello 3, possibile perché si lavora in un worktree). Tutto il resto viene negato subito con `permissionPrompts: 'none'` e Claude va avanti. Le azioni negate compaiono nel resoconto con "Consenti per questa Automazione" in 1 clic.
2. **"Consenti sempre" che resta.** Una regola approvata in un'Esecuzione vale per tutte le successive, anche nei worktree: 0 richieste ripetute (contro #47180).
3. **Livelli 4–5 mai da soli.** Un'azione di livello 4–5 non parte mai senza nessuno davanti: si nega e si mette nel resoconto. Nessun concorrente lo distingue.
4. **Recupero onesto.** All'apertura **e al risveglio**: una sola Esecuzione per l'orario perso più recente (7 giorni), notifica, con ora prevista e ora reale passate al prompt. Nessuna Esecuzione persa senza traccia nello storico.
5. **Niente rumore.** Se l'Esecuzione non trova niente, si archivia da sola con una riga (come Codex); il worktree senza modifiche si cancella. 0 worktree orfani dopo 7 giorni.
6. **Agenti visibili, non riscritti.** Elenco degli agenti con sorgente, modello, strumenti e conflitti di nome; il file si apre nell'editor dell'utente; un'Automazione può "girare come" un agente (`Options.agent`); ogni Richiesta di permesso di un subagent porta il suo nome. 0 file scritti in `.claude/agents/` senza un clic.
7. **Costo sotto controllo** e modello scelto rispettato (contro #97875).
8. **Sempre pronta senza demone.** "Apri Bubo al login" e "Tieni sveglio il Mac" facoltativi; prossimo orario ricalcolato dopo sonno, cambio d'ora e cambio di fuso, scarto sotto 1 minuto a Mac sveglio (Claude Desktop ha qualche minuto di ritardo voluto).

## Rischi e casi limite

- **Il recupero può partire a un'ora sbagliata** (alle 23 invece che alle 9) [7]. Il prompt deve ricevere l'ora prevista e quella reale.
- **Dormire durante l'Esecuzione**: con il coperchio chiuso il Mac dorme comunque. Al risveglio la Sessione va ripresa o segnata come interrotta, mai lasciata "in corso".
- **Regole di permesso che non valgono nel worktree**: in Claude Code le regole "consenti sempre" vanno nel `settings.local.json` del checkout principale anche dai worktree (v2.1.211, vedi [05](05-permessi.md)). Se Bubo non passa le Regole del Progetto alla Sessione dell'Esecuzione, si ripete #47180.
- **Worktree che si accumulano** con Automazioni frequenti (Codex lo documenta [10]).
- **Classificatore auto troppo severo** su azioni che l'utente ha autorizzato nell'Automazione (#98287) [18]: servono Regole di permesso **per Automazione**, non solo per Progetto.
- **Regole che coprono azioni di livello 4–5**: una regola `allow` scritta a mano o dalla CLI può coprire un'azione distruttiva; senza nessuno davanti non basta che Bubo non generi regole di quel livello.
- **Subagent in background** che chiedono permessi: in un'Automazione nessuno li vede. Con `permissionPrompts: 'none'` vengono negati come gli altri.
- **Nomi duplicati** tra `.claude/agents/` annidati o tra progetto e utente: vince uno solo, a volte senza regola [1]. Bubo deve mostrare quale.
- **Contesto**: più di 15.000 token di descrizioni degli agenti fanno scattare l'avviso [1].
- **Opus 5 delega poco** con il preset `claude_code` [2]: un'Automazione che deve usare un agente va lanciata con `Options.agent`, non sperando che Claude lo scelga.
- **Più Automazioni allo stesso orario**: Claude Desktop salta un'esecuzione se la precedente è ancora in corso o se altre stanno girando [7].
- **Creazione silenziosa**: un'Automazione nata da voce o da Comandi rapidi girerebbe poi senza nessuno davanti senza che l'utente abbia mai visto la scheda ([#140](https://github.com/mgiuditta/bubo/issues/140)).

## Mappa

Architettura comune in [INDEX.md](INDEX.md). Si appoggia sulle Sessioni in worktree (01), sulle Regole e sul Livello di rischio (05), su Attività e notifiche (06), sul router (10), sugli App Intents (09), sulla voce (08), sulla Board e sulle Bozze (17, [#132](https://github.com/mgiuditta/bubo/issues/132)) e sui Budget (18, [#135](https://github.com/mgiuditta/bubo/issues/135)).

### Agenti (deciso)

Fonte: [#136](https://github.com/mgiuditta/bubo/issues/136); finestra da [#140](https://github.com/mgiuditta/bubo/issues/140).

- **Solo subagent nativi** di Claude Code (`.claude/agents/` di progetto e utente, cartelle `agents/` dei plugin). Nessun formato di Bubo, nessuna opzione `agents` nel codice (vincerebbe sui file dell'utente e perderebbe `isolation`, `hooks`, `color`).
- **Finestra Agenti**: si apre dal menu Finestra e dalla Palette, senza scorciatoia. Progetto scelto in cima. Elenco da `supportedAgents()` (nome, descrizione, modello); sorgente (Progetto, utente, plugin), strumenti e file di origine letti dai file. I conflitti di nome si mostrano: quale file vince e quali sono coperti, anche i doppioni nella stessa cartella senza regola. Avviso oltre 15.000 token di descrizioni. "Apri nell'editor" apre il file nell'editor dell'utente (lo stesso di "apri nel tuo editor", feature 15).
- **Nuovo agente**: Progetto o utente, nome, descrizione → Bubo scrive un `.claude/agents/<nome>.md` minimo (`name`, `description` e un corpo vuoto da riempire) e lo apre nell'editor. È l'unico file che Bubo scrive in una cartella `agents/`, sempre dopo un clic. Niente editor dei campi in GUI. Nome già esistente in quella sorgente → il pulsante si disattiva e dice perché.
- **Richieste dei subagent**: ogni Richiesta di permesso con `agentID` mostra il nome dell'agente (da `SubagentStart`: `agent_id` → `agent_type`). Colore della Tinta invariato: il contenitore resta acromatico (ADR 0004).
- **Rilettura**: FSEvents sulle cartelle `agents/`; la finestra si aggiorna senza riavvio. Se la cartella `agents/` nasce a Sessione aperta, la finestra avvisa che le Sessioni già aperte non la vedono fino al riavvio della Conversazione [2].

### Automazioni (deciso)

Fonte: [#136](https://github.com/mgiuditta/bubo/issues/136), ingressi da [#140](https://github.com/mgiuditta/bubo/issues/140).

- **Cosa la definisce**: Progetto, richiesta (il testo del prompt), ripetizione, modello, agente facoltativo, Modalità autonoma.
  - **Ripetizione**: una volta, ogni ora, ogni giorno alle HH:MM, giorni feriali, un giorno della settimana. Niente espressioni cron. Ora locale del Mac.
  - **Modello**: il router (default) o un modello fisso. Con il router la scelta segue il Tipo di richiesta come in ogni Sessione (feature 10); con un modello fisso l'Esecuzione usa quello, mai il default (contro #97875).
  - **Agente**: "gira come" un agente dell'elenco, con `Options.agent`. Senza agente, la Sessione normale.
  - **Modalità autonoma**: accesa di default.
- **Sempre in worktree** (feature 01), un worktree nuovo per Esecuzione. Progetto non git: nessuna copia isolata, quindi niente Modalità autonoma e decidono solo le Regole; lo dice un avviso nella scheda alla creazione.
- **Dove si crea**: finestra Automazioni (menu Finestra e Palette, senza scorciatoia) o "Programma…" da una Bozza o da una Sessione, che precompila Progetto e richiesta.
- **A voce**: Bubo propone e non crea. La richiesta a voce apre la scheda precompilata (Progetto, richiesta, ripetizione, modello, agente); l'Automazione esiste solo dopo la conferma esplicita nella scheda.
- **App Intents v1**: solo "Esegui Automazione" (`AutomazioneEntity`, esegue subito, come [Avvia ora]). Niente "Crea Automazione": con Comandi rapidi sarebbe una creazione silenziosa.
- **Gestione**: Pausa/Riprendi, Modifica (vale dalla prossima Esecuzione), [Avvia ora], Elimina con conferma. Le Sessioni già nate restano; le Regole "in questa Automazione" si cancellano con lei. In pausa non partono Esecuzioni né recuperi, e lo storico non segna orari persi.

### Permessi senza nessuno davanti (deciso)

- Ogni Esecuzione gira con `permissionPrompts: 'none'`: nessuna Richiesta di permesso, nessuna attesa.
- **Ordine**: Regole del Progetto → Regole dell'Automazione → Modalità autonoma (fino al livello 3) → diniego.
  - **Regole del Progetto**: quelle di `settings.local.json` e `settings.json` del checkout principale, lette con `projectConfigRoot` = checkout principale anche se la `cwd` è il worktree (architettura comune; rischio del worktree in [05](05-permessi.md)).
  - **Regole dell'Automazione**: terzo ambito della Regola di permesso, "in questa Automazione". Le salva Bubo con l'Automazione, non nei file di Claude Code; a ogni Esecuzione passano alla `query()` come regole `allow` di sessione (destinazione `cliArg`). Non valgono in nessun'altra Sessione.
  - **Modalità autonoma**: `permissionMode: 'auto'` nel worktree. I subagent girano in `auto` anche se il loro file dice altro [3].
- **Livelli 4–5 sempre negati**: un hook `PreToolUse` chiama `Permissions/RiskClassifier` e nega ogni azione di livello 4–5, prima delle regole. Così nemmeno una regola `allow` scritta a mano li fa passare. Ogni diniego va nel resoconto.
- **Resoconto dei dinieghi**: unione di `result.permission_denials` e dei dinieghi dell'hook, con strumento, comando o percorso, livello, agente se viene da un subagent. Per i livelli 1–3: "Consenti per questa Automazione" in 1 clic, che crea la Regola con il pattern dei `suggestions` dell'SDK così come arrivano (stessa regola di [05](05-permessi.md): mai pattern più larghi). Per i livelli 4–5 nessun pulsante: l'utente può riprendere la Sessione e fare l'azione a mano.

### Esecuzione, risultati e recupero (deciso)

- **Esecuzione** = uno scatto di un'Automazione. Esiti:
  - **Fatta**: è partita e ha lasciato modifiche o un messaggio.
  - **Senza modifiche**: è partita, nessuna modifica nel worktree e nessun messaggio utile.
  - **Saltata**, con il motivo: budget esaurito, sovrapposta, Mac spento o Bubo chiuso.
  - **Interrotta**: il Mac si è addormentato o Bubo si è chiuso durante il lavoro.
- **"Messaggio utile"**: il prompt dell'Esecuzione chiede a Claude di rispondere con una frase fissa ("Niente da segnalare.") quando non c'è niente da fare (#96635 [20]). Nessuna modifica, 0 dinieghi e quella frase come messaggio finale → Senza modifiche. Qualunque diniego rende l'Esecuzione Fatta, perché l'utente deve vederlo.
- **Prompt dell'Esecuzione**: la richiesta dell'Automazione più una riga di contesto con nome dell'Automazione, ora prevista e ora reale di partenza.
- **Risultato = Sessione**: ogni Esecuzione partita crea una Sessione con il segno "Automazione" (nome + ora) nella Vista delle Sessioni. A fine lavoro la Sessione è Ferma in Aperta, quindi sulla Board sta in **Da guardare** ([#132](https://github.com/mgiuditta/bubo/issues/132)); notifica (feature 06) con esito e numero di dinieghi.
- **Senza modifiche**: la Sessione si archivia da sola, il worktree si cancella subito, resta una riga nello storico. Niente notifica.
- **Finestra Automazioni**: per ogni Automazione prossimo orario, ultimo esito e storico delle Esecuzioni (una riga per Esecuzione, anche Saltata, con link alla Sessione se è partita).
- **Sovrapposizioni**: la stessa Automazione ancora in corso all'orario successivo → Saltata (sovrapposta). Automazioni diverse allo stesso orario partono insieme; nessuna coda.
- **Budget** ([#135](https://github.com/mgiuditta/bubo/issues/135)): se un Budget che vale per l'Esecuzione (fornitore, Progetto o totale) è già al 100%, l'Esecuzione non parte: Saltata (budget esaurito) + notifica con [Avvia ora], che vale da conferma. Se il Budget si esaurisce durante, la Sessione si ferma come ogni Sessione e aspetta le scelte della feature 18 (è Attende te per il Budget, non una Richiesta di permesso). Nessun override automatico. Anche "Esegui Automazione" da App Intent a Budget esaurito finisce in Saltata con [Avvia ora]: l'intent non vale da conferma.
- **Recupero**: all'apertura di Bubo e al risveglio. Per ogni Automazione attiva, gli orari persi degli ultimi 7 giorni diventano righe Saltata nello storico; si recupera con una sola Esecuzione solo l'orario perso più recente, con notifica. Mai più di un recupero per Automazione.
- **Orario**: un timer per il prossimo orario di tutte le Automazioni, ricalcolato su risveglio (`didWakeNotification`), ora cambiata (`NSSystemClockDidChange`), cambio di fuso e ogni modifica di un'Automazione. Niente `NSBackgroundActivityScheduler` per gli orari.

### Sonno e prontezza (deciso)

- **Durante un'Esecuzione**, sempre: `ProcessInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled])` contro App Nap e sonno per inattività; si rilascia a fine Esecuzione.
- **Facoltativi, spenti di default, proposti alla prima Automazione**:
  - "Apri Bubo al login" (`SMAppService.mainApp`; se lo stato è `requiresApproval`, un pulsante apre Impostazioni di Sistema).
  - "Tieni sveglio il Mac quando c'è un'Automazione nelle prossime 2 ore" (asserzione `IOPMAssertionCreateWithName` presa e rilasciata dal timer). Il coperchio chiuso lo fa dormire comunque, e la scheda lo dice.
- **Sonno durante un'Esecuzione**: su `willSleepNotification` si salva lo stato; al risveglio l'Esecuzione è Interrotta con [Riprendi] (ripresa della Conversazione dell'agente), mai "in corso".
- **Svegliare il Mac** a un'ora precisa è fuori portata (root, [30]); le Automazioni a Bubo chiuso pure (mappa [#125](https://github.com/mgiuditta/bubo/issues/125)).

### Moduli

Architettura comune in [INDEX.md](INDEX.md). Moduli nuovi:

- `Agents/AgentCatalog`: `supportedAgents()` + lettura dei frontmatter dalle cartelle `agents/` (sorgente, strumenti, file), calcolo dei conflitti con la precedenza di [1], stima dei token delle descrizioni, FSEvents.
- `Agents/AgentFileWriter`: scrive il file minimo del Nuovo agente, solo da un clic; rifiuta nomi già presenti.
- `Agents/AgentsWindow`: finestra Agenti (SwiftUI), Apri nell'editor, Nuovo agente.
- `Automations/Automation` e `Automations/AutomationStore`: definizione, Regole dell'Automazione, storico delle Esecuzioni; persistenza locale accanto a `Sessions/SessionStore`.
- `Automations/Recurrence`: le cinque ripetizioni, prossimo orario in ora locale, orari persi in una finestra di 7 giorni. Codice puro, testabile.
- `Automations/AutomationScheduler`: timer unico, ricalcolo su risveglio, ora, fuso e modifiche; recupero all'apertura e al risveglio; sovrapposizioni; controllo del Budget prima della partenza con `BudgetGuard` (18).
- `Automations/ExecutionRunner`: crea la Sessione nel worktree (01), prepara le opzioni (`permissionPrompts: 'none'`, `permissionMode`, `agent`, modello, Regole dell'Automazione), prende e rilascia l'asserzione, calcola l'esito, archivia e cancella il worktree se Senza modifiche.
- `Automations/UnattendedGate`: hook `PreToolUse` con `RiskClassifier` (livelli 4–5 negati) e raccolta dei dinieghi in un resoconto.
- `Automations/Readiness`: "Apri Bubo al login" (`SMAppService`) e "Tieni sveglio il Mac" (IOKit), sonno e risveglio.
- `Automations/WorktreeSweeper`: manutenzione con `NSBackgroundActivityScheduler`: cancella i worktree di Esecuzioni Senza modifiche rimasti dopo un arresto anomalo.
- `Automations/AutomationsWindow` e `Automations/AutomationSheet`: finestra con elenco e storico; scheda di creazione e modifica, la stessa che apre la voce.
- `HUD/DenialReport`: resoconto dei dinieghi nella Sessione, con "Consenti per questa Automazione".
- `System/Intents/RunAutomationIntent` + `AutomazioneEntity` (feature 09).
- Riuso: `Sessions/` e `WorktreeManager` (01), `Permissions/RiskClassifier` e `RuleStore` (05), `System/Notifier` e Attività (06), `Router/ModelRouter` (10), `BudgetGuard` (18), Board e Bozze (17), `Intake/` per la voce (08, 09).

### Flusso

1. Creazione: finestra Automazioni, "Programma…" o voce → `AutomationSheet` → conferma → `AutomationStore` → `AutomationScheduler` ricalcola il timer.
2. Scatto: timer → stessa Automazione in corso? Saltata (sovrapposta) → Budget al 100%? Saltata + notifica [Avvia ora] → `ExecutionRunner`: worktree, Sessione con segno "Automazione", asserzione, `query()` con `permissionPrompts: 'none'`, `UnattendedGate`.
3. Lavoro: ogni strumento → hook (livello 4–5 negato) → Regole del Progetto → Regole dell'Automazione → Modalità autonoma → diniego nel resoconto. Nessuna attesa.
4. Fine: esito → Fatta: Da guardare + notifica con dinieghi; Senza modifiche: archiviata, worktree cancellato, riga nello storico.
5. Apertura o risveglio: orari persi → righe Saltata → un recupero per Automazione (il più recente, 7 giorni) → notifica.
6. Resoconto: "Consenti per questa Automazione" → Regola salvata → vale dalla prossima Esecuzione.

### Casi limite

- **Recupero a un'ora strana** (quello delle 9 parte alle 23): il prompt riceve ora prevista e reale; l'agente decide se ha ancora senso.
- **Mac addormentato durante**: Interrotta con [Riprendi], asserzione rilasciata, worktree tenuto.
- **Bubo chiuso durante**: alla riapertura l'Esecuzione è Interrotta, mai "in corso".
- **Cambio di fuso e ora legale**: "ogni giorno alle 9" resta alle 9 dell'ora locale nuova; il timer si ricalcola.
- **Automazione "una volta" persa**: si recupera se entro 7 giorni; poi l'Automazione resta nell'elenco, senza prossimo orario.
- **Agente sparito** (file cancellato o rinominato): l'Esecuzione non parte senza agente, perché "girare come" fa parte della richiesta. L'Automazione va in pausa e la finestra lo segnala.
- **Progetto non git**: nessuna Modalità autonoma, nessun worktree da cancellare. Le Esecuzioni lavorano sulla cartella del Progetto, dove al massimo una Sessione lavora alla volta (CONTEXT.md): se un'altra Sessione ci sta già lavorando, l'Esecuzione è Saltata (sovrapposta).
- **Progetto sparito** (cartella spostata o disco esterno assente): Automazione in pausa con avviso.
- **Regola `allow` troppo larga** scritta a mano che copre un livello 4: l'hook nega comunque.
- **Subagent che chiede un permesso**: negato come gli altri, nel resoconto con il nome dell'agente.
- **MCP che non torna mai** (#95428 [17]): l'Esecuzione è una Sessione come le altre e si può fermare; nessun timeout nuovo in v1.
- **Budget esaurito durante**: Attende te per il Budget; non conta come Richiesta di permesso ai fini del criterio 1.
- **Modifica di un'Automazione a Esecuzione in corso**: vale dalla prossima.

### Test

- `Recurrence`: tabella di ripetizioni × istanti (compreso cambio d'ora legale e di fuso) → prossimo orario e orari persi attesi.
- `AutomationScheduler` con orologio finto: sonno di 3 giorni → righe Saltata per ogni orario perso, un solo recupero, partito entro 5 s dal risveglio simulato.
- Scarto dall'orario misurato su Mac vero: 100 scatti, anche dopo sonno, cambio d'ora e di fuso, tutti sotto 1 minuto.
- Esecuzione con un comando che chiederebbe un permesso: fine del turno senza attesa, diniego nel resoconto. Poi "Consenti per questa Automazione" → nella successiva, in un worktree nuovo, 0 dinieghi per quel comando.
- Tabella di azioni di livello 4–5 (anche coperte da una regola `allow` scritta a mano): 0 eseguite, 100% nel resoconto.
- Esecuzione Senza modifiche: Sessione archiviata, worktree assente; `git worktree list` dopo 7 giorni di Esecuzioni finte: 0 orfani.
- Budget al 100%: Saltata, notifica; [Avvia ora] parte; "Esegui Automazione" da App Intent non parte.
- Monitor di scrittura su `.claude/agents/`: 0 file senza clic; set di cartelle con nomi doppi (progetto/utente, annidati, stessa cartella): 100% dei conflitti mostrati.
- Voce e App Intents: nessuna Automazione creata senza conferma nella scheda; "Esegui Automazione" presente in Spotlight e Comandi rapidi.
- Accessibilità: audit SwiftUI e AppKit delle finestre Agenti e Automazioni e della scheda.

### Ordine di costruzione

1. **Esecuzione minima senza nessuno davanti**: `Automation`, `AutomationStore`, `ExecutionRunner`, `UnattendedGate`, [Avvia ora] dalla finestra Automazioni; Sessione in worktree con segno "Automazione", resoconto dei dinieghi e Regole "in questa Automazione". Dipende da ponte agente ([#66](https://github.com/mgiuditta/bubo/issues/66)), 01, 05, 06, 10.
2. **Orario, esiti e recupero**: `Recurrence`, `AutomationScheduler`, Senza modifiche e pulizia dei worktree, sovrapposte, recupero all'apertura e al risveglio, asserzioni, Interrotta, "Apri Bubo al login" e "Tieni sveglio". Dipende da 1.
3. **Risultati nella Board e Budget**: Da guardare e notifica con esito, storico nella finestra, Saltata per budget esaurito con [Avvia ora]. Dipende da 2, 17, 18.
4. **Agenti**: `AgentCatalog`, finestra Agenti, Nuovo agente, nome dell'agente sulle Richieste, "gira come" nella scheda. Indipendente da 1–3 per la finestra (dopo 04 e 05); il "gira come" dopo 1.
5. **Ingressi**: "Programma…" da Bozza e Sessione (17), scheda precompilata a voce (08), App Intent "Esegui Automazione" (09), voci nel menu Finestra e nella Palette ([#140](https://github.com/mgiuditta/bubo/issues/140)). Dipende da 2.

## Specifica "migliore di"

Miglior concorrente: **Claude Code Desktop** (attività locali con recupero e worktree), che però resta fermo quando nessuno risponde a un permesso, perde il "consenti sempre" tra un'esecuzione e l'altra e ritarda di qualche minuto; nessuno ha più un editor o un elenco di agenti in GUI.
Bubo li supera così:

1. **Zero stalli**: **0 Esecuzioni** in attesa di una Richiesta di permesso oltre la fine del turno.
2. **Regole che restano**: una Regola "in questa Automazione" approvata una volta → **0 richieste o dinieghi ripetuti** per la stessa azione nelle Esecuzioni successive, anche in worktree nuovi.
3. **Livelli 4–5 mai da soli**: **0 azioni** di livello 4–5 eseguite senza utente; **100%** riportate nel resoconto.
4. **Recupero onesto**: ogni orario perso ha **una riga** nello storico; **al massimo 1 recupero** per Automazione, partito **entro 5 s** dall'apertura o dal risveglio.
5. **Niente rumore**: **0 worktree orfani** di Esecuzioni Senza modifiche dopo 7 giorni.
6. **Agenti rispettati**: **0 file** in `.claude/agents/` scritti senza un clic; conflitti di nome mostrati al **100%**.
7. **Puntuale**: scarto dall'orario **< 1 minuto** a Mac sveglio, anche dopo sonno, cambio d'ora e cambio di fuso.
8. **Budget rispettato**: **0 Esecuzioni** avviate con un Budget al 100% senza [Avvia ora].
9. **Nessuna creazione silenziosa**: **0 Automazioni** create senza conferma esplicita nella scheda, né da voce né da App Intent.
10. **Raggiungibile da fuori**: "Esegui Automazione" compare in Spotlight e in Comandi rapidi.

## Fonti

1. Claude Code, "Create custom subagents" — https://code.claude.com/docs/en/sub-agents
2. Agent SDK, "Subagents in the SDK" — https://code.claude.com/docs/en/agent-sdk/subagents
3. Agent SDK, "Configure permissions" — https://code.claude.com/docs/en/agent-sdk/permissions
4. Agent SDK, "Handle approvals and user input" — https://code.claude.com/docs/en/agent-sdk/user-input
5. `@anthropic-ai/claude-agent-sdk` 0.3.282, `sdk.d.ts` (`AgentDefinition`, `AgentInfo`, `supportedAgents()`, `Options.agent`, `permissionPrompts`, `permission_denials`, `deferred_tool_use`) — https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk
6. Claude Code, "Hooks reference" (Defer a tool call for later; SubagentStart/SubagentStop) — https://code.claude.com/docs/en/hooks
7. Claude Code, "Schedule recurring tasks in Claude Code Desktop" — https://code.claude.com/docs/en/desktop-scheduled-tasks
8. Claude Code, "Automate work with routines" — https://code.claude.com/docs/en/routines
9. Claude Code, "Run prompts on a schedule" — https://code.claude.com/docs/en/scheduled-tasks
10. OpenAI Codex, "Automations" — https://developers.openai.com/codex/app/automations (reindirizza a https://learn.chatgpt.com/docs/automations?surface=app)
11. Cursor, "Automations" — https://cursor.com/docs/cloud-agent/automations ; changelog — https://cursor.com/changelog/03-05-26
12. Devin API, "Common flows" (automazioni con trigger `schedule:recurring`) — https://docs.devin.ai/api-reference/common-flows
13. Conductor, indice della documentazione — https://www.conductor.build/llms.txt
14. anthropics/claude-code #47180, "Cowork scheduled tasks ignore 'Always allow' folder/tool permissions" — https://github.com/anthropics/claude-code/issues/47180
15. anthropics/claude-code #86907 — https://github.com/anthropics/claude-code/issues/86907
16. anthropics/claude-code #78487, "Workflow/background-spawned agents block indefinitely on unanswered permission prompts" — https://github.com/anthropics/claude-code/issues/78487
17. anthropics/claude-code #95428 — https://github.com/anthropics/claude-code/issues/95428
18. anthropics/claude-code #98287 — https://github.com/anthropics/claude-code/issues/98287
19. anthropics/claude-code #97875 — https://github.com/anthropics/claude-code/issues/97875
20. anthropics/claude-code #96635, "Scheduled tasks: skip the run when a cheap check finds nothing to do" — https://github.com/anthropics/claude-code/issues/96635
21. anthropics/claude-code #69482 — https://github.com/anthropics/claude-code/issues/69482
22. anthropics/claude-code #81237 — https://github.com/anthropics/claude-code/issues/81237
23. Apple, `NSBackgroundActivityScheduler` — https://developer.apple.com/documentation/foundation/nsbackgroundactivityscheduler
24. Apple, Energy Efficiency Guide for Mac Apps, "Schedule Background Activity" — https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/SchedulingBackgroundActivity.html
25. Apple, `NSWorkspace.didWakeNotification` — https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification
26. Apple, `NSSystemClockDidChange` — https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/nssystemclockdidchange
27. Apple, Energy Efficiency Guide for Mac Apps, "App Nap" — https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html
28. Apple, `NSWorkspace.willSleepNotification` — https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification
29. Apple, `IOPMAssertionCreateWithName` — https://developer.apple.com/documentation/iokit/1557134-iopmassertioncreatewithname
30. macOS SDK, `IOKit/pwr_mgt/IOPMLib.h`, `IOPMSchedulePowerEvent` ("Must be called as root") — https://developer.apple.com/documentation/iokit/1557070-iopmschedulepowerevent
31. Apple, `SMAppService.mainApp` — https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp
32. Apple, `SMAppService.Status.requiresApproval` — https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval
33. Claude Code, "Run Claude Code programmatically → Turn off permission prompts in unattended runs" — https://code.claude.com/docs/en/headless#turn-off-permission-prompts-in-unattended-runs
34. Claude Code, "Permission modes" (When auto mode falls back; critical paths) — https://code.claude.com/docs/en/permission-modes
