# 09 — Finder e sistema: "Chiedi a Bubo" da ovunque

Ticket: [#45](https://github.com/mgiuditta/bubo/issues/45), [#53](https://github.com/mgiuditta/bubo/issues/53), [#57](https://github.com/mgiuditta/bubo/issues/57), [#60](https://github.com/mgiuditta/bubo/issues/60), [#61](https://github.com/mgiuditta/bubo/issues/61). Mappa: [#42](https://github.com/mgiuditta/bubo/issues/42). ADR: [0005](../adr/0005-claude-senza-i-permessi-tcc-di-bubo.md).
Ricerca del 2026-09-29 su macOS 26 (Tahoe). Fonti lette alla stessa data; dove la pagina ha una data è indicata tra parentesi nelle Fonti.

In sintesi: nessuno dei concorrenti usa le estensioni di sistema. Raycast, ChatGPT, Claude desktop e Alfred fanno tutto con **una scorciatoia globale + permesso di Accessibilità** (più Registrazione schermo per gli screenshot). Bubo può fare meglio partendo senza permessi: **Servizi** (testo e file, da qualunque app Cocoa, zero permessi, zero sandbox), **trascinamento sull'Orb** (zero permessi) e **App Intents** (Spotlight e Comandi rapidi, macOS 26). L'Accessibilità resta un'opzione per il testo selezionato con scorciatoia. Il punto delicato è che Bubo non è in sandbox e avvia il figlio `claude`: i permessi TCC dati a Bubo valgono, di norma, anche per i processi che l'agente lancia.

> **Nota dopo le decisioni.** La Ricerca sotto è rimasta com'era. Dove propone l'Accessibilità come opzione, un processo di supporto separato per AX, Condividi o Azione rapida, vale ciò che è stato deciso dopo: niente Accessibilità né Registrazione schermo classica, `claude` avviato con disclaim ([ADR 0005](../adr/0005-claude-senza-i-permessi-tcc-di-bubo.md), [#61](https://github.com/mgiuditta/bubo/issues/61)); Condividi, Azione rapida e Finder Sync fuori dalla v1 ([#53](https://github.com/mgiuditta/bubo/issues/53), [#60](https://github.com/mgiuditta/bubo/issues/60)). Il drop sul Panel non attivante, "da verificare" qui, è stato provato in [#60](https://github.com/mgiuditta/bubo/issues/60).

## Ricerca

### Come fanno i concorrenti

| App | Punti d'ingresso | Permessi chiesti | Limiti noti |
|---|---|---|---|
| **Raycast** | Launcher globale; `{selection}` nei comandi AI; Quick AI (Tab dalla ricerca); AI Chat con allegati via `@`; Screen Awareness; API estensioni `getSelectedText()` e `getSelectedFinderItems()` [R1][R2][R3][R4]. Output "Replace Selection" che riscrive il testo selezionato al suo posto (v0.65, 18-06-2026) [R2][R5]. | **Accessibilità** ("quella che conta di più"); **Registrazione schermo** facoltativa, senza si perde solo lo screenshot [R3]. | `getSelectedText` fallisce se non c'è selezione; `getSelectedFinderItems` fallisce se il Finder non è in primo piano [R4]. App con poca accessibilità: solo screenshot + titolo. Browser: serve l'estensione Browser Companion [R3]. Nei terminali e nelle app che bloccano AX manda ⌘C e legge gli appunti [R6]. |
| **App ChatGPT (macOS)** | ⌥Spazio apre la finestra compagna sempre in primo piano; screenshot di una finestra o dello schermo dal "+"; "Work with Apps" legge il contenuto di IDE, terminali, Note [C1][C2]. | **Accessibilità** per leggere le app; per VS Code un'estensione dedicata; **Registrazione schermo** per gli screenshot, con riavvio dell'app [C1][C2]. | Solo app supportate (elenco in Impostazioni → Work with Apps → Manage Apps). Dei terminali legge **le ultime 200 righe**; negli editor la selezione più il testo vicino fino a un limite di troncamento [C1]. |
| **Claude desktop (macOS)** | Quick Entry: doppio ⌥ (o ⌥Spazio o scorciatoia a scelta) apre un campo in sovrimpressione; screenshot di un'area, clic su una finestra per allegarne il contenuto; dettatura con Caps Lock [A1][A2]. | **Accessibilità** per Quick Entry, **Registrazione schermo** per screenshot e finestre, **Riconoscimento vocale** per la dettatura (macOS 14+) [A1]. | L'app deve restare in esecuzione. Lentezza dell'allegato screenshot: 3–5 s su M1 Mac Studio, quasi immediato su M4 [A2]. Nessuna fonte primaria su Servizi, Condividi o Finder. |
| **Alfred** | Universal Actions: si seleziona file, testo o URL e si preme la scorciatoia (predefinita ⌘/); oltre 60 azioni; File Buffer per più file (⌥→) [L1]. | **Accessibilità obbligatoria** per le scorciatoie delle Universal Actions [L1]. | Conflitti di scorciatoia con altre app; a volte va tolto e rimesso il permesso [L1]. |
| **PopClip** (specialista della selezione) | Barra che appare sulla selezione. | Accessibilità. | Legge la selezione via AX; se l'app non la espone, simula ⌘C, legge e **ripristina** gli appunti (dicembre 2025) [P1]. |

### Temi ricorrenti

1. **Tutti chiedono l'Accessibilità al primo avvio.** È il permesso più potente di macOS (legge e controlla qualunque app). Nessuno dei quattro offre una via senza.
2. **Screenshot = Registrazione schermo**, con riavvio dell'app dopo il consenso [C2].
3. **Lettura della selezione fragile.** AX non funziona ovunque; il ripiego ⌘C sporca gli appunti se non li ripristina [P1][R6].
4. **Finder quasi ignorato.** Solo Raycast legge la selezione del Finder, e solo se il Finder è in primo piano [R4]. Nessuno ha un'azione nel menu contestuale.
5. **Le estensioni di sistema non si usano.** Servizi, Condividi, Azioni rapide e App Intents non compaiono nelle fonti dei quattro concorrenti per macOS. È lo spazio libero per Bubo.

## Punti d'ingresso di macOS 26

Premessa: Bubo si distribuisce come DMG firmato Developer ID e notarizzato, con Hardened Runtime e **senza sandbox** (`docs/brief.md`, `project.yml`). Le estensioni (`.appex`) invece **devono** essere in sandbox; un'app non in sandbox può contenerle, è l'approccio comune per le app distribuite fuori dal Mac App Store [S1][S2]. La scorciatoia globale di Bubo usa già Carbon `RegisterEventHotKey`, che non richiede Accessibilità (`Bubo/System/GlobalHotKey.swift`).

### 1. Servizi (menu Servizi)

- **API.** `NSApplication.servicesProvider` + chiave `NSServices` in Info.plist: `NSMessage`, `NSPortName`, `NSSendTypes` (testo), `NSSendFileTypes` (solo UTI, per i file), `NSReturnTypes`, `NSMenuItem`, `NSKeyEquivalent`, `NSRequiredContext`, `NSTimeout` [K1][K2]. `NSUpdateDynamicServices()` solo per servizi dinamici [K3].
- **Sandbox/entitlement.** Nessuno: il fornitore è l'app principale. Se Bubo non è aperto, il sistema lo avvia per servire la richiesta [K2].
- **Permessi.** Nessuno. Il testo arriva dal pasteboard del servizio, non via AX.
- **Dove compare.** Menu app → Servizi in ogni app Cocoa con selezione; menu contestuale del testo; menu contestuale del Finder per i file. L'utente può assegnare una scorciatoia da Impostazioni → Tastiera → Scorciatoie → Servizi.
- **Limiti.** Senza `NSRequiredContext` (anche vuoto) il servizio si registra ma **non compare** [K1]. Niente sottomenu: una voce per servizio [K1]. Timeout predefinito 30 s [K1]: Bubo deve rispondere subito (accetta e apre il Panel), non attendere la risposta del modello. Funziona solo nelle app che implementano `NSServicesMenuRequestor` (Cocoa sì; Electron e alcuni terminali in modo parziale; da verificare con un prototipo). Scorciatoia ⌘ a un carattere, da usare con parsimonia [K1].

### 2. Azioni rapide nel Finder (Action extension) e Finder Sync

- **Action extension "Quick Action".** Estensione `com.apple.services` con `NSExtensionActivationRule` sui tipi di file e `NSExtensionServiceAllowsFinderPreviewItem` per il pannello Anteprima del Finder; appare in Azioni rapide del menu contestuale [F1]. Chiavi per icona ed etichetta poco documentate [F1][F2].
  - **Sandbox:** sì, obbligatoria per l'`.appex` [S1]. Deve passare i file all'app principale: app group condiviso, schema URL o XPC.
  - **Permessi:** nessun TCC; l'utente può doverla attivare in Impostazioni → Generali → Elementi login ed estensioni → Finder [F1].
- **Finder Sync (`FIFinderSync`).** Menu contestuale (`FIMenuKind` per elementi, contenitore, barra laterale, pulsante della barra strumenti), badge, pulsante nella barra degli strumenti [F3][F4]. `selectedItemURLs` e `targetedURL` valgono solo dentro `menu(for:)` e le sue azioni [F3][F4].
  - **Limite di fondo:** agisce **solo** sulle cartelle in `directoryURLs` [F5]. Apple DTS avverte che è pensata per il badge delle cartelle sincronizzate e "può non funzionare bene" come estensione generale del Finder (settembre 2024) [S3]. Vive a lungo e deve essere leggerissima [F3].
  - **Sandbox:** sì. **Permessi:** attivazione manuale in Impostazioni. In macOS 15.0–15.1 l'interfaccia per attivarla era sparita, tornata con 15.2 [F6]: è un'API trascurata.
- **Comandi rapidi come Azione rapida.** Un comando rapido con "Usa come Azione rapida" compare nel menu contestuale del Finder e in Servizi, dopo l'attivazione in Impostazioni → Privacy e sicurezza → Estensioni → Finder [H1]. Bubo può fornire l'azione (App Intent, sotto) e un comando rapido pronto.

### 3. Estensione Condividi

- **API.** Share extension (`NSExtensionItem` in `extensionContext`), compare nel pulsante Condividi, nel menu contestuale → Condividi, nelle app che usano `NSSharingServicePicker` [F7].
- **Sandbox:** sì [S1]. Stessa questione di passaggio dati all'app principale del punto 2.
- **Permessi:** nessun TCC.
- **Limiti.** Interfaccia di dimensione vincolata, larghezza fissa [F7]. Utile per Safari (URL e pagina), Foto, Note; ridondante con Servizi per testo e file.

### 4. App Intents: Comandi rapidi, Spotlight, Siri

- **API.** `AppIntent` con parametri `String` e `IntentFile` (file con UTI, macOS 13+) [I1]; `AppShortcutsProvider` per le frasi pronte [I2]; `supportedModes` (macOS 26) per eseguire in background o portare l'app in primo piano [I3]; `IndexedEntity` (macOS 15+) per mettere in Spotlight entità come le Sessioni [I4].
- **Spotlight su macOS 26.** Spotlight esegue azioni delle app **senza aprirle**; l'utente può assegnare quick keys (es. "cb") [I5][H2]. Un intent compare in Spotlight solo se il parameter summary contiene tutti i parametri obbligatori senza default; non compare se `isDiscoverable: false` o `assistantOnly: true` [I5]. Con `IndexedEntity` il sistema genera da sé un'azione Find [I5]. L'azione "Use Model" di Comandi rapidi riceve le entità in JSON [I5].
- **Automazioni personali su Mac** (macOS 26): attivate da cartelle e dischi esterni [I5]. Esempio: "quando entra un PDF in Download, chiedi a Bubo un riassunto".
- **Sandbox/entitlement:** nessuno per l'app principale; gli intent vivono nel target app. **Permessi:** nessuno.
- **Limiti.** Apple estrae in forma anonima le frasi degli App Shortcuts per addestrare i modelli [I2]. Non trovata documentazione su cosa Spotlight conservi dei valori dei parametri: non darlo per scontato.

### 5. Testo selezionato via Accessibilità

- **API.** `AXIsProcessTrustedWithOptions` (con prompt) [X1]; `AXUIElementCreateSystemWide` → elemento focalizzato → `kAXSelectedTextAttribute` (`AXUIElement.h`) [X2]. Ripiego: `CGEvent` ⌘C, lettura del pasteboard, ripristino degli appunti [P1][R6].
- **Sandbox/entitlement.** Nessun entitlement; con Hardened Runtime basta il consenso TCC. Un'app in sandbox non potrebbe comunque usarla per il Mac App Store.
- **Permessi.** Accessibilità (Impostazioni → Privacy e sicurezza → Accessibilità). Il consenso è legato alla firma: ogni build di sviluppo con firma diversa lo perde.
- **Limiti.** App che non espongono la selezione (terminali, alcune Electron) [R3][R6]; `AXIsProcessTrusted` vero ma chiamate che falliscono con `.cannotComplete` in alcune app [X3]. Il ripiego ⌘C tocca gli appunti dell'utente.
- **Selezione del Finder senza AX.** Apple Events al Finder (`selection`): serve `com.apple.security.automation.apple-events` con Hardened Runtime e `NSAppleEventsUsageDescription`; macOS chiede il consenso "Automazione" una volta per app di destinazione [X4].

### 6. Trascinamento sull'Orb (NSPanel non attivante)

- **API.** `NSDraggingDestination` sulla vista del Panel (`OrbPanelView`, un `MTKView`): `registerForDraggedTypes([.fileURL, .string, .URL, .png, .tiff])`, poi `draggingEntered`/`performDragOperation` [D1][D2]. Il Panel è `NSPanel` con `.nonactivatingPanel`, livello `.floating`, su tutti gli Spazi (`Bubo/Panel/OrbPanelController.swift` su `main`).
- **Sandbox:** non serve; un'app non in sandbox legge i file trascinati senza segnalibri security-scoped.
- **Permessi.** Nessuno. Trascinare è **intento dell'utente**: macOS concede l'accesso anche a file in cartelle protette (Scrivania, Documenti, Download) e lo registra nell'attributo esteso `com.apple.macl` del file, fuori da `TCC.db` e non azzerabile con `tccutil` [D3].
- **Limiti e da verificare nel prototipo.** La destinazione di trascinamento funziona per finestra sotto il puntatore anche con app non attiva; non trovata documentazione specifica per `.nonactivatingPanel`: va provato. Il Panel è piccolo: serve un'area di rilascio che si allarga (lo stato Ascolto dell'Orb) durante `draggingEntered`. Il Panel sparisce quando l'HUD è aperto (CONTEXT.md): l'HUD deve accettare lo stesso trascinamento. `isMovableByWindowBackground` non deve intercettare il drop.

### Tabella riassuntiva

| Punto d'ingresso | Testo | File | Permesso TCC | Sandbox | Costo per l'utente |
|---|---|---|---|---|---|
| Servizi | sì | sì (Finder) | nessuno | no | zero; scorciatoia opzionale |
| Trascinamento sull'Orb | sì | sì | nessuno | no | zero |
| App Intents / Spotlight / Comandi rapidi | sì | sì (`IntentFile`) | nessuno | no | zero; quick key opzionale |
| Azione rapida (Action ext.) | no | sì | nessuno | `.appex` sì | attivazione in Impostazioni |
| Condividi | sì | sì | nessuno | `.appex` sì | attivazione per alcune app |
| Finder Sync | no | sì, solo cartelle osservate | nessuno | `.appex` sì | attivazione manuale |
| Selezione via AX + scorciatoia | sì | sì (Finder via AX o Apple Events) | Accessibilità (+ Automazione) | no | consenso potente |
| Screenshot / finestra | immagine | — | Registrazione schermo | no | consenso + riavvio (in fog nella mappa) |

## Implicazioni di "non sandbox + processo figlio"

- **TCC segue la catena dei processi.** macOS attribuisce un'operazione protetta al "codice responsabile", risalendo di norma dal figlio al padre; in una prova DTS un figlio ha usato il permesso Input Monitoring del padre (novembre 2025) [S4]. Anche le estensioni ereditano di norma i permessi dell'app che le contiene (settembre 2024) [S3]. Conseguenza: **se Bubo ottiene Accessibilità o Registrazione schermo, anche `claude` e i comandi Bash che l'agente lancia (es. `osascript`, `screencapture`) possono usarli**. Le richieste "Bubo vorrebbe accedere a Documenti" possono nascere da un comando dell'agente, non da un'azione di Bubo.
- **Regola candidata:** chiedere Accessibilità e Registrazione schermo solo quando l'utente attiva la funzione che li usa, mai all'avvio; valutare un processo di supporto separato per AX, così i figli dell'agente non lo ereditano. Da verificare: la catena di responsabilità "non è sempre seguita come ci si aspetta" [S4].
- **Se Bubo fosse in sandbox**, un eseguibile incluso dovrebbe ereditarne la sandbox [S5]: la CLI `claude` e i suoi comandi non potrebbero lavorare liberamente sul Progetto. Conferma la scelta del brief.
- **Estensioni in sandbox in un'app che non lo è:** ammesso [S2]. Serve un app group per lo scambio (Condividi, Azione rapida, Finder Sync).

## Il meglio da battere

Il riferimento è **Raycast** (selezione, Finder, schermo in un solo gesto) insieme a **Claude desktop** (doppio ⌥ con screenshot). Tutti e due partono chiedendo l'Accessibilità. Criteri candidati:

1. **Zero permessi per iniziare:** testo selezionato e file del Finder arrivano a Bubo con Servizi e trascinamento senza alcun consenso TCC. Accessibilità chiesta solo se l'utente attiva "scorciatoia sulla selezione".
2. **Dal gesto all'Orb in < 300 ms:** dal Servizio o dal drop, il Panel mostra l'Orb in Ascolto con il contenuto allegato entro 300 ms (Bubo già aperto).
3. **Appunti intatti:** se si usa il ripiego ⌘C, gli appunti sono ripristinati nel 100% dei casi (PopClip lo fa [P1]).
4. **Finder da qualunque posizione:** "Chiedi a Bubo" nel menu contestuale del Finder su qualunque file, non solo con il Finder in primo piano (limite di Raycast [R4]) e non solo in cartelle osservate (limite di Finder Sync [F5]).
5. **Spotlight:** "Chiedi a Bubo" eseguibile da Spotlight con una quick key, senza aprire l'HUD, risposta nel Panel.
6. **Domanda o Sessione dichiarata:** ogni ingresso crea una **Domanda** per default; se i file appartengono a un **Progetto** noto, Bubo propone di trasformarla in **Sessione**.

## Rischi e casi limite

- **Permessi ereditati dall'agente** (sopra): il rischio principale. Un'Accessibilità concessa per comodità diventa controllo dell'interfaccia per l'agente [S4].
- **Timeout Servizi a 30 s** [K1]: se Bubo aspetta il modello il servizio fallisce. Accettare e rispondere nel Panel.
- **Consenso perso a ogni build di sviluppo** con firma diversa: i test su AX vanno fatti con la firma Developer ID o con un profilo stabile.
- **Finder Sync trascurata da Apple** (interfaccia sparita in 15.0–15.1) [F6]; osservare `/` per avere il menu ovunque va contro l'uso previsto [S3]. Preferire Servizi e Azione rapida.
- **Scorciatoie in conflitto** (Alfred lo segnala [L1]): ⌥Spazio è la predefinita di ChatGPT, Raycast e Alfred e un'opzione di Claude desktop [C2][A1]. `GlobalHotKey.register` **non** lo rileva: `alreadyInUse` scatta solo tra registrazioni esclusive, e le altre app non la usano ([#64](https://github.com/mgiuditta/bubo/issues/64)). Difesa nell'onboarding della voce ([08-voce.md](08-voce.md)).
- **App senza supporto ai Servizi o ad AX** (Electron, terminali): comportamento da misurare in un prototipo su Terminal, VS Code, Slack, Safari, Chrome.
- **Drop su un Panel minuscolo e su tutti gli Spazi:** area di rilascio, schermo intero, HUD aperto.
- **Dati verso il cloud:** un file trascinato o selezionato finisce nel prompt. Per il principio della mappa, nessun dato del Progetto al cloud senza consenso: l'ingresso deve mostrare cosa viene inviato e a quale fornitore prima dell'invio, se il router sceglie un fornitore non locale.
- **Accesso concesso per intento resta sul file** (`com.apple.macl`), non azzerabile con `tccutil` [D3].
- **App Intents e dati Apple:** frasi degli App Shortcuts estratte in forma anonima [I2]; non mettere dati dell'utente nelle frasi.

## Mappa

Architettura comune in [INDEX.md](INDEX.md#architettura-comune-feature-16).

### Ingressi della v1

In ordine di costruzione ([#53](https://github.com/mgiuditta/bubo/issues/53)), tutti senza permessi TCC:

1. **Trascinamento sull'Orb** (Panel) e nell'HUD: file, cartelle, testo, URL, immagini.
2. **Servizio "Chiedi a Bubo"**: testo da qualunque app Cocoa, file e cartelle dal menu contestuale del Finder, con scorciatoia predefinita **⌘⇧O** (`NSKeyEquivalent` = `O`, O di Orb) che sostituisce la lettura della selezione via Accessibilità ([#61](https://github.com/mgiuditta/bubo/issues/61), [#64](https://github.com/mgiuditta/bubo/issues/64)). Nessuna ⌘⇧+lettera è libera in tutte le 7 app: ⌘⇧O perde solo in Finder (Documenti, ma lì i file arrivano dal menu contestuale e dal drop) e in VS Code (Go to Symbol), dove resta il menu Servizi. Scartate ⌘⇧X (barrato in Slack e nelle web app), ⌘⇧Y (Stickies), ⌘⇧L (Safari), ⌘⇧A/M (Terminal), ⌘⇧B, ⌘⇧F. Per cambiarla Bubo offre un pulsante che apre Impostazioni → Tastiera → Abbreviazioni → Servizi; nessuna hotkey Carbon doppione, che non riceverebbe la selezione.
3. **App Intents**: "Chiedi a Bubo" (testo, file facoltativi → Domanda) e "Nuova Sessione" (Progetto, testo → Sessione), da Spotlight con quick key e da Comandi rapidi. Frasi degli App Shortcuts senza dati dell'utente. Altri intent arrivano con le feature che li motivano (es. "Mostra nella Galassia", feature 11).
4. **"Allega finestra…"** nel prompt: `SCContentSharingPicker` + un solo scatto con `SCScreenshotManager`, subordinato alla prova a inizio costruzione (sotto). Uno screenshot dell'utente trascinato o incollato è già un Allegato e non dipende dalla prova.

Fuori dalla v1: Condividi, Azione rapida, Finder Sync, Accessibilità, Registrazione schermo classica (vedi Out of scope della mappa [#42](https://github.com/mgiuditta/bubo/issues/42)).

### Cosa nasce

- Ogni ingresso crea una **Domanda** con i suoi **Allegati**.
- File tutti dentro un Progetto noto → proposta "Trasforma in Sessione su <Progetto>".
- Cartella che è un repo git ma non è ancora un Progetto → proposta "Apri come Progetto e crea Sessione".
- File da più Progetti → Domanda, nessuna proposta.
- Trascinamento nell'HUD con una Sessione davanti → Allegato di quella Sessione; HUD senza Sessione davanti → nuova Domanda.
- App Intent "Nuova Sessione" → Sessione direttamente (il Progetto è un parametro).

### Invio

- **Trascinamento e Servizio**: il Panel si apre con l'Orb in Ascolto e l'Allegato nel prompt, poi aspetta testo o voce (⌥Spazio). Nessun Servizio con azione preconfezionata.
- **Servizio**: risponde al sistema subito (accetta, apre il Panel, ritorna) e non aspetta il modello; il timeout di 30 s non entra mai in gioco.
- **App Intent con testo**: invia subito, risposta nel Panel, l'HUD non si apre.

### Allegati e fornitori

- Senza consenso un Allegato va **solo a Claude o a un modello sul Mac**, anche un file fuori da ogni Progetto. Il router da solo sceglie solo modelli sul Mac (feature 10).
- Se l'utente sceglie un altro fornitore, la chip mostra "allegato → <fornitore>" e chiede conferma una volta per Allegato.
- Claude riceve i file **per percorso** e l'agente li legge; il trascinamento dà già l'accesso per intento (`com.apple.macl`).
- Gli altri fornitori ricevono il **contenuto** nel prompt solo per testo e PDF estratto, sotto un **tetto** per destinazione: al massimo metà del contesto del modello d'arrivo, il resto a istruzioni, domanda e risposta. Apple FM: ≤ 2.000 token misurati con `tokenCount(for:)` su `contextSize` (4.096); Ollama e LM Studio: metà del contesto letto dal server (`/api/show` per Ollama); client OpenAI-compatibili senza metadati: 32.000 token fissi. Oltre il tetto Bubo avvisa e propone Claude; niente spezzettamento in più passaggi in v1 ([#65](https://github.com/mgiuditta/bubo/issues/65)). Una cartella passa solo come percorso, quindi solo a Claude.
- Gli screenshot dal selettore seguono le stesse regole.

### Pipeline unica degli ingressi

Pezzo condiviso con la feature 08 (voce) e 10 (router). Una sola strada per voce, prompt scritto, trascinamento, Servizio e App Intent ([#57](https://github.com/mgiuditta/bubo/issues/57)):

1. **Ingresso → Richiesta**: ogni ingresso produce lo stesso valore: testo (può essere vuoto finché l'utente non scrive o parla), Allegati, destinazione (Domanda nuova, Sessione esistente, Sessione nuova con Progetto).
2. **Proposta**: se i file lo permettono, compare la proposta di Sessione (sopra). Finché non è accettata resta una Domanda.
3. **Classificazione**: una sola chiamata restituisce **Tipo di richiesta**, **Categoria** e **Variante** con un budget unico di 300 ms (Jev se passa il cancello della feature 10, altrimenti Apple FM + regole). Con Jev i due passi Categoria → Variante corrono in parallelo al Tipo. Variante incerta → resta il Blob con la Categoria scelta.
4. **Chip del router**: mostra modello, sforzo e Tinta previsti; l'utente la cambia con Tab prima dell'invio (feature 10). Qui si applica la regola degli Allegati.
5. **Orb**: all'invio entra subito in **Pensiero** sulla Forma corrente, prende la **Tinta** del fornitore previsto (Claude per le Sessioni, mai neutra; Tinta neutra per le Domande ad Apple FM, che non ha una Tinta propria), avvia il **Morph** verso la Variante appena c'è la decisione, passa a **Lavora** al primo token e a **Parla** con l'audio della Sintesi parlata. Un Morph iniziato arriva sempre in fondo.
6. **Invio** al motore: Sessione → ponte agente (`claude`); Domanda → fornitore scelto dal router.

La voce aggiunge solo un ramo prima del passo 3: previsione sul testo parziale durante l'Ascolto, **solo in locale** (Apple FM, mai Jev), con Morph solo al rilascio; se il testo finale conferma la previsione il Morph parte subito, altrimenti aspetta il classificatore (feature 08). I cambi di Variante durante il lavoro restano alla Regia del Morph (PRD fase 1–2).

### Isolamento di `claude`

`claude` si avvia con disclaim della responsabilità (`responsibility_spawnattrs_setdisclaim`): non eredita Microfono né altri permessi di Bubo e chiede da sé File e cartelle ([ADR 0005](../adr/0005-claude-senza-i-permessi-tcc-di-bubo.md)). Si applica nel ponte agente, ma nasce qui perché è la condizione che rende sicuri gli ingressi. Ripiego se la SPI sparisce o non isola: eredità del solo Microfono dichiarata nelle Impostazioni; Accessibilità e Registrazione schermo restano escluse.

### Moduli

- `System/Services/ServiceProvider`: `NSServices` in Info.plist (`NSRequiredContext` vuoto, testo + URL + `public.item`, `NSKeyEquivalent`), `servicesProvider` che crea la Richiesta e ritorna subito.
- `Panel/OrbDropTarget`: `NSDraggingDestination` sul Panel (`.fileURL`, `.string`, `.URL`, `.png`, `.tiff`); Ascolto già su `draggingEntered`. Lo stesso target nell'HUD, con la regola "Sessione davanti".
- `System/Intents/`: `AskBuboIntent`, `NewSessionIntent`, `BuboShortcuts` (`AppShortcutsProvider`), `supportedModes` per restare in background.
- `System/ScreenCapture/WindowPicker`: `SCContentSharingPicker` + `SCScreenshotManager`, uno scatto e stop.
- `Intake/` (pezzo condiviso): `Richiesta`, `Allegato`, `IntakePipeline` (passi 1–6 sopra), `AttachmentPolicy` (chi può ricevere cosa, tetto), `SessionProposal` (Progetto noto, repo nuovo, più Progetti).
- `Agent/ProcessSpawner`: `posix_spawn` con disclaim per `claude`.
- Dipendenze: `Router/` (classificatore e chip, feature 10), `Orb/` (Stati, Tinta, Morph), `Sessions/`, `Agent/AgentBridge`.

### Flusso

Gesto (drop, Servizio, intent, voce, prompt) → Richiesta con Allegati → Panel con l'Orb in Ascolto (o invio diretto per l'intent con testo) → testo o voce dell'utente → proposta di Sessione se applicabile → classificatore (Tipo, Categoria, Variante) → chip del router con regola degli Allegati → Pensiero + Tinta → Morph → risposta nel Panel.

### Casi limite

- Scorciatoia del Servizio già usata dall'app in primo piano (Finder, VS Code, altre): vince l'app; resta il menu Servizi, e il pulsante in Impostazioni porta dove cambiarla.
- Servizio invocato con Bubo chiuso: il sistema lo avvia; la Richiesta resta in attesa fino al Panel pronto.
- Drop a schermo intero e su tutti gli Spazi: il Panel ha `canJoinAllSpaces` + `fullScreenAuxiliary`; `isMovableByWindowBackground` non intercetta il drop ([#60](https://github.com/mgiuditta/bubo/issues/60)).
- Panel nascosto perché l'HUD è aperto: il drop va all'HUD con la regola della Sessione davanti.
- Allegato oltre il tetto verso un fornitore non Claude: avviso e proposta di Claude, nessun troncamento silenzioso.
- Cartella trascinata con fornitore non Claude: non si invia; si propone Claude.
- File in Documenti o Scrivania letto da `claude`: macOS chiede il permesso a nome di `claude`, non di Bubo; il messaggio deve essere comprensibile (prova ADR 0005).
- Selettore di finestra annullato: nessun Allegato, nessun indicatore di cattura acceso.
- Prova del selettore fallita: il pulsante "Allega finestra…" non si costruisce; restano trascinamento e incolla.
- App Intent con Progetto non più esistente: errore nel Panel, nessuna Sessione a metà.

### Prove a inizio costruzione

1. **Disclaim**: `sox` lanciato dall'agente non registra con il permesso Microfono di Bubo; gli avvisi di `claude` per File e cartelle sono comprensibili.
2. **Selettore**: scatto singolo col filtro di `SCContentSharingPicker` senza consenso TCC su macOS 26, in un'utenza pulita.
3. **Scorciatoia del Servizio**: ⌘⇧O fa partire il Servizio in Safari, Chrome, Mail, Terminal e Slack, anche dentro le web app nei browser.
4. **Tetto degli Allegati**: 2.000 token su Apple FM lasciano risposte complete per Fatto breve e Riassunto in italiano; si abbassa se la risposta viene troncata.

### Test

- Unità (Swift Testing): `SessionProposal` (un Progetto, repo nuovo, più Progetti, fuori da tutto), `AttachmentPolicy` (Claude, locale, altro fornitore sotto e sopra il tetto, cartella, screenshot), regola "Sessione davanti" nell'HUD.
- Integrazione: `NSPerformService` → Richiesta nel Panel, con tempo misurato; intent eseguiti con `AppIntent.perform()`.
- Manuale con log, sulle 7 app (Finder, Safari, Chrome, Mail, VS Code, Terminal, Slack): drop, Servizio dal menu e dalla scorciatoia, schermo intero, `NSApp.isActive` e `frontmostApplication` prima e dopo.
- Pipeline: le stesse 200 richieste etichettate della feature 08, entrate da prompt scritto e da Servizio, danno la stessa Categoria e Variante della voce.

## Specifica "migliore di"

Miglior concorrente: **Raycast** (selezione, Finder, schermo in un gesto) con **Claude desktop** (Quick Entry con screenshot) e **app ChatGPT** (Work with Apps). Tutti e tre partono chiedendo Accessibilità e Registrazione schermo, e il Finder lo legge solo Raycast con il Finder in primo piano.
Bubo li supera così:

- **Zero permessi TCC** in tutta la feature: nessuna richiesta di Accessibilità né di Registrazione schermo; testo selezionato e file del Finder arrivano con Servizi e trascinamento.
- **Agente isolato**: un processo lanciato dall'agente non usa nessun permesso TCC dato a Bubo (verificato con `sox` sul Microfono).
- **Dal gesto all'Orb in Ascolto con l'Allegato: < 300 ms** (p95, Bubo già aperto). Misurato in [#60](https://github.com/mgiuditta/bubo/issues/60): rilascio → Panel 1,2–2,5 ms, Servizio 3,0 ms; il margine resta al rendering dell'Orb.
- **Servizio**: controllo restituito al sistema in **< 1 s**.
- **Nessun furto del fuoco**: drop sul Panel e Servizio funzionano nel **100%** delle prove su Finder, Safari, Chrome, Mail, VS Code, Terminal e Slack, anche a schermo intero, con l'app di partenza sempre davanti.
- **Finder da qualunque posizione**: "Chiedi a Bubo" nel menu contestuale su qualunque file o cartella, con il Finder anche non in primo piano e fuori da cartelle osservate.
- **Scorciatoia sulla selezione** ⌘⇧O funzionante in 5 app su 7 (tutte tranne Finder e VS Code, dove resta il menu Servizi), senza Accessibilità.
- **Spotlight**: "Chiedi a Bubo" con quick key, senza aprire l'HUD, risposta nel Panel.
- **Schermo**: dal clic nel selettore all'Allegato nel prompt **≤ 500 ms**; indicatore di cattura spento dopo lo scatto; **0** catture continue o avviate dall'agente.
- **Domanda per default**: la Sessione nasce solo su proposta accettata (o dall'intent "Nuova Sessione", o con drop nell'HUD su una Sessione davanti).
- **Allegati**: **0 byte** di un Allegato a un fornitore diverso da Claude o dal Mac senza conferma esplicita per quell'Allegato.
- **Pipeline** (condivisa con 08 e 10, p95 su Mac M-series, modalità locale): Pensiero visibile **≤ 100 ms** dall'invio; inizio Morph **≤ 350 ms** se la previsione vocale regge, **≤ 600 ms** col classificatore finale; Morph finito **≤ 1,7 s**; classificazione in **≤ 300 ms**; **0 Morph falsi** e Categoria corretta **≥ 90%** sulle 200 richieste etichettate, qualunque sia l'ingresso.


## Fonti

Concorrenti
- R1. Raycast Manual, "AI Commands" — https://manual.raycast.com/ai/ai-commands.md
- R2. Raycast Manual, "Quick AI" — https://manual.raycast.com/ai/quick-ai
- R3. Raycast Manual, "Screen Awareness" — https://manual.raycast.com/ai/screen-awareness.md
- R4. Raycast API, "Environment" (`getSelectedText`, `getSelectedFinderItems`) — https://developers.raycast.com/api-reference/environment
- R5. Raycast changelog v0.65 (18-06-2026) — https://www.raycast.com/changelog/macos/0-65
- R6. Raycast Store, estensione "Quick Quote" (ripiego ⌘C nei terminali) — https://www.raycast.com/kumamaki/quick-quote
- C1. OpenAI Help, "Work with Apps on macOS" — https://help.openai.com/en/articles/10119604-work-with-apps-on-macos (pagina protetta da 403 al momento della ricerca; contenuto dall'estratto indicizzato); OpenAI Help, "How to install the Work with Apps Visual Studio Code extension" — https://help.openai.com/en/articles/10128592
- C2. OpenAI Help, "Using the ChatGPT macOS app" — https://help.openai.com/en/articles/9295245 (estratto indicizzato)
- A1. Claude Help Center, "Use quick entry with Claude Desktop on Mac" — https://support.claude.com/en/articles/12626668-use-quick-entry-with-claude-desktop-on-mac
- A2. MacStories, "Claude Adds Screenshot and Voice Shortcuts to Its Mac App" — https://www.macstories.net/news/claude-adds-screenshot-and-voice-shortcuts-to-its-mac-app/
- L1. Alfred Help, "Universal Actions" — https://www.alfredapp.com/help/features/universal-actions/
- P1. Forum PopClip, Nick Moore, "PopClip modifies the system clipboard on every activation" (07-12-2025) — https://forum.popclip.app/t/popclip-modifies-the-system-clipboard-on-every-activation/3681

Apple — Servizi
- K1. Services Implementation Guide, "Services Properties" — https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/properties.html
- K2. `NSApplication.servicesProvider` — https://developer.apple.com/documentation/appkit/nsapplication/servicesprovider
- K3. `NSUpdateDynamicServices()` — https://developer.apple.com/documentation/appkit/nsupdatedynamicservices()

Apple — Finder, Condividi, estensioni
- F1. Daniel Jalkut, "Finder Quick Actions" (03-09-2018) — https://indiestack.com/?p=709
- F2. `NSExtensionServiceFinderPreviewIconName` — https://developer.apple.com/documentation/bundleresources/information-property-list/nsextension/nsextensionattributes/nsextensionservicefinderpreviewiconname
- F3. App Extension Programming Guide, "Finder Sync" — https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html
- F4. `FIFinderSyncProtocol.menu(for:)` — https://developer.apple.com/documentation/findersync/fifindersyncprotocol/menu(for:)
- F5. `FIFinderSyncController.directoryURLs` — https://developer.apple.com/documentation/findersync/fifindersynccontroller/directoryurls
- F6. Apple Developer Forums 756711, "FinderSync extensions gone in macOS settings" (2024) — https://developer.apple.com/forums/thread/756711 ; M. Tsai (03-10-2024) — https://mjtsai.com/blog/2024/10/03/finder-sync-extensions-removed-from-system-settings-in-sequoia
- F7. App Extension Programming Guide, "Share" — https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html
- H1. Guida Comandi rapidi per Mac, "Usare i comandi rapidi come Azioni rapide" — https://support.apple.com/guide/shortcuts-mac/apd163eb9f95
- H2. Guida Mac, Spotlight: azioni e quick keys (macOS 26) — https://support.apple.com/guide/mac-help/mh26783

Apple — App Intents
- I1. `IntentFile` — https://developer.apple.com/documentation/appintents/intentfile
- I2. `AppShortcutsProvider` — https://developer.apple.com/documentation/appintents/appshortcutsprovider
- I3. `AppIntent.supportedModes` (macOS 26) — https://developer.apple.com/documentation/appintents/appintent/supportedmodes
- I4. `IndexedEntity` (macOS 15) — https://developer.apple.com/documentation/appintents/indexedentity
- I5. WWDC25 sessione 260, "Develop for Shortcuts and Spotlight with App Intents" (giugno 2025) — https://developer.apple.com/videos/play/wwdc2025/260/

Apple — Accessibilità, Apple Events, trascinamento
- X1. `AXIsProcessTrustedWithOptions` — https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions
- X2. `AXUIElement.h` — https://developer.apple.com/documentation/applicationservices/axuielement_h
- X3. Apple Developer Forums 794253, "AXIsProcessTrusted returns true, but AXUIElementCopyAttributeValue fails with .cannotComplete" — https://developer.apple.com/forums/thread/794253
- X4. Entitlement `com.apple.security.automation.apple-events` — https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events
- D1. `NSDraggingDestination` — https://developer.apple.com/documentation/appkit/nsdraggingdestination
- D2. Drag and Drop Programming Topics, "Receiving Drag Operations" — https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DragandDrop/Tasks/acceptingdrags.html
- D3. Apple Developer Forums 124121, Quinn, intento dedotto e `com.apple.macl` (ottobre 2019) — https://developer.apple.com/forums/thread/124121

Apple — sandbox e TCC
- S1. App Sandbox — https://developer.apple.com/documentation/security/app-sandbox ; Apple Developer Forums 738407 (estensioni macOS in sandbox) — https://developer.apple.com/forums/thread/738407
- S2. Apple Developer Forums 776568, Quinn: estensioni in sandbox dentro un'app che non lo è (marzo 2025) — https://developer.apple.com/forums/thread/776568
- S3. Apple Developer Forums 763956, Kevin Elliott: permessi TCC ereditati dalle estensioni; Finder Sync (settembre 2024) — https://developer.apple.com/forums/thread/763956
- S4. Apple Developer Forums 805245, Quinn: codice responsabile e figli di `Process` (novembre 2025) — https://developer.apple.com/forums/thread/805245
- S5. "Protecting user data with App Sandbox" (strumenti inclusi ereditano la sandbox) — https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox
- S6. Apple Developer Forums 765103, Quinn: `SCContentSharingPicker` senza Registrazione schermo (ottobre 2024) — https://developer.apple.com/forums/thread/765103
- S7. Apple Developer Forums 706187, Quinn: i servizi XPC condividono i permessi dell'app (maggio 2022) — https://developer.apple.com/forums/thread/706187
- S8. Qt, "The curious case of the responsible process" (disclaim) — https://www.qt.io/blog/the-curious-case-of-the-responsible-process

Prova misurata: spike [`spike/drop-panel`](https://github.com/mgiuditta/bubo/tree/spike/drop-panel/spike/drop-panel) ([#60](https://github.com/mgiuditta/bubo/issues/60)).

Codice di Bubo letto: `project.yml`, `docs/brief.md`, `Bubo/System/GlobalHotKey.swift`, `Bubo/Panel/OrbPanelController.swift` (ramo `main`). Nessun prototipo eseguito: le voci "da verificare" restano per il prototipo.
