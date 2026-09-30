# `claude` senza i permessi TCC di Bubo

Bubo non è in sandbox e avvia `claude`, che a sua volta lancia comandi arbitrari. Per TCC il processo responsabile di un figlio è di norma il padre, quindi ogni permesso dato a Bubo (Microfono per la voce, e un domani Accessibilità o Registrazione schermo) varrebbe anche per l'agente: `sox` potrebbe registrare, `osascript` controllare le app. Tutti i concorrenti chiedono Accessibilità e Registrazione schermo al primo avvio; noi no.

Abbiamo scelto:

- **Regola**: Bubo non chiede mai un permesso TCC che l'agente erediterebbe, se non c'è un modo di isolarlo.
- **Isolamento**: `claude` si avvia con il "disclaim" della responsabilità (`responsibility_spawnattrs_setdisclaim`, SPI privata usata da Chromium, Firefox, LLDB, Qt Creator ed Electron). `claude` diventa responsabile di sé: non eredita il Microfono di Bubo e chiede a nome proprio File e cartelle per i Progetti in Documenti o Scrivania. Un servizio XPC non basta, perché condivide i permessi dell'app.
- **Ingressi senza permessi**: testo selezionato con la scorciatoia del Servizio "Chiedi a Bubo", non con l'Accessibilità; schermo con il selettore di ScreenCaptureKit (scatto scelto dall'utente), non con la Registrazione schermo.

Se la SPI sparisce o non isola davvero (prova a inizio costruzione), Bubo accetta l'eredità del solo Microfono e lo dice nelle Impostazioni; Accessibilità e Registrazione schermo restano comunque escluse.
