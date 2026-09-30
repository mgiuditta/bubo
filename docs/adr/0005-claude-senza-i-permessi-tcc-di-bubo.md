# `claude` senza i permessi TCC di Bubo

Bubo non è in sandbox e avvia `claude`, che a sua volta lancia comandi arbitrari. Per TCC il processo responsabile di un figlio è di norma il padre, quindi ogni permesso dato a Bubo (Microfono per la voce, e un domani Accessibilità o Registrazione schermo) varrebbe anche per l'agente: `sox` potrebbe registrare, `osascript` controllare le app. Tutti i concorrenti chiedono Accessibilità e Registrazione schermo al primo avvio; noi no.

Abbiamo scelto:

- **Regola**: Bubo non chiede mai un permesso TCC che l'agente erediterebbe, se non c'è un modo di isolarlo.
- **Isolamento**: `claude` si avvia con il "disclaim" della responsabilità (`responsibility_spawnattrs_setdisclaim`, SPI privata usata da Chromium, Firefox, LLDB, Qt Creator ed Electron). `claude` diventa responsabile di sé: non eredita il Microfono di Bubo e chiede a nome proprio File e cartelle per i Progetti in Documenti o Scrivania. Un servizio XPC non basta, perché condivide i permessi dell'app.
- **Ingressi senza permessi**: testo selezionato con la scorciatoia del Servizio "Chiedi a Bubo", non con l'Accessibilità; schermo con il selettore di ScreenCaptureKit (scatto scelto dall'utente), non con la Registrazione schermo.

**Provato** il 30/09/2026 in bundle firmato ([#66](https://github.com/mgiuditta/bubo/issues/66)): il ponte `bubo-agent` parte con il disclaim, e `claude` e i suoi comandi non ereditano Microfono né File e cartelle di Bubo.

Se la SPI sparisce o non isola davvero, Bubo accetta l'eredità del solo Microfono e lo dice nelle Impostazioni; Accessibilità e Registrazione schermo restano comunque escluse.

## Estensione: ogni processo avviato da Bubo

La regola vale per tutto ciò che Bubo avvia, non solo per `claude`: shell del terminale, dev server, CLI dell'editor ("apri nell'editor"). Tutti partono con il disclaim. Una shell ha bisogno anche di un terminale di controllo, che `posix_spawn` non dà: un piccolo lanciatore nel bundle fa `setsid` + `TIOCSCTTY` + `exec`, e lui stesso parte con il disclaim. Per questo il terminale usa SwiftTerm solo come vista, con un PTY di Bubo: `LocalProcess` di SwiftTerm e libghostty completo creano i processi con `fork`, dove il disclaim non si può mettere. Nessun concorrente lo fa: VS Code, Cursor e Claude desktop usano `node-pty` senza disclaim ([Terminale e anteprima: cosa entra in v1](https://github.com/mgiuditta/bubo/issues/133)).
