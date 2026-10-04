# Ricerca #488 — Dal cursore all'azione: Bubo capisce l'app aperta e agisce

Ticket: [#488](https://github.com/mgiuditta/bubo/issues/488). Dipende da: [#485](https://github.com/mgiuditta/bubo/issues/485) (cattura sotto il cursore, [ricerca](https://github.com/mgiuditta/bubo/blob/research/485-cattura-cursore/docs/research/485-cattura-cursore.md)). Collegati: [#103](https://github.com/mgiuditta/bubo/issues/103) (Allega finestra), [#100](https://github.com/mgiuditta/bubo/issues/100) (Servizio ⌘⇧O), [#66](https://github.com/mgiuditta/bubo/issues/66) (prova del disclaim). Spec: [`docs/features/09-sistema.md`](../features/09-sistema.md). ADR: [0001](../adr/0001-solo-macos-26.md), [0005](../adr/0005-claude-senza-i-permessi-tcc-di-bubo.md).
Ricerca del 2026-10-02, **fatta su Linux**: nessuna prova su Mac, nessuna misura. Tutto ciò che riguarda TCC e tempi va provato su un Mac (sezione "Da verificare"). Fonti lette alla stessa data; dove la pagina ha una data è indicata tra parentesi.

**Domanda.** Dopo lo scatto sotto il cursore (#485), come può Bubo capire quale app è aperta e cosa c'è dentro (finestra, documento, selezione), e su richiesta compiere azioni semplici in quell'app ("rispondi a questa mail", "aggiungi questo evento al calendario", "riassumi questa pagina", "crea un ticket da questo errore"), restando dentro ADR 0005?

**Nota sui termini.** In `CONTEXT.md` **Automazione** è una richiesta programmata di Bubo e **Bozza** un lavoro da iniziare. Qui il consenso TCC di macOS chiamato "Automazione" si scrive **consenso Apple Events**, e la bozza di una mail è "mail non inviata".

## In sintesi

- **Capire l'app senza permessi si può solo a metà.** Senza consensi Bubo sa **quale** app è davanti (`NSWorkspace.frontmostApplication`, già usato nei log del Panel) e quale finestra c'è sotto il cursore (`CGWindowList`, senza titolo: provato in #485). Il **contenuto** arriva solo da ciò che l'utente consegna: selezione col Servizio ⌘⇧O, trascinamento, selettore di finestra + OCR (#485/#103). L'albero AX dà tutto, ma vuole Accessibilità, esclusa dalla v1.
- **Agire senza permessi si può per la maggior parte degli esempi, con la strada "prepara e consegna":** Bubo (o l'agente) prepara il risultato e lo consegna all'app di destinazione, che lo mostra all'utente prima del passo irreversibile. Mail aperta e non inviata (`mailto:` o `NSSharingService.composeEmail`), file `.ics` aperto con Calendario, issue creata con un **Server MCP** (GitHub, Linear) dietro **Richiesta di permesso**, Comandi rapidi dell'utente con `shortcuts run`. Nessuna voce TCC per Bubo.
- **Il salto vero è il consenso Apple Events per app** (Mail, Calendario, Safari, Note, Finder): legge la mail selezionata, l'URL della pagina, crea l'evento in un calendario preciso. È per singola app di destinazione, lo chiede macOS alla prima chiamata, e con il disclaim non passa a `claude`. Spec 09 e ADR 0005 non lo escludono per nome, ma ADR 0005 cita proprio "`osascript` controllare le app" come rischio: serve un ADR e la prova del disclaim anche per Apple Events (#66 ha provato Microfono e File e cartelle).
- **Computer use (AX + Registrazione schermo) resta fuori.** Claude Code ce l'ha come server MCP `computer-use`, ma in anteprima, solo Pro/Max, **solo in sessione interattiva** (non con `-p`, quindi probabilmente non dal ponte con l'Agent SDK) e con i due permessi che ADR 0005 esclude [C1][C2].
- **Le strade di Apple non sono aperte a Bubo come lettore.** La consapevolezza dello schermo di Siri AI (macOS 27, 14 settembre 2026) legge le entità che le app annotano, ma quel contenuto "è privato dell'app" e lo consuma solo il sistema [A1][A2]. Gli App Intents di altre app si invocano solo passando da Comandi rapidi [T1][T2]. Il server MCP di Safari 27 lavora in una finestra di automazione isolata, non nella pagina dell'utente [S1].
- **Raccomandazione:** v1 della funzione a **zero permessi** (contesto consegnato dall'utente + "prepara e consegna" + MCP); il consenso Apple Events come **secondo passo opt-in per app**, con ADR e prova; computer use e AX fuori finché ADR 0005 non cambia. Ticket `ready-for-human` per le due decisioni.

## Vincoli già decisi

- **ADR 0005:** Bubo non chiede un permesso TCC che l'agente erediterebbe se non può isolarlo; `claude` e ogni processo avviato da Bubo partono con il disclaim (provato per Microfono e File e cartelle in #66). Ingressi senza permessi: Servizio per il testo, selettore di ScreenCaptureKit per lo schermo. Ripiego: "Accessibilità e Registrazione schermo restano comunque escluse".
- **Spec 09, Ingressi della v1:** drop, Servizio ⌘⇧O, App Intents di Bubo, "Allega finestra…". Fuori: Condividi, Azione rapida, Finder Sync, Accessibilità, Registrazione schermo classica. La sezione Ricerca cita gli Apple Events al Finder come strada possibile (consenso per app di destinazione, `com.apple.security.automation.apple-events` + `NSAppleEventsUsageDescription`), senza decisione.
- **ADR 0001:** solo macOS 26. Siri AI con la consapevolezza dello schermo è di **macOS 27** [A3]: per Bubo è al massimo un'aggiunta condizionale, non una base.
- **Permessi dell'agente (`CONTEXT.md`):** ogni azione non ancora consentita passa da una **Richiesta di permesso** (No, Solo ora, Per questa Sessione, Sempre in questo Progetto); **Livello di rischio** 1–5 (Lettura, Modifica reversibile, Rete, Distruttivo locale, Irreversibile esterno); dai livelli 4–5 non nasce mai una **Regola di permesso**; dal **Telecomando** per 4–5 solo No o Solo ora.
- **Codice esistente** (`origin/main` 5f0de80): `NSWorkspace.frontmostApplication` usato solo nei log di `Bubo/Panel/OrbPanelController.swift`; App Intents di Bubo in `Bubo/System/Intents/` (Chiedi a Bubo, Nuova Sessione, Galassia, Cronologia); ponte con l'Agent SDK in `bridge/src/main.ts` con `canUseTool` verso Bubo e un server MCP in processo (`createSdkMcpServer({ name: "bubo" })`); `Bubo/Permissions/RiskClassifier.swift` assegna il Livello di rischio. `Bubo/Bubo.entitlements` ha solo `audio-input` e il portachiavi: niente `automation.apple-events`.

## Le fonti del contesto, una per una

### 1. App in primo piano e finestra sotto il cursore (zero permessi)

- `NSWorkspace.shared.frontmostApplication` dà bundle ID, nome e PID dell'app attiva; il Panel di Bubo è un `NSPanel` non attivante, quindi l'app dell'utente resta quella davanti. Nessun consenso.
- `CGWindowListCopyWindowInfo`: app, ID e riquadro della finestra sotto il cursore; **niente titolo** senza Registrazione schermo (provato in #485 con un processo con disclaim).
- Basta per **adattare la risposta all'app** (suggerimenti diversi per Mail, Safari, Xcode, Calendario) e per scrivere "da Mail" nella chip. Non basta per sapere quale mail.

### 2. Ciò che l'utente consegna (zero permessi)

- **Servizio "Chiedi a Bubo" (⌘⇧O):** testo selezionato da qualunque app Cocoa (spec 09). Per "rispondi a questa mail" l'utente seleziona il testo della mail.
- **Trascinamento sull'Orb:** file, URL, testo. Da Mail il trascinamento di un messaggio produce un file `.eml` o un URL `message:` (da verificare su macOS 26): darebbe intestazioni e corpo, e quindi destinatario e oggetto della risposta.
- **Selettore di finestra + OCR di Vision** (#485, #103): immagine della finestra e testo riconosciuto in locale.
- Copre i quattro esempi della issue, con un gesto in più rispetto a chi legge l'albero AX.

### 3. Albero di Accessibilità (AX)

- `AXUIElementCreateApplication(pid)` → finestra in primo piano → elemento focalizzato, `kAXSelectedTextAttribute`, `kAXValueAttribute`, figli. È ciò che usano ChatGPT "Work with Apps", Raycast `@screen-awareness` e il computer use di Claude [C1][R1] (spec 09).
- Permesso **Accessibilità**: escluso dalla v1 (spec 09) e dal ripiego di ADR 0005. Senza consenso `AXUIElementCopyElementAtPosition` torna `kAXErrorAPIDisabled` (#485).
- Limiti noti: app Electron e terminali espongono poco o nulla (spec 09, [R3][R6] lì).

### 4. App Intents e Comandi rapidi esposti dalle altre app

- Le app dichiarano le azioni nei metadati `Metadata.appintents/extract.actionsdata` dentro il bundle; leggerli non chiede permessi. Un'app terza **non può invocare direttamente** l'`AppIntent` di un'altra: la via pubblica è un comando rapido che contiene l'azione, eseguito con `/usr/bin/shortcuts run` [T1][T2]. Il progetto `intents-mcp` fa proprio questo: genera un comando rapido per azione, lo firma con `shortcuts sign` e lo espone come strumento MCP; le azioni su entità esistenti (una nota, un promemoria) non sono ancora supportate [T1].
- Adozione bassa nelle app terze: su un Mac preso a campione 8 app su 50 avevano App Intents [T3]. Le app Apple ne dichiarano molte (oltre 1.000 azioni in macOS 27, secondo [T1]).
- Esecuzione: le azioni di Comandi rapidi chiedono i **loro** consensi (a nome di Comandi rapidi), non a nome di Bubo; un comando rapido che chiede input si ferma in attesa [T2]. Con disclaim da verificare come vengono attribuiti i consensi quando `shortcuts` è lanciato da Bubo o dall'agente.

### 5. AppleScript, JXA e Apple Events

- Le app scriptabili (Mail, Calendario, Safari, Note, Finder, Musica; molte terze come OmniFocus, Things) espongono un dizionario: Mail `selection` e `content`, Safari `URL of front document`, Calendario `make new event`. Da Swift con `NSAppleScript`, `NSAppleEventDescriptor` o ScriptingBridge.
- Requisiti: con Hardened Runtime l'entitlement `com.apple.security.automation.apple-events` e la chiave `NSAppleEventsUsageDescription` [X1][X2]. macOS chiede il **consenso Apple Events una volta per app di destinazione** ("Bubo vuole controllare Mail"); `AEDeterminePermissionToAutomateTarget` controlla lo stato senza chiedere, ma vuole l'app di destinazione in esecuzione [X3].
- **Ereditarietà:** il consenso va al processo responsabile. Senza disclaim un `osascript` lanciato dall'agente userebbe quello di Bubo (o farebbe comparire "Bubo vuole controllare…" per conto dell'agente); con il disclaim la richiesta è a nome del processo figlio [X4][X5]. Bubo avvia già tutto con il disclaim (ADR 0005), ma per Apple Events la prova non c'è.
- Consenso **più stretto** di Accessibilità (una app alla volta, revocabile per app in Impostazioni → Privacy e sicurezza → Automazione) e senza avvisi periodici noti.

### 6. Apple Intelligence e Siri AI: consapevolezza dello schermo

- **Siri AI** è uscita con macOS 27 il 14 settembre 2026, in beta e in inglese al lancio; altre lingue da ottobre [A3][A4]. "Siri AI può rispondere a domande o compiere azioni sul contenuto dello schermo"; sul Mac anche dal menu contestuale (Control-clic su immagini, file, testo) [A3]. Modelli costruiti con Google Gemini, Private Cloud Compute [A3].
- Le app partecipano annotando viste e `NSUserActivity` con `appEntityIdentifier`, `NSTableViewAppIntentsDataSource`, `NSCollectionViewAppIntentsDataSource`, e adottando gli **schemi** (`App schema domains`, prima "assistant schemas"); nuovi nel 2026 `OwnershipProvidingEntity` (privato/condiviso/pubblico, per decidere quando chiedere conferma), `IntentValueQuery` [A1][A2]. Apple lo presenta come il modo di collegare le app a "personal context, app actions, and onscreen awareness" di Siri AI [A5].
- **Per Bubo come lettore non serve:** la documentazione dice che il contenuto a schermo "è privato della tua app" e lo usa Apple Intelligence [A1]; la sessione WWDC26 non prevede assistenti terzi [A2]. Bubo può solo **fornire** le sue entità (Sessioni, Domande) a Siri, cosa già nella linea della spec 09 (App Intents).
- Su un Mac con macOS 27 e Siri AI attiva, per le app Apple l'utente ha già un'alternativa di sistema: è il confronto da tenere a mente.

### 7. ScreenCaptureKit + Vision

Coperta da #485: selettore di sistema e un solo scatto, OCR in locale, zero permessi. Dà testo e immagine, non la struttura (quale mail, quale campo). Utile per "riassumi questa pagina" e "crea un ticket da questo errore" (l'errore è testo a schermo).

### 8. Safari MCP (Safari 27)

`safaridriver --mcp` espone 17 strumenti (DOM, rete, console, screenshot, valutazione di script) a un agente locale dopo l'opt-in in Safari → Impostazioni → Sviluppo → "Allow remote automation and external agents" [S1][S2]. Lavora in una **finestra di automazione isolata**, senza cookie, password né cronologia dell'utente [S2]. Quindi non legge "questa pagina" con la sessione dell'utente: per una pagina pubblica basta già l'URL (Servizio, drop) e il recupero lato agente. Disponibilità di Safari 27 su macOS 26: da verificare.

## Come agire, una strada per volta

| Strada | Esempi della issue | Permessi TCC di Bubo | Chi vede prima dell'effetto | Annullamento |
|---|---|---|---|---|
| **Prepara e consegna**: `mailto:` / `NSSharingService(named: .composeEmail)` | rispondi a questa mail | nessuno | l'utente, in Mail, prima di Invia | chiudere senza inviare |
| **Prepara e consegna**: file `.ics` aperto con `NSWorkspace.open` | aggiungi evento | nessuno | Calendario chiede in quale calendario importare (da verificare su 26) | elimina l'evento |
| **Server MCP** già collegati (connettori claude.ai, plugin): Gmail, Google Calendar, GitHub, Linear | tutti e quattro, se l'utente usa quei servizi | nessuno | **Richiesta di permesso** di Bubo (`canUseTool`) | dipende dal servizio; spesso no |
| **Comandi rapidi dell'utente** (`shortcuts run`) o wrapper di App Intents | qualunque azione esposta | nessuno per Bubo; Comandi rapidi chiede i suoi | Richiesta di permesso + eventuali avvisi di Comandi rapidi | dipende dall'azione |
| **Apple Events** (strumenti stretti di Bubo) | rispondi nella conversazione giusta, evento in un calendario preciso, URL di Safari | consenso Apple Events **per app** | Richiesta di permesso con l'anteprima | Bubo ricorda l'ID creato e può eliminarlo; invio di mail no |
| **Eventi AX / computer use** | qualunque app | Accessibilità + Registrazione schermo | per app e per sessione (Claude) | no, in generale |

Note:

- **`mailto:`** (RFC 6068) porta destinatario, oggetto e corpo; non porta in modo affidabile `In-Reply-To`, quindi la risposta può non agganciarsi alla conversazione in Mail [X6] (da verificare). Con Apple Events, `reply` di Mail apre la risposta vera nella conversazione.
- **Gli strumenti stretti** sono il modo di dare Apple Events senza dare `osascript` all'agente: il server MCP in processo del ponte (`createSdkMcpServer`) espone pochi strumenti tipizzati (`mail_reply_draft(to:subject:body:)`, `calendar_add_event(...)`, `safari_current_url()`), li esegue **Bubo** con il suo consenso e ciascuno passa da `canUseTool` e dal `RiskClassifier`. L'agente non riceve mai un AppleScript libero.
- **Computer use di Claude Code** è il server MCP integrato `computer-use`: chiede Accessibilità e Registrazione schermo per il processo che lo esegue, approvazione per app e per sessione, livelli fissi per categoria (browser e piattaforme di trading solo visione, terminali e IDE solo clic, il resto pieno controllo), Esc globale che ferma tutto; non funziona con `-p` [C1][C2]. Con il disclaim i consensi sarebbero chiesti per `claude`, non per Bubo: compatibile con la lettera di ADR 0005 ma non con la clausola "restano comunque escluse" né con la spec 09. In più, lanciato dall'Agent SDK potrebbe non essere disponibile (da verificare).

## Permessi TCC e ADR 0005

| Permesso | Serve per | Granularità | Si isola dall'agente? | Stato |
|---|---|---|---|---|
| Nessuno | app in primo piano, finestra sotto il cursore (senza titolo), Servizio, drop, selettore + OCR, prepara e consegna, MCP | — | — | ammesso (v1) |
| Apple Events | leggere la mail selezionata, l'URL di Safari; creare eventi, risposte | **per app di destinazione** | con disclaim sì in teoria; **da provare** come #66 | non deciso: serve ADR |
| Calendari / Promemoria (EventKit) | creare eventi senza passare da Calendario | tutto il calendario | come sopra | non deciso; `.ics` lo evita |
| Accessibilità | albero AX, eventi di input | tutto il Mac | con disclaim il consenso resterebbe a Bubo, ma il potere è totale | escluso (spec 09, ADR 0005) |
| Registrazione schermo | scatto senza selettore, computer use | tutto lo schermo, avviso mensile | — | escluso |

Quattro regole per restare dentro ADR 0005, se si apre il consenso Apple Events:

1. Il consenso lo chiede **Bubo**, alla prima azione su quell'app, con un testo che nomina l'app ("per leggere la mail selezionata e preparare le risposte").
2. **L'agente non lo eredita**: tutti i processi partono con il disclaim; da provare con `osascript -e 'tell application "Mail" to …'` lanciato dall'agente, che deve chiedere a nome proprio o fallire, non usare quello di Bubo.
3. L'agente usa solo **strumenti stretti** di Bubo, non AppleScript libero.
4. Elenco delle app ammesse nelle Impostazioni, revocabile, con il collegamento a Impostazioni → Privacy e sicurezza → Automazione.

## Richiesta di permesso e annullamento

Ogni azione passa dalla **Richiesta di permesso** già esistente, con il **Livello di rischio** del `RiskClassifier`:

| Azione | Livello | Regola di permesso possibile? |
|---|---|---|
| Leggere il contesto (app davanti, selezione consegnata, URL) | 1 Lettura | sì |
| Aprire una mail non inviata, importare un `.ics` che l'utente conferma in Calendario | 2 Modifica reversibile | sì |
| Creare un evento direttamente (Apple Events, MCP) | 2 se nel calendario personale, 5 se manda inviti | sì per 2, mai per 5 |
| Creare un'issue su GitHub o Linear | 5 Irreversibile esterno (visibile ad altri) | no |
| Inviare una mail, rispondere in una chat | 5 Irreversibile esterno | no: meglio non offrirlo, lasciare Invia all'utente |

- **La Richiesta mostra il contenuto concreto**: destinatari, oggetto, corpo, data e calendario, titolo e testo dell'issue. Destinatari e indirizzi presi dal contenuto a schermo sono evidenziati.
- **Annullamento**: per le azioni reversibili Bubo registra l'inverso (ID dell'evento creato, ID dell'issue) e offre "Annulla" nel Panel per qualche secondo; per le irreversibili non c'è, e per questo la strada consigliata lascia l'ultimo passo all'app di destinazione.
- **Mai senza l'utente**: nessuna azione su app dell'utente in **Modalità autonoma** né in un'**Automazione** di Bubo; dal **Telecomando** solo No o Solo ora (regola già in `CONTEXT.md` per 4–5).

## Come fanno le app simili

| App | Contesto | Come agisce | Permessi | Conferma |
|---|---|---|---|---|
| **Claude** (desktop, Cowork, Claude Code) | screenshot + AX; Quick Entry con finestra (spec 09) | computer use: clic, tasti, trascinamento; dal 2 settembre 2026 anche in finestre in background [C1][C2][C4] | Accessibilità + Registrazione schermo [C1] | per app e per sessione, livelli per categoria, app negate, Esc globale, scansione di prompt injection [C1][C2][C3] |
| **ChatGPT per Mac** | "Work with Apps" via AX su app supportate (IDE, terminali, Note); "Appshots" della finestra attiva per la voce (luglio 2026) [O1][O2] | Computer Use nel nuovo ChatGPT desktop con Work e Codex [O2][O3] | Accessibilità, Registrazione schermo (spec 09) | non documentata nelle fonti lette |
| **Raycast AI** | `@selected-text`, `@screen-awareness` (contenuto, selezione, screenshot della finestra attiva), `@browser` con estensione [R1] | AI Extensions e Server MCP come strumenti [R1] | Accessibilità; Registrazione schermo facoltativa (spec 09) | Ask / Auto / Always Allow; Auto chiede sempre per credenziali e azioni distruttive [R1] |
| **Apple Siri AI** (macOS 27) | consapevolezza dello schermo dalle entità annotate dalle app [A1][A3] | App Intents e schemi delle app [A1] | di sistema | `OwnershipProvidingEntity` guida la conferma [A2] |
| **Perplexity Personal Computer** (Mac, maggio 2026) | file locali, app native, 400+ connettori [P1][P2] | agente ibrido locale/cloud; secondo la stampa azioni "verificabili e reversibili" in una sandbox [P1][P2] | non documentati nelle fonti lette | non documentata |
| **intents-mcp** (open source) | metadati App Intents | comandi rapidi generati, `shortcuts run` [T1] | consensi di Comandi rapidi | "Consenti sempre" alla prima esecuzione [T1] |

Tutti i concorrenti che "agiscono nell'app aperta" partono da Accessibilità + Registrazione schermo. Nessuno usa la strada "prepara e consegna" come prodotto: è lo spazio per Bubo, come lo erano i Servizi in spec 09.

## Opzioni

| # | Strada | Contesto | Azione | Permessi TCC | Gesti dell'utente | Stato rispetto alle decisioni |
|---|---|---|---|---|---|---|
| A | **Zero permessi**: app davanti + contesto consegnato (⌘⇧O, drop, selettore + OCR) + prepara e consegna + MCP | testo, file, immagine, nome dell'app | mail non inviata, `.ics`, MCP, comandi rapidi | **nessuno** | selezione o 1 clic + invio finale nell'app | Ammesso (v1) |
| B | A + **Apple Events per app**, con strumenti stretti di Bubo | mail selezionata, URL di Safari, finestra del Finder | risposta nella conversazione, evento nel calendario scelto | consenso Apple Events per app | nessun gesto per il contesto | Da decidere: ADR + prova del disclaim |
| C | B + **EventKit** per Calendario e Promemoria | calendari, promemoria | eventi e promemoria diretti | Calendari, Promemoria | — | Da decidere; poco guadagno su `.ics` e Apple Events |
| D | **Comandi rapidi / App Intents** delle altre app (stile `intents-mcp`) | — | azioni delle app che le espongono | nessuno per Bubo | consensi di Comandi rapidi | Ammesso; poche app terze lo supportano |
| E | **Albero AX** per il contesto | tutto ciò che l'app espone | — | Accessibilità | nessuno | Escluso (spec 09, ADR 0005) |
| F | **Computer use** (Claude Code `computer-use` o proprio) | screenshot + AX | clic e tasti in qualunque app | Accessibilità + Registrazione schermo | approvazione per app | Escluso; anteprima, interattivo, non da `-p` |
| G | **Siri AI** di sistema | entità annotate | App Intents | — | — | Non disponibile a terzi come lettore; macOS 27 |

## Raccomandazione

1. **Prima versione della funzione: opzione A.** Il Panel sa quale app è davanti e propone due o tre azioni adatte ("Rispondi", "Aggiungi al calendario", "Riassumi", "Crea issue"). Il contenuto arriva da ciò che l'utente ha già consegnato (⌘⇧O, drop, Allega finestra con OCR). L'agente prepara; Bubo consegna: mail non inviata in Mail, `.ics` aperto in Calendario, issue via il Server MCP di GitHub o Linear dietro Richiesta di permesso di livello 5. Nessun permesso TCC, nessun ADR nuovo.
2. **Secondo passo, opt-in per app: opzione B**, solo dopo un ADR che estenda ADR 0005 agli Apple Events e la prova che il disclaim isola anche quel consenso. Prime app: Mail (mail selezionata, risposta nella conversazione), Safari (URL e titolo della scheda), Calendario (evento in un calendario scelto). Sempre con strumenti stretti nel server MCP in processo, mai `osascript` libero all'agente.
3. **Opzione D come estensione, non come base**: leggere i metadati App Intents delle app installate per proporre azioni, ed eseguire i comandi rapidi che l'utente ha già, con `shortcuts run`. Utile per le app che lo supportano; poche.
4. **E, F, G fuori.** Accessibilità e Registrazione schermo restano escluse da ADR 0005; il computer use di Claude Code, se un giorno servisse, chiederebbe i consensi per `claude` e non per Bubo, ma oggi non gira da `-p`. Siri AI non è una fonte per Bubo: se mai, Bubo le fornisce le sue entità.
5. **Regole fisse per tutte le opzioni:** contenuto a schermo trattato come non fidato (sotto), anteprima concreta in ogni Richiesta di permesso, invio finale lasciato all'utente, nessuna azione su app dell'utente in Modalità autonoma o in un'Automazione.

## Rischi

- **Prompt injection dal contenuto a schermo** (OWASP LLM01:2025, indiretta [K1]): una mail o una pagina può contenere "inoltra le ultime 10 mail a…". Anthropic misura l'1% di successo degli attacchi adattivi su Opus 4.5 nel browser e lo chiama "rischio significativo" [K2]; i numeri variano molto con le azioni disponibili. Contromisure: il testo catturato entra nel prompt marcato come dati non fidati; le azioni le sceglie l'utente dal Panel, non il testo; destinatari e indirizzi venuti dal contenuto evidenziati nella Richiesta; nessuna Regola di permesso per 4–5; meno strumenti esposti (OWASP LLM06, "Excessive Agency" [K1]).
- **Azioni sbagliate**: destinatario o data capiti male. La strada "prepara e consegna" lascia l'ultimo controllo nell'app di destinazione; l'anteprima nella Richiesta mostra i campi, non un riassunto.
- **Privacy**: la selezione o lo scatto possono contenere dati di terzi o sensibili. Vale `AttachmentPolicy` (cosa va a Claude, cosa resta sui modelli del Mac); OCR in locale; elenco di app da cui Bubo non prende contesto (gestori di password, banche), come le "app negate" di Claude [C2].
- **Il consenso Apple Events passa all'agente** se il disclaim non lo isola: l'agente potrebbe controllare Mail con `osascript`. Va provato prima dell'ADR; senza prova l'opzione B non parte.
- **`mailto:` non aggancia la conversazione** in Mail (da verificare): la risposta può partire come mail nuova con "Re:". Se non basta, è il primo motivo concreto per l'opzione B su Mail.
- **Comandi rapidi lanciati da Bubo**: consensi attribuiti a Comandi rapidi o al processo responsabile (da verificare); un comando rapido con input resta in attesa.
- **macOS 27 vs ADR 0001**: Siri AI, Safari 27 e le novità App Intents 2026 sono di macOS 27 o con esso; Bubo è "solo macOS 26". Niente che dipenda da 27 nella prima versione.
- **Concorrenza di Siri AI** sulle app Apple con macOS 27: "aggiungi questo evento" lo fa già il sistema. Il valore di Bubo è sulle app e i servizi dove Siri non arriva (GitHub, Linear, Gmail via MCP) e sul fatto di non chiedere permessi.

## Da verificare (non provato: ricerca fatta su Linux)

- Con il disclaim, un `osascript` lanciato da `claude` usa o no il consenso Apple Events di Bubo? (Stessa prova di #66, con Mail o Finder.)
- `AEDeterminePermissionToAutomateTarget` e il testo dell'avviso con `NSAppleEventsUsageDescription` su macOS 26.
- `mailto:` con `In-Reply-To` in Mail su macOS 26: aggancia la conversazione?
- `.ics` aperto con `NSWorkspace.open`: Calendario chiede il calendario o importa da solo?
- Trascinamento di un messaggio da Mail sull'Orb: arriva un `.eml`, un URL `message:` o entrambi?
- `shortcuts run` lanciato da Bubo con disclaim: a chi sono attribuiti i consensi delle azioni?
- Il server `computer-use` di Claude Code è disponibile in una sessione dell'Agent SDK?
- Safari 27 su macOS 26 e il suo server MCP.

## Fonti

Apple — documentazione e annunci
- A1. "Apple Intelligence and Siri AI" (App Intents, onscreen context, App schema domains) — https://developer.apple.com/documentation/appintents/apple-intelligence-and-siri-ai
- A2. WWDC26 sessione 343, "Explore advanced App Intents features for Siri and Apple Intelligence" (giugno 2026) — https://developer.apple.com/videos/play/wwdc2026/343/
- A3. Apple Newsroom, "Siri AI, a profoundly more capable and personal assistant, is here" (14-09-2026) — https://www.apple.com/newsroom/2026/09/siri-ai-a-profoundly-more-capable-and-personal-assistant-is-here/
- A4. 9to5Mac, "macOS 27 Golden Gate adds a new Siri app for Mac" (19-08-2026) — https://9to5mac.com/2026/08/19/macos-27-new-siri-app-features/
- A5. Apple Newsroom, "Apple aids app development with new intelligence frameworks and advanced tools" (08-06-2026) — https://www.apple.com/newsroom/2026/06/apple-aids-app-development-with-new-intelligence-frameworks-and-advanced-tools/

Apple Events e TCC
- X1. Entitlement `com.apple.security.automation.apple-events` — https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events
- X2. `NSAppleEventsUsageDescription` — https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription
- X3. Apple Developer Forums 130949, "Catalina & AEDeterminePermissionToAutomateTarget" — https://developer.apple.com/forums/thread/130949 ; Michael Tsai, "AEDeterminePermissionToAutomateTarget added" (31-08-2018) — https://mjtsai.com/blog/2018/08/31/aedeterminepermissiontoautomatetarget-added-but-aepocalyse-still-looms/
- X4. Peter Steinberger, "AppleScript CLI on macOS: TCC and the Info.plist" (2025) — https://steipete.me/posts/2025/applescript-cli-macos-complete-guide
- X5. Qt, "The Curious Case of the Responsible Process" — https://www.qt.io/blog/the-curious-case-of-the-responsible-process
- X6. RFC 6068, "The 'mailto' URI Scheme" — https://www.rfc-editor.org/rfc/rfc6068

Comandi rapidi e App Intents di altre app
- T1. `intents-mcp` (VladUZH), App Intents del Mac come strumenti MCP via Comandi rapidi — https://github.com/VladUZH/intents-mcp
- T2. Supporto Apple, "Eseguire comandi rapidi dalla riga di comando" — https://support.apple.com/guide/shortcuts-mac/apd455c82f02/mac ; Six Colors, "Run Shortcuts from the Mac command line" (2021) — https://sixcolors.com/post/2021/12/run-shortcuts-from-the-mac-command-line/
- T3. Blake Crosley, "App Intents vs MCP: The Routing Question" (2026) — https://blakecrosley.com/blog/app-intents-vs-mcp-tools-frontier

Safari MCP
- S1. WebKit, "WebKit features for Safari 27.0" — https://webkit.org/blog/18325/webkit-features-for-safari-27-0/
- S2. iThinkDiff, "Safari 27 Adds an MCP Server for AI Coding Agents Like Claude Code" (18-09-2026) — https://www.ithinkdiff.com/safari-27-adds-an-mcp-server-for-ai-coding-agents-like-claude-code/ ; Forkast, "Safari 27 Ships a Native MCP Server" (20-09-2026) — https://forkast.news/safari-27-ships-a-native-mcp-server-and-apple-gave-enterprises-no-way-to-turn-it-off/

Claude
- C1. Claude Code, "Let Claude use your computer from the CLI" — https://code.claude.com/docs/en/computer-use
- C2. Claude Code, "Desktop application", sezione App permissions — https://code.claude.com/docs/en/desktop
- C3. Claude Help Center, sicurezza del computer use — https://support.claude.com/en/articles/14128542
- C4. AIToolsReview, "Claude's Background Computer Use, Explained" (settembre 2026) — https://aitoolsreview.co.uk/insights/claude-background-computer-use

OpenAI
- O1. OpenAI Help, "Work with Apps on macOS" — https://help.openai.com/en/articles/10119604-work-with-apps-on-macos (403 al momento della lettura; contenuto da spec 09 e dall'estratto indicizzato)
- O2. 9to5Mac, "OpenAI updating ChatGPT desktop app with GPT Voice for talking through work" (23-07-2026) — https://9to5mac.com/2026/07/23/openai-updating-chatgpt-desktop-app-with-gpt-voice-for-talking-through-work/
- O3. Digital Applied, "ChatGPT Work: OpenAI's Agent That Ships Finished Work" (2026) — https://www.digitalapplied.com/blog/chatgpt-work-openai-agent-launch-2026

Raycast e Perplexity
- R1. Raycast Manual, "AI Extensions" — https://manual.raycast.com/ai/ai-extensions
- P1. 9to5Mac, "Perplexity AI app introduces all-new native Mac experience for Personal Computer" (07-05-2026) — https://9to5mac.com/2026/05/07/perplexity-ai-app-introduces-all-new-native-mac-experience-for-personal-computer/
- P2. TechCrunch, "Perplexity's Personal Computer is now available to everyone on Mac" (07-05-2026) — https://techcrunch.com/2026/05/07/perplexitys-personal-computer-is-now-available-everyone-on-mac/

Sicurezza
- K1. OWASP, "Top 10 for LLM Applications 2025" (LLM01 Prompt Injection, LLM06 Excessive Agency) — https://genai.owasp.org/llm-top-10/
- K2. Anthropic, "Mitigating the risk of prompt injections in browser use" (24-11-2025) — https://www.anthropic.com/research/prompt-injection-defenses

Codice e documenti di Bubo letti (`origin/main` 5f0de80): `CONTEXT.md` (Allegato, Permessi, Automazione, Bozza), `docs/adr/0005-claude-senza-i-permessi-tcc-di-bubo.md`, `docs/features/09-sistema.md`, ricerca #485 sul branch `research/485-cattura-cursore`, `Bubo/Panel/OrbPanelController.swift`, `Bubo/System/Intents/`, `Bubo/Bubo.entitlements`, `Bubo/Permissions/`, `bridge/src/main.ts`.
