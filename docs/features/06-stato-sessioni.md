# 06 — Stato delle sessioni, notifiche native, badge nel Dock

Ticket: [#17](https://github.com/mgiuditta/bubo/issues/17) · Mappa: [#11](https://github.com/mgiuditta/bubo/issues/11) · Ricerca del 2026-09-29.

Domanda: come mostrano i concorrenti lo stato di ogni sessione (lavora, attende te, ferma), con notifiche native e badge nel Dock? Da quali eventi lo ricavano? Quali API Apple servono? Cosa lamentano gli utenti?

## Ricerca

### Sintesi

- Tutti convergono su **tre stati visibili**: *lavora*, *attende te*, *finita/ferma*. Chi ne mostra di più li aggiunge sopra (fallita, in revisione, fermata a mano).
- Il problema più sentito **non è la notifica mancante, è il rumore**: una notifica a ogni fine turno, anche quando la sessione continua da sola (subagent, task in background).
- Il secondo problema è la **confusione tra "finita" e "attende una risposta"**: con i soli hook non si distinguono bene.
- Quasi nessuno permette di **approvare direttamente dalla notifica**. Si clicca, si apre l'app, si cerca la sessione, si approva.

### App desktop ufficiale di Claude Code (e agent view della CLI)

Come lo fa:
- Sidebar con filtro delle sessioni per stato, progetto e ambiente. ([desktop](https://code.claude.com/docs/en/desktop))
- Notifica di sistema quando una sessione **finisce un task e non la stai guardando**. Notifica anche quando la CI di una PR finisce. ([desktop](https://code.claude.com/docs/en/desktop))
- Nei **Progetti** c'è il pannello Overview con gruppi: *Ready for review*, *Waiting on you* (risposta, approvazione o errore), *Working*, *Landing*, *Idle*, *Resolved*. Il pulsante Overview mostra un **pallino** quando un thread ti aspetta. Notifica quando Claude scrive, quando un thread va in errore o ha bisogno di te; la notifica a ogni fine turno è opzionale, per progetto. ([projects](https://code.claude.com/docs/en/claude-projects))
- L'**agent view** della CLI (`claude agents`) è il riferimento più preciso sugli stati: *Working* (animato), *Needs input* (giallo), *Idle* (attenuato), *Completed* (verde), *Failed* (rosso), *Stopped* (grigio). In più la forma dell'icona dice se il processo è vivo, uscito o in pausa tra due iterazioni di `/loop`. ([agent view](https://code.claude.com/docs/en/agent-view))
- Ogni riga ha un **riassunto di una riga** fatto da un modello Haiku: cosa fa, cosa chiede, cosa ha prodotto. Si aggiorna al massimo ogni 15 s durante il lavoro. ([agent view](https://code.claude.com/docs/en/agent-view))
- Contatore "← 2 agents" nel prompt e titolo del tab "2 awaiting input". Il contatore si aggiorna circa ogni 10 s. ([agent view](https://code.claude.com/docs/en/agent-view))
- La CLI salta la notifica desktop se stai scrivendo o se il terminale ha il focus (presence check). ([env vars](https://code.claude.com/docs/en/env-vars))
- Dispatch: push sul telefono quando la sessione finisce o chiede un'approvazione. ([desktop](https://code.claude.com/docs/en/desktop))

Cosa piace: stati chiari e colorati; riassunto per riga; "Waiting on you" come gruppo in cima.

Cosa lamentano:
- Notifica (con suono) **a ogni fine risposta**, anche intermedia, mentre la sessione lavora ancora. Unica soluzione oggi: spegnere tutto. ([#87351](https://github.com/anthropics/claude-code/issues/87351))
- `idle_prompt` suona circa **60 s** dopo la fine del turno, anche se ci sono subagent ancora in esecuzione. ([#93672](https://github.com/anthropics/claude-code/issues/93672))
- Nessun hook distingue "turno finito" da "turno finito con una domanda per te" (`AskUserQuestion`). ([#93872](https://github.com/anthropics/claude-code/issues/93872))
- La finestra dell'app desktop **ruba il focus** quando una sessione ha bisogno di te. Gli utenti chiedono solo badge, suono o banner. ([#94460](https://github.com/anthropics/claude-code/issues/94460))
- Richiesta storica di un'opzione per spegnere le notifiche. ([#12046](https://github.com/anthropics/claude-code/issues/12046))

Cosa manca: approvazione dalla notifica (non documentata); filtro per motivo della notifica; badge nel Dock (non documentato).

### Conductor

Come lo fa (dal [changelog](https://www.conductor.build/changelog.md) e dall'[aggregato di releases.sh](https://releases.sh/conductor/conductor-changelog.md)):
- Notifiche quando Claude fa una domanda o aspetta la revisione di un piano (0.28.7, gennaio 2026).
- **Suoni di fine lavoro** scelti dall'utente, anche "novelty" (0.52.0 e seguenti). ([0.52.0](https://www.conductor.build/changelog/0.52.0-sounds-colors))
- Workspace organizzati per stato: backlog, in corso, in revisione, fatto. ([0.35.0](https://www.conductor.build/changelog/0.35.0-workspace-status))
- **Pallino "non letto"** sulle tab delle sessioni, "segna come non letto", navigazione "prossimo non letto".
- Clic sulla notifica apre la sessione che l'ha generata; la notifica mostra il nome del workspace, non del branch.

Cosa lamentano (dalle correzioni nel changelog): sessioni rimaste "working" dopo uno stop; notifiche che aprivano la pagina sbagliata; icone di stato tagliate o spinner spariti con sidebar nascosta.

Cosa manca: badge nel Dock e azioni nella notifica non documentati.

### Nimbalyst (ex Crystal)

Come lo fa (dalle [release su GitHub](https://github.com/nimbalyst/nimbalyst/releases)):
- Sessioni che aspettano una domanda o un permesso appaiono come **"in attesa del tuo input"**, non più come "in esecuzione".
- **Isola nella barra dei menu** con colori: verde per le sessioni in corso, blu per le non lette. Pulsante "segna tutte come lette".
- **Icona diversa per tipo di notifica**: finito, domanda, approvazione, messaggio di un collega.
- Sessioni in background completate restano "non lette" finché non le apri.
- Su iPhone: **Live Activity** con le sessioni ordinate per **quanto aspettano te**.
- Push al telefono se sei lontano; sessione bloccata o in errore raggiunge anche il computer.

Cosa lamentano: la domanda restava "in attesa" dopo che l'utente aveva scritto altro; clic sulla notifica di una sessione in worktree dava "sessione non trovata"; gli stati "risposta richiesta" non generavano push iOS ([#1006](https://github.com/nimbalyst/nimbalyst/issues/1006)); un task in background che finisce può distruggere una domanda in attesa ([#1557](https://github.com/nimbalyst/nimbalyst/issues/1557)); stato "idle" vecchio dopo che il figlio riparte ([#1245](https://github.com/nimbalyst/nimbalyst/issues/1245)).

### Superset

Come lo fa ([docs](https://docs.superset.sh/agent-status)):
- Installa **hook e wrapper** nella config di ogni agente; gli hook riportano avvio, fine, attesa di input. Funziona solo per agenti lanciati da Superset.
- Notifica quando l'agente finisce o si ferma per te; suoni configurabili.
- **Badge nel Dock** per i workspace che richiedono attenzione. Nota importante: *macOS mostra il badge solo se l'app ha il permesso di notifica*.

Cosa lamentano:
- **Nessun banner se Superset è in primo piano**, anche se la notifica viene da un pannello che non stai guardando. Causa: notifica Electron semplice, senza presentazione in primo piano. ([#7141](https://github.com/superset-sh/superset/issues/7141))
- Una notifica **ogni volta che finisce un subagent**, non quando finisce il task. ([#6929](https://github.com/superset-sh/superset/issues/6929), [#6641](https://github.com/superset-sh/superset/issues/6641))
- Spam di notifiche con le Agent Teams di Claude Code. ([#1785](https://github.com/superset-sh/superset/issues/1785))
- "Task complete" a ogni turno con Cursor Agent. ([#5259](https://github.com/superset-sh/superset/issues/5259))
- Richieste chiuse per inattività: badge + rimbalzo nel Dock quando l'agente aspetta, suono per le approvazioni, volume regolabile. ([#5601](https://github.com/superset-sh/superset/issues/5601))

### CodeAgentSwarm

- Notifica quando Claude **finisce** o **aspetta** (conferma, scelta tra opzioni, più contesto). Stato visivo di ogni terminale: lavora, finito, bloccato. ([guida ufficiale](https://github.com/arturogj92/codeagentswarm-landing/blob/main/content/guides/en/codeagentswarm-notifications.ts))
- Tesi del prodotto: "quando torni, Claude ti aspettava da 10 minuti". Nessun numero misurato.

### opcode (ex Claudia)

- Nel codice non c'è invio di notifiche di sistema; le issue sulle notifiche riguardano solo i limiti d'uso ([#208](https://github.com/winfunc/opcode/issues/208)). Non è un riferimento per questa feature.

### Sculptor, ClaudeGUI, Agentic Stack Desktop

- Nessuna fonte primaria trovata su stato, notifiche o badge. Da verificare a mano se serve.

### Strumenti di contorno (utile come segnale di domanda)

- App da barra dei menu nate solo per questo problema: Claude Code Notifier, Nudge, Standby. Promettono: notifica nativa quando Claude aspetta, **silenzio se il terminale è in primo piano**, clic che porta al terminale giusto. ([Indie Hackers](https://www.indiehackers.com/post/i-built-a-free-mac-app-that-tells-you-when-claude-code-needs-you-so-you-can-stop-watching-your-terminal-Nem4tXVTIa7HyAV3jgDh), [Product Hunt: Nudge](https://www.producthunt.com/products/nudge-30))
- Issue storiche su Claude Code che chiedono la stessa cosa: [#36885](https://github.com/anthropics/claude-code/issues/36885), [#13024](https://github.com/anthropics/claude-code/issues/13024), [#26581](https://github.com/anthropics/claude-code/issues/26581).

## Come si ricava lo stato

Bubo usa l'Agent SDK TypeScript (versione letta: `@anthropic-ai/claude-agent-sdk` 0.3.284, `sdk.d.ts`). Tre fonti di segnale, dalla più affidabile.

### 1. Messaggio `session_state_changed` (segnale principale)

```ts
type SDKSessionStateChangedMessage = {
  type: 'system';
  subtype: 'session_state_changed';
  state: 'idle' | 'running' | 'requires_action';
  uuid: UUID;
  session_id: string;
};
```

- Il commento nel `.d.ts` dice: `idle` scatta dopo che il risultato è stato consegnato e i subagent in background sono finiti. È **il segnale autorevole di fine turno**.
- Risolve i due problemi più lamentati: non scatta a ogni fine turno intermedio e non scatta con subagent ancora vivi.
- Da verificare con uno spike: nel bundle esiste la variabile `CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS`. Probabilmente serve per abilitare l'evento. La doc pubblica non la descrive.

### 2. `canUseTool` e i messaggi del flusso (dettaglio dello stato)

- **Permesso richiesto**: la callback `canUseTool` arriva subito, con `toolName`, `input`, `toolUseID`, `requestId`, `suggestions`. Può restare in attesa senza limite. ([typescript](https://code.claude.com/docs/en/agent-sdk/typescript), [user input](https://code.claude.com/docs/en/agent-sdk/user-input))
  - Bubo sa che deve chiedere **nel momento stesso** in cui l'SDK chiede. Latenza zero lato SDK.
- **Domanda all'utente** (`AskUserQuestion`): passa anch'essa da `canUseTool`. Così si distingue "domanda" da "fine turno", cosa che gli hook non fanno ([#93872](https://github.com/anthropics/claude-code/issues/93872)).
- **Fine turno**: `result` con `subtype` `success` o errore (`error_max_turns`, `error_during_execution`, `error_max_budget_usd`, ...), più `duration_ms`, `total_cost_usd`, `is_error`, `permission_denials`.
- **Task in background**: `task_started`, `task_progress`, `task_notification` (`completed` / `failed` / `stopped`).
- **Altri**: `status` (`compacting`), `api_retry`, `rate_limit`, `permission_denied`, `notification` (testo con `priority` low/medium/high/immediate), `informational`, `worker_shutting_down`.
- Per il riassunto di riga: `tool_use_summary` e l'ultimo testo dell'assistente.

### 3. Hook (utili, ma secondari)

- In TS ci sono tutti: `Stop`, `StopFailure`, `SubagentStart/Stop`, `PermissionRequest`, `Notification`, `SessionStart/End`, `TaskCompleted`, `TeammateIdle`, `Elicitation`. ([hooks SDK](https://code.claude.com/docs/en/agent-sdk/hooks))
- `Notification` nelle sessioni SDK scatta solo per:
  - `permission_prompt` dopo **circa 6 secondi** di attesa su `canUseTool`;
  - `elicitation_complete` e `elicitation_response`.
  - `idle_prompt`, `agent_needs_input`, `agent_completed` vengono dalla UI interattiva e **non arrivano all'SDK**. ([hooks SDK](https://code.claude.com/docs/en/agent-sdk/hooks), [hooks](https://code.claude.com/docs/en/hooks))
- `Stop` non distingue "finito" da "domanda in sospeso". Il payload ha però `background_tasks` con lo stato dei task ([#93672](https://github.com/anthropics/claude-code/issues/93672)).
- Se Bubo carica gli hook dell'utente da `~/.claude`, i suoi `Notification` hook potrebbero partire in doppio. Esiste `CLAUDE_CODE_DISABLE_PERMISSION_PROMPT_NOTIFY_HOOKS=1` per spegnerli nelle sessioni con `canUseTool`. ([env vars](https://code.claude.com/docs/en/env-vars))

### Mappa proposta degli stati

| Stato di Bubo | Da cosa si ricava | Notifica? |
|---|---|---|
| Lavora | `session_state_changed: running` | No |
| Attende te: permesso | `canUseTool` pendente (tool ≠ domanda) | Sì, con azioni |
| Attende te: domanda | `canUseTool` pendente per `AskUserQuestion`, oppure elicitation MCP | Sì, apre la sessione |
| Finita | `idle` dopo `result: success`, nessun task in background | Sì, se non la stai guardando |
| Errore | `result` con `is_error`, `StopFailure`, `api_retry` esauriti | Sì |
| In pausa per limiti | `rate_limit` | Sì, una volta |
| Fermata | interruzione dell'utente, `worker_shutting_down`, processo uscito | No |

## API Apple

Target: macOS 26 (ADR 0001). Tutte le API qui sotto esistono da macOS 12 o prima.

### Notifiche con azioni

- `UNUserNotificationCenter` + `UNNotificationCategory` con `UNNotificationAction` (pulsante) e `UNTextInputNotificationAction` (risposta scritta). ([Apple](https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types))
- Opzioni dell'azione: `.foreground` (apre l'app), `.destructive` (rosso), `.authenticationRequired` (serve sblocco). ([Apple](https://developer.apple.com/documentation/usernotifications/unnotificationactionoptions))
- Icone sulle azioni: `UNNotificationActionIcon`, da macOS 12. ([Apple](https://developer.apple.com/documentation/usernotifications/unnotificationactionicon))
- **Limite**: in stile banner il sistema mostra **solo le prime due azioni**. ([Apple](https://developer.apple.com/documentation/usernotifications/unnotificationcategory/actions)) Quindi: "Consenti" e "Nega". "Consenti sempre" va nel menu o nell'app.
- La risposta arriva in `userNotificationCenter(_:didReceive:withCompletionHandler:)`. Un'azione senza `.foreground` si gestisce **senza aprire l'app**: si risolve la promise di `canUseTool` e basta.
- `UNTextInputNotificationAction` permette di rispondere a una domanda semplice dalla notifica.

### Notifica mentre Bubo è in primo piano

- Di default macOS **non mostra il banner** se l'app è in primo piano. Con `userNotificationCenter(_:willPresent:withCompletionHandler:)` l'app sceglie per ogni notifica: `.banner`, `.list`, `.sound`, `.badge` oppure niente. ([Apple](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter(_:willpresent:withcompletionhandler:)))
- È esattamente il bug di Superset ([#7141](https://github.com/superset-sh/superset/issues/7141)). Bubo può decidere: banner sì se la sessione non è quella visibile, silenzio se lo è.

### Raggruppamento, priorità, Focus

- `threadIdentifier`: raggruppa le notifiche. Una per sessione (o per progetto). ([Apple](https://developer.apple.com/documentation/usernotifications/unmutablenotificationcontent/threadidentifier))
- `interruptionLevel`: `passive`, `active`, `timeSensitive`, `critical`. `timeSensitive` supera Focus e Riepilogo, ma serve l'entitlement `com.apple.developer.usernotifications.time-sensitive` e l'utente può spegnerlo. ([Apple](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive), [WWDC21 10091](https://developer.apple.com/videos/play/wwdc2021/10091/))
- `relevanceScore` (0–1): quale notifica viene messa in evidenza nel riepilogo. ([Apple](https://developer.apple.com/documentation/usernotifications/unnotificationcontent/relevancescore))
- `SetFocusFilterIntent` (App Intents, macOS 13+): Bubo può sapere quale Focus è attivo e adattarsi (es. in "Lavoro" solo permessi). ([Apple](https://developer.apple.com/documentation/appintents/setfocusfilterintent))
- `removeDeliveredNotifications(withIdentifiers:)`: togliere la notifica quando il permesso è già stato dato dall'HUD. Evita notifiche "stantie". ([Apple](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/removedeliverednotifications(withidentifiers:)))
- Banner o avviso persistente: **lo sceglie l'utente**, l'app non può forzarlo. ([Apple Developer Forums](https://developer.apple.com/forums/thread/792875))

### Badge nel Dock

- `NSApp.dockTile.badgeLabel`: stringa libera nel badge. ([Apple](https://developer.apple.com/documentation/appkit/nsdocktile/badgelabel))
- In alternativa `UNUserNotificationCenter.setBadgeCount(_:)`, da macOS 13. ([Apple](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/setbadgecount(_:withcompletionhandler:)))
- Il badge appare **solo con il permesso `.badge`** concesso. ([Superset docs](https://docs.superset.sh/agent-status), [Apple Developer Forums](https://developer.apple.com/forums/thread/696708))
- `NSDockTile.contentView` permette un'icona disegnata (es. un mini **Orb** colorato per stato). Da valutare per costo.
- `NSApplication.requestUserAttention(_:)`: rimbalzo dell'icona. `.informationalRequest` rimbalza una volta. Non ruba il focus, a differenza di quanto lamentato in [#94460](https://github.com/anthropics/claude-code/issues/94460). ([Apple](https://developer.apple.com/documentation/appkit/nsapplication/requestuserattention(_:)))

## Il meglio da battere

Oggi il riferimento è l'**agent view di Claude Code** (stati chiari e riassunto per riga) più **Nimbalyst** (non letti, icona per tipo, sessioni ordinate per tempo di attesa). Nessuno approva dalla notifica e tutti fanno rumore. Criteri candidati:

1. **Latenza della notifica "attende te"** ≤ 1 s dalla chiamata `canUseTool` (Claude Code in SDK: ~6 s per `permission_prompt`; `idle_prompt` ~60 s).
2. **Clic per approvare** un permesso con Bubo in secondo piano: 1 clic dalla notifica, senza aprire l'app (oggi: clic → app → sessione → approva, 3+ clic).
3. **Zero notifiche spurie**: nessuna notifica di fine se ci sono task in background o subagent attivi; al massimo 1 notifica per sessione per transizione di stato.
4. **Silenzio se la sessione è visibile**, banner se è un'altra sessione anche con Bubo in primo piano.
5. **Mai rubare il focus**; badge nel Dock = numero di sessioni che aspettano te, allineato entro 1 s.

## Rischi e casi limite

- **`session_state_changed` forse dietro una variabile d'ambiente**. Se non arriva, ricadere su `result` + stato dei task in background. Serve uno spike.
- **Approvare dalla notifica è rischioso**: un `rm -rf` approvato da un banner senza leggere. Mitigazione: comando visibile nel corpo, `.authenticationRequired` o solo "Apri" per comandi pericolosi, "Consenti sempre" mai dalla notifica.
- **Notifica stantia**: permesso già dato dall'HUD, ma la notifica resta. Toglierla con `removeDeliveredNotifications`. Stesso caso se l'SDK annulla la richiesta (`control_cancel_request`).
- **Più richieste nella stessa sessione** (subagent in parallelo): una notifica per richiesta o una sola raggruppata? `threadIdentifier` per sessione aiuta.
- **Domanda distrutta da un evento in background** (visto in Nimbalyst [#1557](https://github.com/nimbalyst/nimbalyst/issues/1557)): lo stato "attende te" deve sopravvivere a un `task_notification`.
- **Stato "attende" che non si pulisce** quando l'utente scrive altro invece di rispondere (visto in Nimbalyst).
- **Permesso badge negato**: niente badge. Mostrare lo stato anche nel **Panel** e nella barra dei menu.
- **Focus e Riepilogo notifiche** possono ritardare o nascondere le notifiche. `timeSensitive` richiede entitlement ed è spegnibile.
- **Hook dell'utente in `~/.claude`** (feature 04): i suoi `Notification`/`Stop` hook partono anche in Bubo e possono duplicare le notifiche.
- **Sessione ripresa** dopo riavvio o sonno: i messaggi rigiocati (`worker_shutting_down` ecc.) non devono generare notifiche.
- **Rumore dei limiti d'uso**: `rate_limit` e `api_retry` possono arrivare a raffica. Una notifica sola, poi silenzio.
- **Collegamento con l'Orb**: lo **Stato** dell'Orb (CONTEXT.md) è della presenza, non della sessione. Con più sessioni serve una regola (es. l'Orb va in "attende" se almeno una sessione aspetta). Da decidere nella mappa.

## Mappa

### Vista delle Sessioni (decisa)

Fonte: [Prototipo: le Sessioni nell'HUD](https://github.com/mgiuditta/bubo/issues/22), branch `prototype/sessioni-hud`.

- Tre Viste, scelte in Impostazioni → Aspetto: **Colonna** (predefinita), **Orbita**, **Striscia**. Stessi dati e stesse azioni; cambia solo la disposizione.
- Colonna: raggruppata per Attività; Attende te in cima, ordinate per tempo di attesa; riga = titolo, attesa, riassunto di una riga, Progetto · branch · Fase; Richiesta di permesso inline.
- Orbita: Attende te in alto, più grandi e luminose; le altre ai lati; card della Sessione sotto l'Orb; quota come archi sull'anello.
- Striscia: carte orizzontali sopra il prompt; Attende te allargate con i pulsanti.
- In tutte: quota 5 h / settimana con reset visibile senza clic; interruttore Domanda ↔ Sessione nel prompt; ⌘N nuova Sessione; ↩ Solo ora, esc No sulla Richiesta aperta.
- Ordine di costruzione: Colonna, poi Orbita e Striscia.

### Moduli, flussi e casi limite

Architettura comune in [INDEX.md](INDEX.md#architettura-comune-feature-16).

- **Moduli**: `Sessions/ActivityTracker` (da `session_state_changed` con `CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS=1` e da `canUseTool`), `System/Notifier` (`UNUserNotificationCenter`, categorie con azioni Solo ora / No, `threadIdentifier` per Sessione, silenzio se la Sessione è visibile), `System/DockBadge` (`NSDockTile.badgeLabel`, `requestUserAttention(.informationalRequest)`), `HUD/SessionViews` (Colonna, Orbita, Striscia).
- **Flusso**: evento SDK → Attività → Vista + Stato dell'Orb + badge + (se non visibile) notifica.
- **Casi limite**: permesso notifiche negato (solo badge e rimbalzo), Focus attivo, più Richieste nella stessa Sessione, risposta dalla notifica dopo che la Richiesta è scaduta, riavvio di Bubo con Richieste pendenti.
- **Test**: macchina delle Attività con Swift Testing su sequenze di eventi registrate.

## Specifica "migliore di"

Miglior concorrente: **agent view di Claude Code** (stati e riassunto per riga) e **Nimbalyst** (non letti, ordinamento per attesa); nessuno approva dalla notifica e tutti fanno rumore.
Bubo lo supera così:
- Notifica "Attende te" **≤ 1 s** dalla richiesta (Claude Code via hook: ~6 s).
- **1 clic** dalla notifica per Solo ora / No sui livelli 2–3, senza aprire Bubo.
- **0 notifiche spurie**: niente "finito" con subagent attivi, al massimo 1 per transizione, silenzio se la Sessione è visibile, **mai** focus rubato.
- Badge nel Dock = Sessioni in Attende te, allineato **entro 1 s**; tre Viste (Colonna predefinita, Orbita, Striscia).

## Fonti

Anthropic / Claude Code
- Agent SDK, hooks: https://code.claude.com/docs/en/agent-sdk/hooks
- Agent SDK, riferimento TypeScript: https://code.claude.com/docs/en/agent-sdk/typescript
- Agent SDK, input utente e permessi: https://code.claude.com/docs/en/agent-sdk/user-input
- Tipi del pacchetto `@anthropic-ai/claude-agent-sdk` 0.3.284 (`sdk.d.ts`): https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk
- Hooks reference: https://code.claude.com/docs/en/hooks
- Variabili d'ambiente: https://code.claude.com/docs/en/env-vars
- App desktop: https://code.claude.com/docs/en/desktop
- Progetti: https://code.claude.com/docs/en/claude-projects
- Agent view: https://code.claude.com/docs/en/agent-view
- Issue: https://github.com/anthropics/claude-code/issues/87351 · /93672 · /93872 · /94460 · /12046 · /36885 · /13024 · /26581

Concorrenti
- Conductor changelog: https://www.conductor.build/changelog.md · https://www.conductor.build/changelog/0.52.0-sounds-colors · https://www.conductor.build/changelog/0.35.0-workspace-status · https://releases.sh/conductor/conductor-changelog.md
- Nimbalyst release: https://github.com/nimbalyst/nimbalyst/releases · issue #1006, #1245, #1557, #1549
- Superset docs: https://docs.superset.sh/agent-status · issue https://github.com/superset-sh/superset/issues/7141 · /6929 · /6641 · /1785 · /5259 · /5601
- CodeAgentSwarm, guida notifiche: https://github.com/arturogj92/codeagentswarm-landing/blob/main/content/guides/en/codeagentswarm-notifications.ts
- opcode: https://github.com/winfunc/opcode/issues/208
- App di contorno: https://www.indiehackers.com/post/i-built-a-free-mac-app-that-tells-you-when-claude-code-needs-you-so-you-can-stop-watching-your-terminal-Nem4tXVTIa7HyAV3jgDh · https://www.producthunt.com/products/nudge-30

Apple
- Notifiche con azioni: https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types
- `UNNotificationCategory.actions` (max 2 in banner): https://developer.apple.com/documentation/usernotifications/unnotificationcategory/actions
- `UNNotificationActionOptions`: https://developer.apple.com/documentation/usernotifications/unnotificationactionoptions
- `UNNotificationActionIcon`: https://developer.apple.com/documentation/usernotifications/unnotificationactionicon
- `willPresent`: https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter(_:willpresent:withcompletionhandler:)
- `threadIdentifier`: https://developer.apple.com/documentation/usernotifications/unmutablenotificationcontent/threadidentifier
- `interruptionLevel.timeSensitive`: https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive
- WWDC21 "Send communication and Time Sensitive notifications": https://developer.apple.com/videos/play/wwdc2021/10091/
- `relevanceScore`: https://developer.apple.com/documentation/usernotifications/unnotificationcontent/relevancescore
- `SetFocusFilterIntent`: https://developer.apple.com/documentation/appintents/setfocusfilterintent
- `removeDeliveredNotifications`: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/removedeliverednotifications(withidentifiers:)
- `NSDockTile.badgeLabel`: https://developer.apple.com/documentation/appkit/nsdocktile/badgelabel
- `setBadgeCount`: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/setbadgecount(_:withcompletionhandler:)
- `requestUserAttention`: https://developer.apple.com/documentation/appkit/nsapplication/requestuserattention(_:)
- Forum: preferenze notifiche non modificabili dall'app: https://developer.apple.com/forums/thread/792875
- Forum: badge che non appare senza permesso: https://developer.apple.com/forums/thread/696708
