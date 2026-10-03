# Ricerca #485 — Scorciatoia che cattura ciò che sta sotto il cursore

Ticket: [#485](https://github.com/mgiuditta/bubo/issues/485). Collegati: [#103](https://github.com/mgiuditta/bubo/issues/103) (Allega finestra con il selettore), [#100](https://github.com/mgiuditta/bubo/issues/100) (Chiedi a Bubo ⌘⇧O), [#98](https://github.com/mgiuditta/bubo/issues/98) (trascinamento, chiuso). Spec: [`docs/features/09-sistema.md`](../features/09-sistema.md). ADR: [0005](../adr/0005-claude-senza-i-permessi-tcc-di-bubo.md).
Ricerca del 2026-10-02 su macOS 26.7 (25G229), SDK 26.5. Fonti lette alla stessa data.

**Domanda.** Come può l'utente, con una scorciatoia globale e il cursore nativo, catturare ciò che sta sotto il puntatore (finestra, elemento, area) e passarlo a Bubo come Allegato?

## In sintesi

- **Del tutto automatico, senza un clic, non si può fare senza permessi.** Leggere i pixel di un'altra app richiede Registrazione schermo; leggere l'elemento e il suo testo richiede Accessibilità. Provato su questo Mac (sotto). Tutti e due sono esclusi dalla v1 ([ADR 0005](../adr/0005-claude-senza-i-permessi-tcc-di-bubo.md), [spec 09](../features/09-sistema.md#ingressi-della-v1)).
- **Strada consigliata, zero permessi:** scorciatoia globale Carbon → il selettore di sistema `SCContentSharingPicker` in modalità finestra singola → **un clic** sulla finestra che è già sotto il cursore → un solo scatto con `SCScreenshotManager` → PNG nella cartella delle Domande → `Allegato(fileAt:)` → Panel in Ascolto. In più, OCR di Vision sul PNG per dare il testo ai modelli sul Mac. È il "Allega finestra…" di #103 con una scorciatoia davanti: un clic in più rispetto a Claude desktop, ma nessun consenso, nessun avviso mensile.
- **Senza permesso si sa già quale finestra c'è sotto il cursore** (app, PID, ID, riquadro; non il titolo) con `CGWindowListCopyWindowInfo`: basta per scrivere "Finestra di Safari" nella chip e per controllare che il clic sia caduto sulla finestra attesa.
- **Modalità automatica** (scatto della finestra o dell'area sotto il cursore senza selettore, ed elemento AX): solo come opt-in futuro, con un nuovo ADR. Il disclaim provato in #66 la renderebbe isolabile dall'agente, ma resta l'avviso mensile di macOS 15+ e la spec 09 la esclude oggi. Decisione da `ready-for-human`.

## Vincoli già decisi

- **ADR 0005:** Bubo non chiede permessi TCC che l'agente erediterebbe se non può isolarli; per lo schermo, il selettore di ScreenCaptureKit e non la Registrazione schermo. Ripiego: "Accessibilità e Registrazione schermo restano comunque escluse".
- **Spec 09, Ingressi della v1:** "Fuori dalla v1: … Accessibilità, Registrazione schermo classica". "Allega finestra…" con `SCContentSharingPicker` + un solo scatto, subordinato alla prova di #103. Uno screenshot trascinato o incollato è già un Allegato.
- **Codice esistente:** `Allegato` (`Bubo/Intake/Allegato.swift`) ha già `kind: .image`, che va solo a Claude per percorso; `OrbDropTarget` salva un'immagine senza file come PNG in una cartella propria e crea `Allegato(fileAt:)`. `GlobalHotKey` (`Bubo/System/GlobalHotKey.swift`) usa Carbon `RegisterEventHotKey`, senza Accessibilità. Nel repo non c'è ancora codice ScreenCaptureKit, `CGWindowList` né `AXUIElement`.

## Prove sul Mac

Script Swift in `$TMPDIR/agent-485/probe/`, nessun permesso cambiato. La shell eredita i permessi di iTerm2 (che ha Registrazione schermo e Accessibilità); per vedere un processo **senza** consensi l'ho rilanciato con il disclaim (`responsibility_spawnattrs_setdisclaim`), come fa Bubo con `claude` (ADR 0005). Così il processo è responsabile di sé e non ha voci in TCC, cioè la situazione di Bubo appena installato.

| Chiamata | Con permessi (iTerm2) | Senza permessi (disclaim) |
|---|---|---|
| `CGPreflightScreenCaptureAccess()` (non chiede) | `true` | `false` |
| `AXIsProcessTrusted()` (non chiede) | `true` | `false` |
| `NSEvent.mouseLocation` | sì | **sì** |
| `CGWindowListCopyWindowInfo` | 33 finestre, 33 con titolo, 11 ms | **33 finestre, 1 con titolo**, 1,4 ms |
| Finestra sotto il cursore (primo strato 0 che contiene il punto) | iTerm2, ID 52, titolo "◑ Merge delle PR", riquadro | **iTerm2, ID 52, riquadro; titolo `nil`** |
| `AXUIElementCopyElementAtPosition` | `AXTextArea`, 27 ms | **`kAXErrorAPIDisabled` (-25211)** |

Conclusione: senza permessi Bubo sa **quale** app e finestra c'è sotto il cursore, non il titolo, non il contenuto, non l'elemento.

Tempi con permesso (iTerm2 responsabile, Mac M-series, monitor a 1×, finestra 960×1050):

| Passo | Tempo |
|---|---|
| `SCShareableContent` (elenco finestre) | 42 ms |
| `SCScreenshotManager.captureImage(contentFilter:)` di una finestra | 138 ms la prima volta, poi 43–44 ms |
| Scrittura PNG | 7–10 ms |
| OCR Vision `.accurate` (it + en) | 509 ms la prima volta, poi 153 ms |
| OCR Vision `.fast` | 143 ms |
| `captureImage(in:)` di 400×300 pt attorno al cursore | 54 ms |

Lo scatto in sé sta ben sotto i 500 ms di #103; il tempo vero è il clic dell'utente nel selettore, che non si misura da script. Il selettore non si può provare senza interfaccia: resta la prova di #103 in un'utenza pulita.

`/usr/sbin/screencapture` ha l'entitlement privato `com.apple.private.tcc.check-allow-on-responsible-process` con `kTCCServiceScreenCapture` (letto con `codesign -d --entitlements -`): controlla la Registrazione schermo **del processo responsabile**. Lanciato da Bubo, `screencapture -i` userebbe quindi il permesso di Bubo, che non c'è. Non è una via senza permesso (comportamento esatto in modalità interattiva non provato, per non far partire un avviso).

## Decisione (2026-10-03)

Presa in autonomia, scelte reversibili; costruita nella v1 minima (PR di #485).

- **Strada:** opzione 1. ⌃⌥⌘O apre `SCContentSharingPicker` in `singleWindow`, con Bubo escluso (`excludedBundleIDs`); il clic sulla finestra la scatta una volta con `SCScreenshotManager.captureImage(contentFilter:configuration:)`; `isActive = false` subito dopo, scattata o annullata. Il PNG va in `Domande/Allegati/<uuid>/Finestra di <App>.png` e diventa `Allegato(fileAt:)` `.image` nella Bolla, o nell'HUD se il Panel è nascosto. Codice: `Bubo/System/ScreenCapture/`.
- **Permessi:** nessuno. Niente Accessibilità, quindi niente testo dell'elemento sotto il cursore: il testo selezionato arriva con ⌘⇧O (#100). Niente Registrazione schermo. Il testo dell'elemento "se c'è il permesso" è scartato: ADR 0005 esclude Accessibilità e Registrazione schermo anche come opzione.
- **Finestra sotto il cursore:** `CGWindowListCopyWindowInfo`, senza permessi, saltando le finestre di Bubo e gli strati diversi da 0. Serve al nome della chip se il filtro non dice l'app, e a un log (`capture`) che dice se il clic è caduto sulla finestra che era sotto il cursore: risponde sul campo alla prima domanda di "Da verificare".
- **Scorciatoia:** ⌃⌥⌘O, modificabile in Impostazioni › Scorciatoie come le altre due, con lo stesso controllo dei conflitti; c'è anche la voce "Allega finestra…" nel menu di Bubo. Lontana da ⌘⇧3/4/5, ⌥Spazio, ⌃⌥Spazio e ⌘⇧O.
- **Senza selettore o senza scatto:** un avviso dice di usare ⌃⌘⇧4, Spazio, clic e ⌘V. Non apre Impostazioni di Sistema, perché non c'è un permesso da dare.
- **Fuori dalla v1:** OCR con Vision su `Allegato.text`, la modalità automatica (opzioni 4–6) e l'azione nell'app (#488).

## Le API, una per una

### ScreenCaptureKit

- **`SCContentSharingPicker`** (macOS 14): selettore di sistema; modalità `singleWindow`, `multipleWindows`, `singleApplication`, `multipleApplications`, `singleDisplay`; `present(using: .window)` porta l'utente dritto alla scelta di una finestra [A1][A2]. Con il selettore **non serve il permesso di Registrazione schermo** [W1]; Quinn (DTS) lo indica come la via per evitare l'avviso "bypassing the system private window picker" (ottobre 2024) [F1]. L'SDK 26.5 **non** ha una modalità area né un modo di preselezionare la finestra sotto il cursore (header `SCContentSharingPicker.h`, `SCShareableContent.h`): stile `none`, `window`, `display`, `application`.
- **`SCScreenshotManager`** (macOS 14) [A3]: `captureImage(contentFilter:configuration:)` (macOS 14) con il filtro che dà il selettore; `captureImage(in:)` per un rettangolo in punti (macOS 15.2); `captureScreenshot(contentFilter:configuration:)` e `captureScreenshot(rect:configuration:)` con `SCScreenshotConfiguration` (macOS 26) [A4]. Le varianti con rettangolo non passano dal selettore: richiedono Registrazione schermo.
- **`CGWindowListCreateImage`**: `SCREEN_CAPTURE_OBSOLETE(10.5,14.0,15.0)` nell'header `CGWindow.h`: obsoleta da macOS 15, sostituita da `SCScreenshotManager` [W1].

### CoreGraphics: finestra sotto il punto

`CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)` restituisce le finestre dall'alto in basso; la prima di strato 0 il cui `kCGWindowBounds` contiene il punto è quella sotto il cursore. Senza Registrazione schermo il titolo (`kCGWindowName`) delle altre app manca (prova sopra). Le coordinate sono con origine in alto a sinistra dello schermo principale: `NSEvent.mouseLocation` va ribaltato sull'altezza del primo schermo.

### Accessibilità: elemento e testo

`AXUIElementCopyElementAtPosition` dà l'elemento alle coordinate in alto a sinistra [A5]; senza consenso torna `kAXErrorAPIDisabled` (prova sopra). Con consenso dà ruolo, valore, testo selezionato. Esclusa dalla v1; il testo selezionato arriva già con il Servizio ⌘⇧O (#100).

### Vision: testo dall'immagine, senza permessi

`VNRecognizeTextRequest` lavora su un `CGImage` già in mano, sul Mac, senza consenso; 143–153 ms a caldo sulla finestra di prova (sopra). Utile perché oggi un Allegato `.image` va solo a Claude: l'OCR riempirebbe `Allegato.text` e lo renderebbe leggibile ai modelli sul Mac, con le stesse regole di `AttachmentPolicy`.

### Scorciatoia globale

- Carbon `RegisterEventHotKey` non chiede Accessibilità (già in `GlobalHotKey`). In macOS 15.0–15.1 falliva con `-9868` se i modificatori erano solo ⌥ e/o ⇧ (misura contro i keylogger); da 15.2 sono di nuovo ammessi [F2]. Meglio comunque un ⌘ o ⌃ nella combinazione: ⌥⇧lettera scrive caratteri (Ø).
- **Da evitare:** ⌘⇧3, ⌘⇧4, ⌘⇧5 (e ⌃ con questi: negli appunti) sono le scorciatoie di sistema per le istantanee [W3]; ⌥Spazio è già la voce di Bubo e la predefinita di ChatGPT e Raycast (spec 09); ⌘⇧O è il Servizio di #100.
- Come per ⌘⇧O, `alreadyInUse` scatta solo tra registrazioni Carbon esclusive: un conflitto con le scorciatoie di un'app in primo piano non si vede. Va scelta con la stessa prova sulle 7 app di #64. Candidata da provare: ⌃⌥⌘O ("O" di Orb, nessuna app delle 7 la usa per quanto noto; da verificare).

### Il permesso, se un giorno servisse

- Registrazione schermo su macOS 15+: avviso periodico che chiede di confermare l'accesso, passato in beta da settimanale a **mensile**, e non più a ogni riavvio [W4][W5]; l'entitlement `com.apple.developer.persistent-content-capture` lo evita ma non è documentato né concesso alle app comuni [W5].
- Durante la cattura il sistema mostra l'indicatore viola nella barra dei menu ("… sta registrando lo schermo"), non disattivabile [W6]; da 15.1 anche un punto viola nel Centro di Controllo [W6]. Per uno scatto singolo dal selettore l'indicatore deve spegnersi subito dopo (criterio di #103).
- Il permesso è legato alla firma e, senza disclaim, passerebbe a `claude` e ai suoi comandi (ADR 0005).

## Come fanno le app simili

| App | Gesto | Permessi | Note |
|---|---|---|---|
| **Claude desktop** | Quick Entry (doppio ⌥): trascina per un'area, clic su una finestra per allegarne il contenuto [C1] | Registrazione schermo (screenshot e finestre), Accessibilità (Quick Entry) [C1] | 3–5 s per allegare su M1, quasi immediato su M4 (spec 09, [A2] lì) |
| **ChatGPT per Mac** | ⌥Spazio, "+" → screenshot di finestra o schermo; "Work with Apps" legge le app via AX | Registrazione schermo, Accessibilità (spec 09, [C1][C2] lì) | Solo app supportate |
| **Raycast** | Screen Awareness: screenshot della finestra davanti nell'AI | Registrazione schermo facoltativa, Accessibilità (spec 09, [R3] lì) | Senza Registrazione schermo perde solo lo screenshot |
| **Shottr** | Area, finestra, OCR con Vision | Registrazione schermo al primo avvio; Accessibilità solo per lo scorrimento [C2] | — |
| **CleanShot X** | Area, finestra, schermo | Registrazione schermo (indicatore viola segnalato dagli utenti) [C3] | Nessuna pagina ufficiale trovata sui permessi |

Nessuna usa `SCContentSharingPicker` per gli screenshot (nessuna fonte trovata): è lo spazio libero per Bubo, come lo erano i Servizi nella spec 09.

## Opzioni

| # | Strada | Cosa prende | Gesto | Permessi TCC | Tempo stimato | Stato rispetto alle decisioni |
|---|---|---|---|---|---|---|
| 1 | **Scorciatoia → selettore finestra → scatto** (`SCContentSharingPicker` + `SCScreenshotManager`) | Finestra intera (immagine) + testo OCR | Tasto + 1 clic | **Nessuno** | scatto ~45–140 ms + OCR ~150 ms dopo il clic | Ammesso; dipende dalla prova #103 |
| 2 | **Istantanea di sistema negli appunti** (⌃⌘⇧4 o ⌃⌘⇧5) poi scorciatoia o ⌘V nel prompt | Area, finestra, schermo scelti col cursore nativo | Gesto di sistema + incolla | **Nessuno** | immediato | Ammesso (incolla = Allegato, spec 09) |
| 3 | Miniatura dell'istantanea trascinata sull'Orb | Come 2 | ⌘⇧4 + trascina | **Nessuno** | < 300 ms (#98) | Già costruito (#98) |
| 4 | Scorciatoia → finestra sotto il cursore (`CGWindowList`) → `captureScreenshot(contentFilter:)` senza selettore | Finestra sotto il cursore | Solo tasto | Registrazione schermo | ~50–150 ms | Escluso dalla v1 |
| 5 | Scorciatoia → area attorno al cursore (`captureImage(in:)`) | Rettangolo | Solo tasto | Registrazione schermo | ~55 ms | Escluso dalla v1 |
| 6 | Scorciatoia → elemento AX sotto il cursore (`AXUIElementCopyElementAtPosition`) | Ruolo, testo, valore | Solo tasto | Accessibilità | ~30 ms | Escluso dalla v1 (testo: c'è ⌘⇧O) |
| 7 | `screencapture -i` lanciato da Bubo | Area o finestra | Tasto + selezione | Registrazione schermo del responsabile (entitlement sopra) | — | Escluso; nessun vantaggio su 1 |
| 8 | `CGWindowListCreateImage` | Finestra o area | — | — | — | Obsoleta da macOS 15 |

## Raccomandazione

1. **v1: opzione 1.** Una scorciatoia globale ("Allega finestra", da scegliere con la prova delle 7 app) apre il selettore in `singleWindow` con Bubo escluso dalla configurazione; il clic sulla finestra sotto il cursore la scatta una volta; `SCContentSharingPicker.shared.isActive = false` subito dopo, così l'indicatore si spegne. Il PNG va in una cartella propria dentro le Domande e diventa `Allegato(fileAt:)` di tipo `.image`; il nome nella chip viene da `SCWindow.owningApplication` ("Finestra di Safari"). La stessa funzione serve il pulsante "Allega finestra…" del prompt: **un solo modulo** (`System/ScreenCapture/WindowPicker`, già previsto dalla spec 09) con due ingressi.
2. **OCR facoltativo e in locale**: Vision `.accurate` (it, en) sul PNG riempie `Allegato.text`, così l'immagine raggiunge anche i modelli sul Mac secondo `AttachmentPolicy`. Non ritarda il Panel: la chip compare subito, il testo arriva dopo.
3. **Rendere visibili le opzioni 2 e 3** (onboarding o suggerimento nel prompt): sono il cursore nativo con area libera, senza permessi, e funzionano già.
4. **Modalità automatica (4–6) fuori dalla v1.** Se il prodotto la vuole, serve un ADR che superi la clausola "restano comunque escluse" di ADR 0005, con: richiesta solo all'attivazione della funzione, disclaim verificato anche per Registrazione schermo (#66 ha provato Microfono e File e cartelle), testo per l'avviso mensile. Ticket `ready-for-human`.

## Rischi

- **La prova #103 può fallire**: se il selettore + `SCScreenshotManager` chiedesse comunque il consenso in un'utenza pulita, l'opzione 1 cade e restano 2 e 3. Va fatta per prima.
- **Un clic in più dei concorrenti**: Claude desktop e ChatGPT scattano senza selettore, al prezzo di due permessi. Il racconto di Bubo è "zero permessi"; il clic è il prezzo, va detto nel prompt.
- **Il selettore non preseleziona** la finestra sotto il cursore e non ha una modalità area (SDK 26.5): se l'utente vuole un'area, l'opzione 2.
- **Indicatore di cattura acceso** se il selettore resta attivo: spegnerlo dopo lo scatto e su annullo (criteri di #103).
- **Finestre di Bubo nello scatto**: escluderle nella configurazione del selettore, e nascondere il Panel durante la scelta se coprisse la finestra.
- **Dati sensibili nello scatto**: una finestra può contenere password o messaggi; l'immagine va solo a Claude (o al Mac) per `AttachmentPolicy`, e la chip deve mostrarla prima dell'invio.
- **Conflitti di scorciatoia** non rilevabili da Carbon (vedi #64): prova sulle 7 app.
- **API giovani**: `captureScreenshot` e `SCScreenshotConfiguration` sono di macOS 26 e poco usate; per la v1 basta `captureImage(contentFilter:configuration:)` (macOS 14).
- **Bubo responsabile dei processi**: niente `screencapture` lanciato da Bubo o dall'agente per questa funzione (entitlement sopra, ADR 0005).

## Da verificare (non provato qui)

- Il selettore in `singleWindow` evidenzia la finestra sotto il cursore all'apertura (il clic "cade" senza muovere il mouse)?
- Selettore + scatto davvero senza voce TCC in un'utenza pulita su macOS 26 (#103).
- Tempo reale dal tasto all'Allegato, selettore compreso, su Retina 2×.
- Comportamento con app a schermo intero e su più Spazi (il selettore è del sistema).

## Fonti

Apple — documentazione e header
- A1. `SCContentSharingPicker` — https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker
- A2. `SCContentSharingPickerMode` — https://developer.apple.com/documentation/screencapturekit/sccontentsharingpickermode
- A3. `SCScreenshotManager` — https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager
- A4. `SCScreenshotConfiguration` (macOS 26) — https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration ; `captureScreenshot(rect:configuration:completionHandler:)` — https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/capturescreenshot(rect:configuration:completionhandler:)
- A5. `AXUIElementCopyElementAtPosition` — https://developer.apple.com/documentation/applicationservices/1462077-axuielementcopyelementatposition
- A6. `CGPreflightScreenCaptureAccess()` — https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess()
- Header dell'SDK macOS 26.5: `ScreenCaptureKit/SCScreenshotManager.h`, `SCContentSharingPicker.h`, `SCShareableContent.h`, `CoreGraphics/CGWindow.h`.

Apple — WWDC e forum
- W1. WWDC23 sessione 10136, "What's new in ScreenCaptureKit" (selettore senza permesso, `SCScreenshotManager` al posto di `CGWindowListCreateImage`) — https://developer.apple.com/videos/play/wwdc2023/10136/
- W3. Supporto Apple, "Fare un'istantanea dello schermo sul Mac" — https://support.apple.com/it-it/102646
- F1. Apple Developer Forums 765103, Quinn: `SCContentSharingPicker` per evitare l'avviso del selettore privato (ottobre 2024) — https://developer.apple.com/forums/thread/765103
- F2. Apple Developer Forums 763878, Frameworks Engineer: `RegisterEventHotKey` con solo ⌥/⇧ in macOS 15 e correzione in 15.2 beta 2 (settembre e novembre 2024) — https://developer.apple.com/forums/thread/763878

Stampa e terzi (avviso mensile, indicatore)
- W4. 9to5Mac, "macOS Sequoia screen recording prompt monthly" (14-08-2024) — https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/
- W5. TidBITS, "How to avoid Sequoia's repetitive screen recording permissions prompts" (23-09-2024) — https://tidbits.com/2024/09/23/how-to-avoid-sequoias-repetitive-screen-recording-permissions-prompts/
- W6. Bartender, "macOS purple menu bar item" — https://www.macbartender.com/Bartender5/ScreenCaptureMenuBarItem/

App simili
- C1. Claude Help Center, "Use quick entry with Claude Desktop on Mac" — https://support.claude.com/en/articles/12626668-use-quick-entry-with-claude-desktop-on-mac
- C2. Shottr, "Start guide" — https://shottr.cc/kb/startguide
- C3. Mac Power Users Talk, "Remove 'CleanShot X' is accessing your screen?" — https://talk.macpowerusers.com/t/remove-cleanshot-x-is-accessing-your-screen/39909
- ChatGPT e Raycast: fonti già in [spec 09](../features/09-sistema.md#fonti) (C1, C2, R3).

Codice di Bubo letto (`origin/main` 98947a9): `Bubo/Intake/Allegato.swift`, `Bubo/Panel/OrbDropTarget.swift`, `Bubo/System/GlobalHotKey.swift`, `project.yml`, `docs/features/09-sistema.md`, `docs/adr/0005-claude-senza-i-permessi-tcc-di-bubo.md`, `CONTEXT.md` (Allegato).
