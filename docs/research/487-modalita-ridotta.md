# Ricerca 487: modalità ridotta in basso a destra con Orb piccolo

Ticket: [#487](https://github.com/mgiuditta/bubo/issues/487). Data: 2 ottobre 2026. Ramo usa-e-getta, nessun codice.

Domanda: come deve essere una modalità ridotta di Bubo, cioè un pannello piccolo nell'angolo in basso a destra con l'Orb più piccolo, usabile su schermi piccoli e mentre si lavora in altre app?

## In breve

- **Il Panel c'è già e fa quasi tutto.** `OrbPanelController` è un `NSPanel` `.borderless` + `.nonactivatingPanel`, livello `.floating`, `canJoinAllSpaces` + `fullScreenAuxiliary`, predefinito in basso a destra, con griglia 3×3, zona ricordata per schermo, clic passante fuori da un cerchio, pausa su `occlusionState` e una bolla con prompt e risposta che non attiva Bubo (#25, #29, #30, #31, #383). La modalità ridotta **non è un terzo contenitore**: è il Panel in una **taglia ridotta**. Così resta vera la regola di `CONTEXT.md`: l'Orb vive in un Panel o in un HUD, uno alla volta.
- **Proposta**: Panel ridotto **112 × 112 pt**, Orb visibile **circa 62 pt** di diametro, drawable a **2×** (224 × 224 px). Cerchio di clic di **37 pt** di raggio. Accanto all'Orb, verso il centro, compare una **pillola di stato** solo quando c'è qualcosa da dire (Sessioni in Attende te, risposta pronta). Prompt e risposta restano nella bolla esistente; l'HUD resta a un clic.
- **Costo Metal stimato**: circa **0,5 ms GPU per fotogramma su M4 Max** (3% di un fotogramma a 60 fps), contro 1,40 ms del Panel da 240 pt. Con **30 fps in Riposo** il costo medio scende ancora della metà. RAM dei drawable: circa 0,6 MB invece di 1,55 MB.
- **Da non fare**: comandi rivelati solo al passaggio del puntatore (alla Superwhisper), perché non arrivano da tastiera né a VoiceOver; ridimensionamento libero, perché #25 lo ha escluso.

## Cosa c'è già in Bubo

Letto su `origin/main` (98947a9):

| Pezzo | Dove | Cosa fa oggi |
|---|---|---|
| Finestra | `Bubo/Panel/OrbPanelController.swift` | `NSPanel` 240 pt fisso, `.floating`, `[.canJoinAllSpaces, .fullScreenAuxiliary]`, senza ombra, `orderFrontRegardless()`, mai `NSApp.activate`. |
| Posizione | `Bubo/Panel/PanelPlacement.swift` | Griglia 3×3 su `visibleFrame`, predefinita `bottomRight`, zona ricordata per schermo (UUID del display), ritorno al principale se lo schermo sparisce. Il Panel è a filo del bordo: il margine visivo lo dà l'alone trasparente attorno all'Orb. |
| Clic | `Bubo/Panel/PanelPointer.swift` | Cerchio fisso di 80 pt di raggio; fuori il clic passa alle finestre sotto (`ignoresMouseEvents`). Clic apre l'HUD, trascinamento sposta, tasto destro apre il menu della barra. |
| Bolla | `Bubo/Panel/PanelBubbleView.swift`, `PanelBubbleWindow.swift` | `NSPanel` figlio largo 360 pt, Liquid Glass, prompt, risposta in streaming, sottotitoli della Sintesi parlata, «Trasforma in Sessione». Prende la tastiera senza attivare Bubo. Si apre verso il centro dello schermo. |
| Rendering | `Bubo/Orb/OrbRenderer.swift`, `OrbShading.h` | Un triangolo a schermo pieno, raymarch SDF fino a 90 passi per pixel con sfera di contenimento; `frame = 1,3` rimpicciolisce l'Orb per far stare l'alone. Scala 1,5×, 60 fps, pausa quando coperto. |
| Budget | `BuboPerfTests/PerfBudgets.swift`, spec 25 | Orb 60 fps, tempo GPU p95 ≤ 4 ms; 0 fotogrammi coperto (invariante); Bubo a riposo ≤ 100 MB. |
| Stato delle Sessioni | `Bubo/MenuBar/MenuBarGlyph.swift` | Punto Lume sul gufo della barra quando ci sono Sessioni in Attende te, conteggio per VoiceOver. |
| Energia | `Bubo/Index/EnergyGauge.swift` | Legge già `ProcessInfo.isLowPowerModeEnabled` e la batteria. |

Decisioni di #25 che la ridotta eredita: zona della griglia, una zona per schermo, tutti gli Spaces e sopra lo schermo intero, visibile nelle condivisioni schermo (da rivalutare), un solo Orb alla volta, «Mostra Panel» nel menu e in Impostazioni › Generale. **Una sola decisione di #25 cambia**: «Ridimensionamento: no, fisso a 240 pt» diventa «due taglie fisse, 240 e 112». Non è un ridimensionamento libero.

Misure di #8 (prototipo `prototype/blob-metal`, M4 Max, ms GPU per fotogramma → % a 60 fps):

| Panel | 1,5× | 2× |
|---|---|---|
| 160 pt | 0,76 → 4,5% | 0,90 → 5,4% |
| 240 pt | 1,40 → 8,4% | 1,51 → 9,1% |
| 400 pt | 2,18 → 13% | 4,30 → 26% |

## Fonti primarie Apple

### Pannelli e finestre

- **HIG, Panels** ([link](https://developer.apple.com/design/human-interface-guidelines/panels)): un pannello «typically floats above other open windows»; lo stile HUD è «darker and translucent»; «Keep HUDs small. HUDs are designed to be unobtrusively useful, so letting them grow too large defeats their primary purpose». La stessa pagina dice anche «When your app is inactive, hide all of its panels»: Bubo se ne discosta di proposito, come Picture in Picture e gli indicatori di Granola e Superwhisper, perché il Panel serve proprio mentre si lavora in altre app (decisione di #25). La ridotta va nella stessa direzione delle HIG: più piccola, meno colore, nessun controllo che competa con il contenuto.
- **`NSWindow.StyleMask.nonactivatingPanel`** ([link](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)): «a panel or a subclass of NSPanel that does not activate the owning app». È ciò che tiene davanti l'app dell'utente.
- **`NSPanel.becomesKeyOnlyIfNeeded`** ([link](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded)): in un pannello non attivante la tastiera arriva solo se la vista colpita restituisce `true` da `needsPanelToBecomeKey`. La bolla già fa `canBecomeKey = true` e `makeKey()` senza attivare; la pillola di stato non deve prendere la tastiera.
- **`NSWindow.Level`** ([link](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct)): `floating` è «useful for floating palettes»; i livelli contano più dell'ordine dentro un livello. `.floating` sta sotto `statusBar`, menu a comparsa e Dock: il Dock nascosto che compare copre il Panel per un momento, ed è giusto così.
- **`NSWindow.CollectionBehavior`** ([link](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct)): `canJoinAllSpaces` «The window can appear in all spaces»; `fullScreenAuxiliary` «The window displays on the same space as the full screen window»; `stationary` «Mission Control doesn't affect the window, so it stays visible and stationary, like the desktop window»; `transient` «floats in Spaces and hides in Mission Control»; `ignoresCycle` esclude la finestra dal ciclo delle finestre. `primary`, `auxiliary` e `canJoinAllApplications` valgono per schermo intero e Stage Manager e si escludono a vicenda.
- **`NSScreen.visibleFrame`** ([link](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe)): esclude Dock e barra dei menu; «Don't cache the rectangle»; con il Dock nascosto può essere comunque più piccolo dello schermo, perché il sistema tiene un bordo per far comparire il Dock.
- **`NSWindow.occlusionState`** ([link](https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.property)): `visible` vuol dire che almeno una parte è visibile; «a completely transparent window may also be considered visible». Il Panel quasi tutto trasparente può risultare «visibile» anche quando l'Orb è coperto: vale anche per la ridotta, ma con meno area trasparente il caso è più raro.
- **`NSWindow.sharingType`** ([link](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.property)): controlla l'accesso di altri processi al contenuto della finestra; è la leva per nascondere il Panel nelle condivisioni schermo, rimandata da #25.

### Picture in Picture

- **AVKit, `AVPictureInPictureController`** ([link](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller)): PiP è «a floating, resizable window». Le HIG di [Playing video](https://developer.apple.com/design/human-interface-guidelines/playing-video) non hanno indicazioni su posizione e angoli per macOS.
- Comportamento su Mac, da fonte secondaria ([iMore](https://www.imore.com/how-use-picture-picture-anywhere-your-mac)): la finestra PiP **va all'angolo più vicino** al rilascio; tenendo ⌘ si posa ovunque; si ridimensiona dai bordi. È lo stesso modello della griglia 3×3 di Bubo, con meno zone.

### Movimento, accessibilità, energia

- **HIG, Accessibility** ([link](https://developer.apple.com/design/human-interface-guidelines/accessibility)): su macOS i controlli hanno taglia predefinita **28 × 28 pt** e minima **20 × 20 pt**. Con Riduci movimento: ridurre «automatic and repetitive animations, including zooming, scaling, and peripheral motion». Un Orb che respira in un angolo è movimento periferico per definizione.
- **HIG, Motion** ([link](https://developer.apple.com/design/human-interface-guidelines/motion)): «Make motion optional… avoid using it as the only way to communicate important information».
- **`NSWorkspace.accessibilityDisplayShouldReduceMotion`** ([link](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion)): «avoid large animations, especially those that simulate the third dimension»; aggiornamenti con `accessibilityDisplayOptionsDidChangeNotification`.
- **`MTKView.preferredFramesPerSecond`** ([link](https://developer.apple.com/documentation/metalkit/mtkview/preferredframespersecond)): con un valore più basso la vista sceglie un divisore della frequenza dello schermo (30, 20, 15). **`enableSetNeedsDisplay`** ([link](https://developer.apple.com/documentation/metalkit/mtkview/enablesetneedsdisplay)) con `isPaused` rende il disegno guidato dagli eventi.
- **`ProcessInfo.isLowPowerModeEnabled`** ([link](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled)): in Risparmio energia il sistema riduce CPU e GPU; notifica `NSProcessInfoPowerStateDidChange`.
- **WWDC22, «Power down: Improve battery consumption»** ([link](https://developer.apple.com/videos/play/wwdc2022/10083/)): «Your app may have secondary elements refreshing at a higher rate than necessary»; portare un'animazione secondaria da 60 a 30 fps fa risparmiare «up to 20%» del consumo nell'esempio della sessione (iPhone). Vedi anche [WWDC21, Optimize for variable refresh rate displays](https://developer.apple.com/videos/play/wwdc2021/10147/).
- **WWDC25, «Build an AppKit app with the new design»** ([link](https://developer.apple.com/videos/play/wwdc2025/310/)): Liquid Glass con `NSGlassEffectView`; «Limit your use of Liquid Glass to the most important elements». Più forme di vetro vicine vanno in `NSGlassEffectContainerView`, anche per le prestazioni: vale per Orb, pillola e bolla se diventano vicine.

## Esempi di app

| App | Cosa fa la sua forma piccola | Fonte |
|---|---|---|
| **ChatGPT per Mac** | «Companion window» che resta davanti a tutte le finestre; ⌥Spazio la apre ovunque, anche sopra Safari a schermo intero; posizione e scorciatoia nelle Impostazioni. Contiene un prompt e la chat, non uno stato. | [Note di rilascio OpenAI](https://help.openai.com/en/articles/9703738-chatgpt-macos-app-release-notes) (bloccata da qui con 403; riportata da [AlternativeTo](https://alternativeto.net/news/2024/8/openai-introduces-handy-companion-window-for-chatgpt-on-macos) e [iMore](https://www.imore.com/apps/mac-apps/chatgpt-upgrade-for-mac-now-better-than-ever-for-productivity)) |
| **Raycast** | AI Chat con «Always on Top» attivabile dall'Action Panel o nelle Impostazioni; da Quick AI ⌘J porta la conversazione nella finestra grande: «The full conversation history, selected model, and any attachments transfer automatically». | [Manuale Raycast, AI Chat](https://manual.raycast.com/ai/ai-chat.md) |
| **Superwhisper** | «Mini recording window»: un indicatore minimo sempre visibile; durante la registrazione mostra la forma d'onda; al passaggio del puntatore compaiono cambio modalità, avvio, espansione alla finestra normale; tasto destro «Expand Window». | [Docs Superwhisper, Recording Window](https://superwhisper.com/docs/get-started/interface-rec-window) |
| **Granola** | Mentre trascrive e si è in un'altra app, un indicatore fluttua sul lato destro; clic riporta alla nota, si trascina da una maniglia in basso. Compare solo quando serve. | [Granola, Transcription](https://docs.granola.ai/help-center/taking-notes/transcription) |
| **Picture in Picture** | Finestra fluttuante che si aggancia all'angolo più vicino. | vedi sopra |

Cosa se ne ricava:

1. **Due livelli, non tre**: forma piccola (indicatore + un gesto) e finestra piena. Raycast e Superwhisper passano dalla piccola alla grande con un gesto solo, portandosi dietro il contesto. In Bubo il contesto è la Domanda, che bolla e HUD già condividono.
2. **Lo stato vive nella forma piccola**: Superwhisper mostra la forma d'onda, Granola il fatto che sta trascrivendo. In Bubo lo fa già l'Orb con lo Stato e la Tinta; manca solo lo stato delle **Sessioni**, che oggi è nella barra dei menu.
3. **Comparire solo quando serve** (Granola) è la parte più rispettosa dello spazio. Per Bubo vale per la pillola, non per l'Orb, che l'utente sceglie di vedere.
4. **Da evitare**: i comandi solo al passaggio del puntatore di Superwhisper. Non esistono per la tastiera e per VoiceOver.

## Raccomandazione

### Taglia e posizione

- **Panel ridotto: finestra 112 × 112 pt**, stesso `NSPanel`, stessa griglia 3×3 e stessa memoria per schermo. Predefinita in basso a destra.
- **Orb visibile circa 62 pt**: con `frame = 1,3` il Blob occupa circa il 55% del lato (raggio 0,92 a distanza 3, campo di vista dello shader), come oggi nel Panel da 240 pt (circa 132 pt). Sotto i 44 pt Tinta e Stato si leggono ancora, ma le Forme del Catalogo diventano macchie: vedi le domande.
- **Cerchio di clic: 37 pt di raggio** (stessa proporzione di 80/240), cioè un bersaglio di 74 pt, ben sopra i 28 pt delle HIG.
- **Margini rispetto al Dock**: nessun margine aggiunto. `visibleFrame` esclude già il Dock e l'alone dà circa 25 pt d'aria tra l'Orb e il bordo della finestra. Il Panel va riletto quando cambia `visibleFrame` (Dock spostato, ingrandito, nascosto), non solo su `didChangeScreenParametersNotification`: da verificare nel prototipo se quella notifica basta.
- **Due taglie fisse, nessun ridimensionamento libero**: «Panel ridotto» nel menu della barra e nel menu destro dell'Orb, più la scelta in Impostazioni › Generale. La taglia si ricorda **per schermo**, come la zona: su un portatile ridotto, sul monitor esterno normale.
- **Drawable a 2×**: 224 × 224 px, nitido su Retina e comunque 2,6 volte meno pixel del Panel attuale a 1,5×.

### Cosa contiene

| Elemento | Quando si vede | Cosa fa |
|---|---|---|
| **Orb** | sempre | Stato e Tinta come oggi. Clic apre l'HUD, trascinamento sposta, tasto destro il menu. |
| **Pillola di stato** (capsula alta 24 pt, finestra figlia come la bolla, verso il centro) | solo con Sessioni in **Attende te**, con **Errore**, o con una risposta pronta e non letta mentre la bolla è chiusa | Testo breve in SF Mono: «2 ti attendono», «Risposta pronta». Punto Lume per Attende te (unico uso del segnale, come in barra), mai solo colore. Clic: apre l'HUD sulla Sessione (`HUDPresenter.show(session:)`) o riapre la bolla. Sparisce da sola quando lo stato si risolve. |
| **Bolla** | come oggi: «Chiedi nel Panel», drop, «Chiedi a Bubo», voce | La stessa `PanelBubbleView`, larga 360 pt; con altezza massima al 50% di `visibleFrame` e scorrimento, in entrambe le taglie. |

Non contiene: elenco delle Sessioni, cronologia, router, costi. Sono dell'HUD.

### Come si espande

1. **Ridotto → bolla**: la scorciatoia o l'azione VoiceOver «Chiedi nel Panel», un drop sull'Orb, una risposta che parte. La bolla cresce dall'Orb (`Motion.emphasized`) o appare in dissolvenza con Riduci movimento, come oggi.
2. **Ridotto o bolla → HUD**: clic sull'Orb, ⌥Spazio, «Trasforma in Sessione», clic sulla pillola. Il Panel sparisce e torna alla chiusura dell'HUD (regola di `CONTEXT.md`). Nessuna animazione di «crescita» dell'Orb verso l'HUD: sono due finestre e due renderer, e una transizione condivisa costerebbe più di quanto rende.
3. **Normale ↔ ridotto**: cambio di taglia sul posto, ancorato alla zona (l'Orb resta nell'angolo). Animazione di `setFrame` 150–250 ms come il resto del contenitore; con Riduci movimento, cambio secco.

### Spaces, schermo intero, più monitor

- **Spaces e schermo intero**: invariati, `canJoinAllSpaces` + `fullScreenAuxiliary`, livello `.floating`. Da aggiungere **`ignoresCycle`**, perché il Panel non deve comparire nel ciclo delle finestre. Da provare **`stationary`** (resta fermo e visibile in Mission Control, come la scrivania) contro `transient` (sparisce in Mission Control): domanda per il prototipo.
- **Più monitor**: invariato, la ridotta eredita `PanelPlacement`. In più la taglia per schermo.
- **Condivisione schermo**: `sharingType = .none` resta una scelta da prendere a parte (#25). La ridotta la rende meno urgente, perché copre meno.

### Costo Metal stimato

Interpolando le misure di #8 a 1,5× (0,76 ms a 160 pt, 1,40 ms a 240 pt) con un costo fisso più un costo per area si ottiene circa **0,25 ms + 2·10⁻⁵ ms/pt²**. Il 2× di #8 costa circa il 15–20% in più dell'1,5× alle taglie piccole.

| Configurazione | Pixel del drawable | GPU stimata, M4 Max | % di un fotogramma a 60 fps |
|---|---|---|---|
| Panel attuale, 240 pt a 1,5× | 129.600 | 1,40 ms (misurato) | 8,4% |
| **Ridotto, 112 pt a 1,5×** | 28.224 | ≈ 0,50 ms | ≈ 3% |
| **Ridotto, 112 pt a 2×** | 50.176 | ≈ 0,60 ms | ≈ 3,6% |

- Sono stime da misure su M4 Max; su M1 i tempi sono più alti in proporzione. Il budget della spec 25 (p95 ≤ 4 ms) resta largo in ogni caso.
- Il pixel che conta è quello che colpisce la sfera di contenimento: fuori, lo shader calcola solo l'alone senza raymarch. Nella ridotta la proporzione è la stessa del Panel attuale, quindi la stima per area regge.
- **Batteria**: la voce che pesa davvero è la frequenza, non la taglia. Proposta: **30 fps in Riposo, 60 fps in Ascolto, Pensiero, Parla, Lavora e durante un Morph**. Con Risparmio energia (`EnergyGauge` lo legge già) 30 fps sempre. Con Riduci movimento l'Orb in Riposo può fermarsi del tutto (`isPaused` + `enableSetNeedsDisplay`, ridisegno solo al cambio di Stato o Tinta). Questo tocca la spec 25 («l'Orb resta a 60 fps») e va deciso lì: la ridotta è l'occasione, non il motivo.
- **RAM**: tre drawable da 224² × 4 B ≈ 0,6 MB contro ≈ 1,55 MB del Panel attuale. Irrilevante rispetto ai 100 MB a riposo.
- **0 fotogrammi coperto** resta un invariante. Con la ridotta la finestra è quasi tutta Orb, quindi l'avvertenza di `occlusionState` sulle finestre trasparenti scatta meno.

### Accessibilità

- **VoiceOver**: l'Orb resta un pulsante «Panel di Bubo» con valore lo Stato; nella ridotta il valore aggiunge lo stato delle Sessioni, per esempio «Riposo, 2 Sessioni ti attendono» (stessa stringa di `MenuBarGlyph.accessibilityDescription`). La pillola è un pulsante con etichetta completa; il suo comparire si annuncia una volta con priorità media, non a ogni cambio. Azioni: «Apri HUD», «Chiedi nel Panel», «Panel normale».
- **Tastiera**: il Panel non attivante non prende il fuoco, quindi ogni funzione deve avere una scorciatoia globale o una voce di menu: «Chiedi nel Panel» (esiste), ⌥Spazio per l'HUD (esiste), «Panel ridotto» nel menu della barra. Nessun comando solo al passaggio del puntatore.
- **Riduci movimento** (sistema o Aspetto, `Motion.isReduced`): niente cambio di taglia animato, bolla e pillola in dissolvenza, Orb in Riposo fermo o quasi (decidere nel prototipo), Morph in dissolvenza come oggi.
- **Differenziare senza colore**: Attende te ha punto e testo, mai solo il punto Lume. La Tinta da sola non deve dire nulla di essenziale.
- **Riduci trasparenza / Aumenta contrasto**: la pillola in Liquid Glass deve avere il ripiego di sistema; testo in `textPrimary` su `surface`, già controllato da `PaletteContrastTests`.
- **Bersagli**: Orb 74 pt di cerchio, pillola alta almeno 24 pt e larga almeno 28 pt (HIG: 28 predefinito, 20 minimo).

### Coerenza con Notte e con il codice

- Contenitore acromatico (ADR 0004): la pillola è vetro con filo `line`, testo `textPrimary` o `textSecondary`, unico colore il punto Lume per Attende te. Nessun alone colorato oltre a quello dell'Orb.
- Raggi: capsula per la pillola, come prompt e chip. Ombra solo per l'elevazione del Panel (la bolla ce l'ha già).
- Codice: `OrbPanelController.side` diventa la taglia corrente (`PanelSize.normal = 240`, `.reduced = 112`) e `PanelClickCircle.radius` diventa proporzionale; `renderScale` per taglia (1,5 per 240, 2 per 112). `PanelPlacement` aggiunge la taglia per schermo accanto alla zona. La pillola è una seconda finestra figlia, posizionata con la stessa logica di `PanelBubbleLayout`. Nessun nuovo renderer.

## Domande per un prototipo

1. **Taglia**: 112 pt (Orb ≈ 62) o 96 pt (Orb ≈ 53)? Provare su un MacBook Air 13" a 1470 × 956 e su un monitor 27" a 2560 × 1440, con Dock in basso e nascosto.
2. **Forme nella ridotta**: a 62 pt le Varianti del Catalogo si riconoscono, o la ridotta resta sul Blob con Tinta e Stato e le Forme si vedono solo in bolla o nell'HUD?
3. **Frequenza**: 30 fps in Riposo si notano accanto ai 60 degli altri Stati? Misurare tempo GPU e impatto energetico (Instruments, Energy Log) a 60, 30 e in pausa, su M1 e M4.
4. **Riduci movimento**: Orb in Riposo fermo del tutto, o respiro rallentato?
5. **Pillola**: a lato dell'Orb verso il centro, o sotto/sopra? Con quali stati compare (Attende te, Errore, Risposta pronta, Lavora)? Quanto resta «Risposta pronta» prima di sparire?
6. **Cambio di taglia**: solo manuale, o anche automatico quando lo schermo è piccolo (per esempio `visibleFrame` alto meno di 900 pt) o quando un'app va a schermo intero?
7. **Mission Control**: `stationary` o `transient`? Quale si legge meglio con 3 Spaces e un'app a schermo intero?
8. **Dock**: `didChangeScreenParametersNotification` arriva quando il Dock cambia taglia o lato? Se no, serve osservare `visibleFrame` in altro modo.
9. **Clic sull'Orb**: nella ridotta, il clic apre ancora l'HUD (come nel Panel normale) o la bolla? La proposta è HUD, per coerenza con #25.
10. **Condivisione schermo**: nascondere il Panel (`sharingType = .none`) solo nella ridotta, sempre o mai?

## Fonti

Apple:
- HIG, Panels: https://developer.apple.com/design/human-interface-guidelines/panels
- HIG, Accessibility: https://developer.apple.com/design/human-interface-guidelines/accessibility
- HIG, Motion: https://developer.apple.com/design/human-interface-guidelines/motion
- HIG, Playing video: https://developer.apple.com/design/human-interface-guidelines/playing-video
- `NSWindow.CollectionBehavior`: https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct
- `NSWindow.StyleMask.nonactivatingPanel`: https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel
- `NSWindow.Level`: https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct
- `NSPanel.becomesKeyOnlyIfNeeded`: https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded
- `NSScreen.visibleFrame`: https://developer.apple.com/documentation/appkit/nsscreen/visibleframe
- `NSWindow.occlusionState`: https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.property
- `NSWindow.sharingType`: https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.property
- `NSWorkspace.accessibilityDisplayShouldReduceMotion`: https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion
- `MTKView.preferredFramesPerSecond`: https://developer.apple.com/documentation/metalkit/mtkview/preferredframespersecond
- `MTKView.enableSetNeedsDisplay`: https://developer.apple.com/documentation/metalkit/mtkview/enablesetneedsdisplay
- `ProcessInfo.isLowPowerModeEnabled`: https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled
- `AVPictureInPictureController`: https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller
- WWDC22 10083, Power down: https://developer.apple.com/videos/play/wwdc2022/10083/
- WWDC21 10147, Optimize for variable refresh rate displays: https://developer.apple.com/videos/play/wwdc2021/10147/
- WWDC25 310, Build an AppKit app with the new design: https://developer.apple.com/videos/play/wwdc2025/310/

App:
- OpenAI, note di rilascio dell'app macOS: https://help.openai.com/en/articles/9703738-chatgpt-macos-app-release-notes (non leggibile da qui, 403)
- AlternativeTo, companion window: https://alternativeto.net/news/2024/8/openai-introduces-handy-companion-window-for-chatgpt-on-macos
- Raycast, AI Chat: https://manual.raycast.com/ai/ai-chat.md
- Superwhisper, Recording Window: https://superwhisper.com/docs/get-started/interface-rec-window
- Granola, Transcription: https://docs.granola.ai/help-center/taking-notes/transcription
- iMore, Picture in Picture su Mac (secondaria): https://www.imore.com/how-use-picture-picture-anywhere-your-mac

Bubo:
- Comportamento del Panel: [#25](https://github.com/mgiuditta/bubo/issues/25); Blob in Metal e misure: [#8](https://github.com/mgiuditta/bubo/issues/8); bolla: [#383](https://github.com/mgiuditta/bubo/issues/383)
- `CONTEXT.md`, `docs/design-system.md`, `docs/features/25-prestazioni.md`, `docs/features/09-sistema.md`
- Codice: `Bubo/Panel/`, `Bubo/Orb/OrbRenderer.swift`, `Bubo/Orb/OrbShading.h`, `Bubo/HUD/HUDOrb.swift`, `Bubo/App/HUDPresenter.swift`, `BuboPerfTests/PerfBudgets.swift`
