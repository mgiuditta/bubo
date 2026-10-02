# 08 — Voce: push-to-talk, dettatura locale, Sintesi parlata, interruzione

Ticket: [#43](https://github.com/mgiuditta/bubo/issues/43) (ricerca), [#51](https://github.com/mgiuditta/bubo/issues/51) (motori, wake word, interruzione), [#57](https://github.com/mgiuditta/bubo/issues/57) (voce → Orb), [#59](https://github.com/mgiuditta/bubo/issues/59) (Jev). Mappa: [#42](https://github.com/mgiuditta/bubo/issues/42).

**Wake word esclusa dalla v1** ([#51](https://github.com/mgiuditta/bubo/issues/51)): la ricerca qui sotto la tratta ancora come ipotesi. Si riapre solo con una API Apple o con un classificatore Create ML sotto una soglia di falsi positivi.
Ricerca del 2026-09-29. Misure su Mac Studio M4 Max con macOS 26.7 (25G229). macOS 27 "Golden Gate" è uscito il 14 settembre 2026 [22], ma su questo Mac non è installato.

In sintesi: macOS 26 ha già tutto ciò che serve per la voce in locale, tranne la wake word. `SpeechTranscriber` trascrive italiano e inglese sul dispositivo. Alla fine dell'audio il testo definitivo arriva in circa 0,1 s e la CPU usata è trascurabile. `AVSpeechSynthesizer` produce il primo audio in circa 0,2 s. La cancellazione dell'eco c'è (`setVoiceProcessingEnabled`). Mancano due cose. La prima è una API per la wake word: bisogna usare una libreria esterna o un classificatore fatto in casa. La seconda è il riconoscimento del nome "Bubo" in inglese: il modello lo sbaglia e il vocabolario personalizzato non vale per `SpeechTranscriber`.

## Ricerca

### Come fanno i concorrenti

| App | Attivazione | Dove gira | Cosa fa bene | Limiti / cosa manca |
|---|---|---|---|---|
| **Superwhisper** | Scorciatoia predefinita **⌥Spazio**, premi per iniziare e ripremi per fermare [1]. Chiede i permessi Microfono e Accessibilità, che servono a incollare il testo [1]. | Modelli locali (Whisper, Parakeet) oppure cloud (OpenAI, Anthropic, Deepgram, Groq, chiavi proprie) [2]. "Con i modelli locali niente di ciò che dici lascia il dispositivo" [2]. | Oltre 100 lingue, "modi" con elaborazione da LLM, riunioni con separazione dei parlanti [2]. | Solo dettatura, nessuna risposta parlata. Latenza dichiarata solo come "millisecondi" [2]. |
| **Wispr Flow** | Tasto tenuto premuto (predefinito Fn) più una modalità a mani libere [3]. | **Solo cloud**: ASR più Llama fine-tuned per ripulire il testo, su Baseten [4]. | End-to-end **< 700 ms p99**, 100+ token in < 250 ms [4]. Il testo esce già formattato. | Non funziona offline. Privacy Mode (zero data retention) solo su richiesta, bloccata su attivo con BAA HIPAA [3]. |
| **ChatGPT desktop (macOS)** | ⌥Spazio apre la finestra compagna [5]. Advanced Voice Mode: conversazione in tempo reale, "puoi interrompere quando vuoi" (30 ottobre 2024), e dal 19 dicembre 2024 funziona insieme ad altre app [6]. | Cloud. | Barge-in naturale, voce espressiva. | Il 9 luglio 2026 la vecchia app è diventata "ChatGPT Classic" e ne è uscita una nuova [6]. Nessuna modalità locale. |
| **App Claude (desktop)** | Quick entry: **Caps Lock** per dettare, spento di default perché occupa il tasto. Si può scegliere un'altra scorciatoia. Richiede macOS 14 e il permesso Riconoscimento vocale [7]. La voice mode si apre con l'icona dell'onda sonora. Due modi: mani libere (risponde alle pause, predefinito) e push-to-talk [8]. | La dettatura è "in tempo reale" e il testo va a Claude come testo normale [7]. La voice mode gira in cloud [8]. | Interruzione semplice: "ricomincia a parlare e Claude si ferma" [8]. Voci predefinite, niente clonazione [8]. | Le lingue diverse dall'inglese sono in **beta** [8]. Quick entry solo su Mac [7]. Nessuna wake word. |
| **Siri (macOS 27, Siri AI)** | Tasto Microfono tenuto premuto oppure scorciatoia; "Hey Siri" o "Siri" a voce. Con Siri AI: ⌘Spazio in Spotlight, ⌘⇧Spazio per scegliere una finestra [9]. | Serve Internet [9]. Siri AI è annunciata come "beta in inglese" per l'autunno 2026 [10]. | Consapevolezza dello schermo e contesto personale [10]. Wake word di sistema. | Siri AI in italiano non è ancora disponibile (solo "espansione rapida" promessa) [10]. Le app terze non possono usare la wake word di Siri né le voci Siri. |

Cosa ne segue per Bubo:
- **⌥Spazio è già occupato** di default da Superwhisper e da ChatGPT [1][5]. Chi li usa ha un conflitto al primo avvio.
- Tutti i concorrenti "conversazionali" (ChatGPT, Claude) sono **cloud**. Gli unici locali (Superwhisper) fanno solo dettatura. Nessuno offre dettatura locale **e** risposta parlata **e** interruzione.
- Nessun concorrente desktop ha una wake word propria. Solo Siri, che è del sistema.

### API Apple in locale (macOS 26)

**Trascrizione: `SpeechAnalyzer` + `SpeechTranscriber`** (macOS 26.0 [11][12])
- Modulare: `SpeechAnalyzer` riceve l'audio come `AsyncSequence` e lo passa ai moduli `SpeechTranscriber`, `DictationTranscriber` e `SpeechDetector` [11][13].
- Il modello gira **fuori dal processo dell'app**. Il sistema lo scarica e lo aggiorna con `AssetInventory`, e non pesa né sulla dimensione dell'app né sulla sua memoria [14]. Un'app può tenere installate solo "un numero limitato di lingue alla volta" [14].
- Risultati **volatili** (subito, meno precisi) e **finali** [14]. È pensato per audio lungo e lontano dal microfono [14].
- Lingue su questo Mac: `SpeechTranscriber.supportedLocales` = **30** (compresi `it_IT`, `it_CH` e 9 varianti di inglese). `DictationTranscriber` = 54 [misura A].
- **Vocabolario personalizzato**: `AnalysisContext.contextualStrings` e `SFSpeechLanguageModel` sono documentati per `DictationTranscriber` [13]. Con `SpeechTranscriber` le `contextualStrings` **non hanno avuto effetto** [misura B].
- Nessuna diarizzazione. Nella documentazione non c'è nessuna API Speech nuova per il 27 (tutti i simboli risultano "introdotti in 26.0") [11][12]. Una domanda sui forum di giugno 2026 non ha ricevuto risposta [15].
- Terze parti: Argmax (M4, macOS 26 beta 1, inglese, earnings22) misura WER **14,0 %** e velocità **70×** il tempo reale, contro whisper-small.en 12,8 % / 35× e Parakeet v2 11,7 % / 359× [16]. Supporta 10 lingue al lancio contro le 100 di Whisper [16].

**VAD: `SpeechDetector`**. Chiede "c'è voce?" e serve per non trascrivere il silenzio e risparmiare energia. Ha una sensibilità regolabile (consigliata `medium`) e funziona solo insieme a un transcriber [13].

**Wake word: nessuna API pubblica.** (Esclusa dalla v1, vedi in alto.)
- Sound Analysis classifica oltre 300 suoni oppure un modello Core ML addestrato con Create ML (`MLSoundClassifier`) [17]. È fatto per classificare suoni, non per una parola chiave: per "Ehi Bubo" bisognerebbe raccogliere e addestrare dati propri.
- **Porcupine (Picovoice)**: include l'italiano, gira su macOS arm64 con binding Swift, la parola si addestra in Picovoice Console e serve una AccessKey [18]. Licenza: gratis per uso personale non commerciale. Commerciale: Foundation (startup, 100 utenti/mese), Developer 500 $/mese, Enterprise da 2.500 $/mese [19].
- **openWakeWord**: codice Apache-2.0, ma i modelli pre-addestrati sono CC BY-NC-SA. Addestramento con voce sintetica, **solo inglese**. Obiettivo: meno del 5 % di falsi rifiuti e meno di 0,5 falsi allarmi all'ora. Gira in Python/ONNX [20].
- Alternativa senza librerie: `SpeechDetector` sempre attivo più `SpeechTranscriber` che cerca "Bubo". La misura B però mostra che in inglese "Bubo" diventa "Bobo", "Bibo" o "bookbook". Serve un confronto fonetico approssimato, oppure non si fa.

**Sintesi vocale: `AVSpeechSynthesizer`**
- Voci con qualità `default`, `enhanced` e `premium` [21]. `write(_:toBufferCallback:)` restituisce i PCM invece di riprodurli, quindi si può instradarli nel proprio `AVAudioEngine` [21].
- **Personal Voice**: `requestPersonalVoiceAuthorization` da macOS 14 [23]. La voce si genera sul dispositivo. Apple la indica "soprattutto per app di comunicazione aumentativa o alternativa" [24].
- Su questo Mac sono installate solo voci `default`: 9 it-IT, 28 en-US, 9 en-GB, nessuna enhanced o premium [misura A]. Le voci migliori le scarica l'utente dalle Impostazioni: l'app vede `availableVoicesDidChangeNotification` ma non può avviare il download [21].
- Le voci di Siri non sono disponibili alle app.

**Cancellazione dell'eco e barge-in**
- `AVAudioInputNode.setVoiceProcessingEnabled(_:)` (macOS 10.15) attiva il Voice Processing I/O: cancellazione dell'eco, riduzione del rumore e controllo automatico del guadagno, "tarati per ogni modello di Mac e per ogni tipo di dispositivo audio" [25][26].
- Da macOS 14: livello di ducking dell'altro audio (Default, Min, Mid, Max) e rilevamento di chi parla col microfono muto (`setMutedSpeechActivityEventListener`) [26][27].
- Ne segue un'implicazione di progetto, da verificare con uno spike: l'eco si cancella solo sull'audio che esce dallo stesso I/O con voice processing. Quindi il TTS va reso con `write(...)` e suonato da un `AVAudioPlayerNode` nello stesso motore, non con `speak(_:)`. Rischi segnalati dagli sviluppatori: volume in uscita più basso e guadagno ridotto con VPIO attivo. Accenderlo e spegnerlo richiede di riavviare il motore, quindi conviene lasciarlo attivo e usare `isVoiceProcessingBypassed` [28].

**Permessi e indicatore**
- `NSMicrophoneUsageDescription` è obbligatoria. Il Centro di Controllo mostra un **punto arancione** e il nome dell'app finché il microfono è aperto [29]. Una wake word sempre attiva lascia quindi il punto arancione acceso in modo permanente.
- Riconoscimento vocale: Claude Desktop chiede il permesso "Speech recognition" per la dettatura [7]. Le prove da riga di comando (misure A e B) hanno trascritto senza nessuna richiesta. Nel bundle firmato va verificato se `SpeechTranscriber` chiede `NSSpeechRecognitionUsageDescription`.

### Cloud (opt-in, per confronto)

| Servizio | Latenza dichiarata | Italiano | Note |
|---|---|---|---|
| ElevenLabs Flash v2.5 | ~75 ms di modello, rete esclusa [30] | Sì | v4 Turbo ~100 ms, v3 Conversational ~280 ms. Streaming via WebSocket [30]. |
| OpenAI `gpt-4o-mini-tts` | Nessun numero. Per la risposta più rapida consigliano `pcm` o `wav` [31] | Sì (lingue di Whisper) | Voci ottimizzate per l'inglese, streaming chunked [31]. |

Per Bubo la differenza da battere non è la latenza: il TTS locale dà il primo buffer in circa 0,2 s. È la naturalezza della voce italiana, che con le sole voci `default` è modesta. Il cloud ha senso come opt-in "voce migliore", con la chiave dell'utente, coerente con il principio della mappa.

### Misure su questo Mac

**Misura A** (`probe.swift`, file generati con `say`, analisi offline del file intero):

| | Italiano (8,7 s di audio) | Inglese (6,9 s) |
|---|---|---|
| `SpeechTranscriber`, file intero | primo volatile 120 ms, finale 240 ms, **36×** il tempo reale | 94 ms / 247 ms, **28×** |
| TTS `AVSpeechSynthesizer.write`, voce `default` | primo buffer **241 ms** (Alice), 4,0 s di audio in 263 ms | **177 ms** (Samantha), 4,5 s in 202 ms |

**Misura B** (`stream.swift`, audio inviato a tempo reale in blocchi da 100 ms, come da microfono):

| Opzioni | Primo testo | Aggiornamenti | Finale dopo la fine dell'audio (`finalizeAndFinishThroughEndOfInput`) |
|---|---|---|---|
| `[.volatileResults]` | **solo a fine audio** (8,7 s): senza pause il modello non emette nulla | tutti insieme alla fine | 120–190 ms |
| `[.volatileResults, .fastResults]` | **~1,0 s** dall'inizio della voce | ogni ~0,9 s | **57–178 ms** |
| con `SpeechDetector` | come sopra | come sopra | +20 ms circa |

- CPU: il processo dell'app ha usato circa l'1 % di un core. Il servizio XPC `localspeechrecognition`, uno per client, ha usato l'1–3 % di un core con circa 46 MB di memoria residente. Il carico sul Neural Engine non si vede con `ps` e **la batteria non è stata misurata**.
- Esattezza sulle voci sintetiche: l'italiano è corretto parola per parola ("dell'ORB", "Commit" con la maiuscola). In inglese "Bubo" diventa "Bibo", "Bobo" o "bookbook", e le `contextualStrings` non cambiano il risultato. "Ehi Bubo" in italiano diventa "E Bubo". **Non ci sono misure su voce umana, rumore o microfono reale.**

## Il meglio da battere

Nessun concorrente unisce dettatura locale, risposta parlata e interruzione. I riferimenti per ogni pezzo sono:
- **dettatura**: Wispr Flow (< 700 ms p99 end-to-end, cloud) e Superwhisper (locale);
- **conversazione**: ChatGPT Advanced Voice e la voice mode di Claude (interruzione naturale, cloud; in Claude l'italiano è in beta).

Criteri candidati per la specifica:
1. **Testo definitivo ≤ 300 ms** dopo il rilascio della hotkey, in locale (misura B: 57–190 ms).
2. **Primo testo a schermo ≤ 1,2 s** dall'inizio della voce, per lo Stato Ascolto (misura B: ~1,0 s con `.fastResults`).
3. **Primo audio della risposta ≤ 300 ms** dal primo testo pronto del modello, in locale (misura A: 177–241 ms).
4. **Interruzione**: se l'utente parla mentre l'Orb è in Parla, il TTS si ferma entro 300 ms e non si attiva mai per l'eco della voce di Bubo. Da verificare con uno spike su VPIO.
5. **Zero rete** nella configurazione predefinita. Il punto arancione è acceso solo mentre si ascolta, finché la wake word resta spenta.
6. Italiano e inglese con la stessa qualità (numeri da ottenere su voce umana).

## Rischi e casi limite

- **Il nome "Bubo" in inglese** viene trascritto male, e il bias del vocabolario non vale per `SpeechTranscriber` [misura B][13]. Questo tocca sia la wake word sia i comandi "apri il progetto Bubo". Opzioni: `DictationTranscriber`, che accetta `contextualStrings` e modelli personalizzati ma con un modello più vecchio [13]; correzione a valle; oppure un nome di attivazione più riconoscibile.
- **Wake word**: non esiste una API Apple. Porcupine ha costi commerciali e dipende da una AccessKey [18][19]. openWakeWord è solo inglese con modelli non commerciali [20]. Un classificatore Create ML richiede dati propri. Con la wake word sempre attiva il punto arancione resta acceso [29] e il consumo in ascolto continuo non è misurato.
- **Conflitto su ⌥Spazio** con ChatGPT, Raycast e Alfred (predefinita di fabbrica) e spesso Superwhisper [1][5]. Carbon **non lo rileva**: `RegisterEventHotKey` non esclusivo riesce anche se un'altra app ha la stessa combinazione, e la pressione arriva a tutte e due; `eventHotKeyExistsErr` esce solo tra due registrazioni esclusive (header `CarbonEvents.h`, prova su macOS 26.7, [#64](https://github.com/mgiuditta/bubo/issues/64)). Difesa: il passo del primo avvio (Mappa). Prendere ⌥Spazio toglie anche lo spazio indivisibile (U+00A0) nei layout italiano e US.
- **Senza `.fastResults` non c'è streaming**: il testo arriva solo alle pause [misura B].
- **Formato audio**: `SpeechAnalyzer` vuole 16 kHz Int16 mono (`bestAvailableAudioFormat`). Un buffer in un formato sbagliato non dà errore e non produce testo [32]. Nelle prove, `AVAudioFile.read` a fine file lancia un'eccezione se non si controlla `framePosition`.
- **Modelli da scaricare**: il primo uso di una lingua può richiedere un download (`AssetInventory`), e le lingue installate per app sono limitate [14]. Serve un avviso chiaro quando si è offline.
- **VPIO**: volume in uscita più basso e guadagno del microfono ridotto [28]. Si comporta diversamente con cuffie Bluetooth, AirPods e microfoni USB (taratura per dispositivo [26]). Da provare.
- **Voci TTS**: senza le voci enhanced o premium scaricate dall'utente, l'italiano suona robotico. L'app non può scaricarle [21]. Personal Voice va proposta con cautela (uso consigliato per la comunicazione aumentativa) [24].
- **Siri AI su macOS 27**: occupa ⌘Spazio (Spotlight) e ⌘⇧Spazio [9]. In italiano non c'è ancora [10], ma quando arriverà sarà il concorrente più vicino per la voce di sistema.
- **Permesso Riconoscimento vocale**: non è chiaro se `SpeechTranscriber` lo chieda in un'app firmata. Da verificare prima di scrivere l'onboarding.

## Mappa

Architettura comune in [INDEX.md](INDEX.md). La voce è un **ingresso**: dopo il rilascio il testo entra nella pipeline unica degli ingressi, specificata in [09-sistema.md](09-sistema.md). Qui c'è solo il ramo voce.

- **Moduli** (`Voice/`):
  - `Voice/Hotkey`: estende la hotkey della Shell. Tocco su ⌥Spazio = mostra/nascondi; tenuto oltre ~300 ms = push-to-talk con invio al rilascio; ⌥⇧ tenuto = sola dettatura nel prompt, nessun invio. Un solo registratore in Impostazioni: tocco e push-to-talk usano la combinazione scelta, la sola dettatura aggiunge ⇧; se la scelta contiene già ⇧, la sola dettatura si spegne e il registratore lo dice. Registrazione Carbon non esclusiva, senza permessi ([#64](https://github.com/mgiuditta/bubo/issues/64)).
  - **Primo avvio, passo "Scorciatoia"**: registratore già su ⌥Spazio. Se `NSWorkspace` trova installati ChatGPT, Raycast, Alfred o Superwhisper (per bundle id, nessun permesso), avviso esplicito: "⌥Spazio aprirà anche <app>", con la scelta di cambiarla qui o nell'altra app. Il registratore avvisa anche per le scorciatoie di sistema abilitate (`CopySymbolicHotKeys`). Nessun tentativo di rilevare il conflitto via Carbon.
  - `Voice/AudioEngine`: un solo `AVAudioEngine` con voice processing sempre attivo (`isVoiceProcessingBypassed` invece del riavvio), livello RMS del microfono e dell'uscita per l'Orb.
  - `Voice/Transcriber`: `SpeechAnalyzer` + `SpeechTranscriber` con `[.volatileResults, .fastResults]`, formato da `bestAvailableAudioFormat`, lingua di sistema o di Impostazioni › Voce, modelli via `AssetInventory`. Nessun rilevamento della lingua, nessun cloud.
  - `Voice/SpeechOutput`: `AVSpeechSynthesizer.write(_:toBufferCallback:)` suonato da un `AVAudioPlayerNode` nello stesso motore (serve alla cancellazione dell'eco). Opt-in cloud ([#109](https://github.com/mgiuditta/bubo/issues/109)): OpenAI `gpt-4o-mini-tts` (voce `coral`, formato `pcm` a 24 kHz in streaming) con la chiave già nel Portachiavi per le Domande. Interruttore in Impostazioni › Voce, spento di default e attivabile solo con la chiave; accenderlo è il consenso, e a OpenAI va solo il testo della Sintesi parlata. Su errore o senza rete prima del primo audio parla il TTS locale; se la rete cade a metà, la voce si ferma lì.
  - `Voice/SpokenSummary`: estrae la **Sintesi parlata** dalla riga dedicata; se manca, prime 1–2 frasi senza codice né tabelle. La riga è la **prima** della risposta e comincia con `Sintesi parlata:`; non si mostra nel testo. La chiede un'istruzione in coda al messaggio dell'utente, solo nelle Domande a voce, non il prompt di sistema ([#107](https://github.com/mgiuditta/bubo/issues/107)). Il criterio "primo audio ≤ 300 ms" si misura dal primo testo della risposta (signpost "Primo audio della Sintesi parlata").
  - **v1** ([#107](https://github.com/mgiuditta/bubo/issues/107)): il TTS suona in un `AVAudioEngine` di sola uscita, a microfono chiuso, quindi senza punto arancione durante Parla. Voice processing e motore condiviso arrivano con il barge-in a voce, se passa lo spike. "0 byte in rete" vale per la catena voce, non per la risposta del modello.
- **Flusso**:
  1. Pressione lunga → Stato **Ascolto** (Orb pulsa con l'RMS, testo parziale nel prompt). Al primo uso si chiede il Microfono, non all'avvio.
  2. Durante l'Ascolto: previsione di Tipo e Variante sul testo parziale, **solo in locale** con Apple FM, mai con Jev ([#57](https://github.com/mgiuditta/bubo/issues/57)).
  3. Rilascio → `finalizeAndFinishThroughEndOfInput` → testo finale nel prompt, visibile, e invio alla pipeline degli ingressi: Pensiero subito, Tinta prevista, Morph al rilascio se la previsione regge, altrimenti dopo il classificatore finale (dettaglio in 09).
  4. Risposta: Stato Lavora al primo token; se la richiesta era a voce, Stato **Parla** con la Sintesi parlata (Orb deformato dal livello TTS, sottotitoli). Il testo completo resta nel Panel. Se la richiesta era scritta, Bubo non parla.
  5. Interruzione: ⌥Spazio tenuto ferma l'audio e riapre l'Ascolto; Esc ferma e basta. Barge-in a voce solo se passa lo spike. L'audio si ferma alla pressione di ⌥Spazio, non alla soglia del tenuto, così il microfono non sente Bubo; un tocco durante Parla ferma la voce e mostra o nasconde l'HUD. Esc è una hotkey globale registrata solo mentre Bubo parla, perché il Panel non prende la tastiera: per quei secondi Esc non arriva all'app davanti ([#108](https://github.com/mgiuditta/bubo/issues/108)). Signpost "Interruzione della voce".
- **Permessi** ([ADR 0005](../adr/0005-claude-senza-i-permessi-tcc-di-bubo.md)): il Microfono è di Bubo; `claude` parte con il disclaim e non lo eredita. Se la SPI non isola, l'eredità del solo Microfono si dichiara nelle Impostazioni. Microfono negato: Orb in Riposo e riga nel Panel con link alle Impostazioni di sistema.
- **Casi limite**:
  - modello della lingua non scaricato e Mac offline: avviso chiaro, niente Ascolto muto;
  - buffer nel formato sbagliato: nessun errore e nessun testo, quindi il formato si prende sempre da `bestAvailableAudioFormat`;
  - voci solo `default`: l'onboarding invita a scaricare una voce italiana enhanced o premium con link alle Impostazioni (l'app non può scaricarla);
  - cuffie Bluetooth, AirPods, microfoni USB: VPIO si comporta in modo diverso, volume in uscita più basso;
  - "Bubo" trascritto male in inglese: nessuna correzione nella v1, il nome non serve all'attivazione;
  - Riduci movimento: Orb fermo, resta un indicatore di livello;
  - un Morph già iniziato arriva sempre in fondo, anche se l'utente interrompe;
  - ⌥Spazio condiviso con un'altra app installata dopo l'onboarding: si aprono entrambe; il registratore resta in Impostazioni › Voce, nessun rilevamento automatico.
- **Test**:
  - latenze p95 con audio registrato a tempo reale (rilascio → testo finale, primo testo → primo audio, interruzione → audio fermo);
  - traffico di rete a zero in modalità locale (Network Link Conditioner o `nettop` durante una sessione vocale completa);
  - le 200 richieste etichettate lette ad alta voce, in italiano e in inglese, per Morph falsi e Categoria;
  - spike del barge-in (costruzione): 5 minuti di risposta dagli altoparlanti del Mac senza interruzioni false, interruzione vera in ≤ 300 ms;
  - verifica in un bundle firmato del permesso Riconoscimento vocale.

## Specifica "migliore di"

Miglior concorrente: **Superwhisper** per la dettatura (locale, ma senza risposta parlata) e **ChatGPT Advanced Voice** e **voice mode di Claude** per la conversazione (interruzione naturale, ma solo cloud; in Claude l'italiano è in beta). Nessuno unisce dettatura locale, risposta parlata e interruzione, e nessuno mostra il tipo di risposta prima che arrivi.
Bubo li supera così (p95, Mac M-series, modalità locale):
- **testo finale ≤ 250 ms** dopo il rilascio della hotkey (misura B: 57–190 ms);
- **primo audio ≤ 300 ms** dopo il primo testo della risposta (misura A: 177–241 ms);
- **audio fermo ≤ 100 ms** dopo l'interruzione (hotkey o Esc);
- **0 byte in rete** in modalità locale: trascrizione, previsione sul parziale e sintesi tutte sul Mac;
- **CPU in Ascolto < 5 %** di un core;
- **italiano completo** con la stessa qualità dell'inglese;
- dal rilascio: **Pensiero visibile ≤ 100 ms**, **inizio Morph ≤ 350 ms** se la previsione regge e **≤ 600 ms** con il classificatore finale, **Morph finito ≤ 1,7 s**;
- **0 Morph falsi** e **Categoria corretta ≥ 90 %** sulle 200 richieste etichettate lette ad alta voce;
- punto arancione del microfono acceso **solo** mentre ⌥Spazio è tenuto.

## Fonti

1. Superwhisper, "Quickstart" — https://superwhisper.com/docs/get-started/quickstart
2. Superwhisper, documentazione — https://superwhisper.com/docs
3. Wispr Flow, "Privacy Mode & Data Retention" — https://docs.wisprflow.ai/articles/6274675613-privacy-mode-data-retention (404 al momento della ricerca; contenuto dall'estratto indicizzato); tasto Fn e modalità mani libere da recensioni, non da fonte primaria
4. Baseten, caso cliente Wispr Flow — https://www.baseten.co/resources/customers/wispr-flow/
5. OpenAI Help, ChatGPT macOS (⌥Spazio, finestra compagna) — https://help.openai.com/en/articles/9703738 (403 via fetch; testo dagli estratti indicizzati)
6. OpenAI, note di rilascio dell'app macOS (30/10/2024, 19/12/2024, 9/7/2026) — https://help.openai.com/en/articles/9703738-chatgpt-macos-app-release-notes (letto tramite https://releasebot.io/updates/openai/chatgpt-macos-app-2)
7. Claude Help, "Use quick entry with Claude Desktop on Mac" — https://support.claude.com/en/articles/12626668
8. Claude Help, "Use voice mode" — https://support.claude.com/en/articles/11101966-use-voice-mode
9. Apple, "Turn on and activate Siri on Mac" — https://support.apple.com/guide/mac-help/turn-on-and-activate-siri-mchlb66b4ad6/mac
10. Apple Newsroom, "Apple unveils next generation of Apple Intelligence, Siri AI, and more" (8 giugno 2026) — https://www.apple.com/newsroom/2026/06/apple-unveils-next-generation-of-apple-intelligence-siri-ai-and-more/
11. Apple Developer, `SpeechAnalyzer` — https://developer.apple.com/documentation/speech/speechanalyzer
12. Apple Developer, `SpeechTranscriber` — https://developer.apple.com/documentation/speech/speechtranscriber
13. Apple Developer, `DictationTranscriber`, `SpeechDetector`, `AnalysisContext` — https://developer.apple.com/documentation/speech/dictationtranscriber ; https://developer.apple.com/documentation/speech/speechdetector ; https://developer.apple.com/documentation/speech/analysiscontext
14. WWDC25, "Bring advanced speech-to-text to your app with SpeechAnalyzer" (sessione 277) — https://developer.apple.com/videos/play/wwdc2025/277/
15. Apple Developer Forums, "Native diarization in '27?" (giugno 2026) — https://developer.apple.com/forums/thread/829621
16. Argmax, "Apple and Argmax" (benchmark su macOS 26 beta 1) — https://www.argmaxinc.com/blog/apple-and-argmax
17. Apple Developer, Sound Analysis — https://developer.apple.com/documentation/soundanalysis
18. Picovoice, Porcupine (README) — https://github.com/Picovoice/porcupine
19. Picovoice, prezzi e Foundation Plan — https://picovoice.ai/pricing ; https://picovoice.ai/blog/introducing-picovoices-free-tier (pagina prezzi non leggibile via fetch; cifre dagli estratti indicizzati)
20. openWakeWord (README) — https://github.com/dscripka/openWakeWord
21. Apple Developer, `AVSpeechSynthesizer`, `AVSpeechSynthesisVoiceQuality` — https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer ; https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoicequality
22. MacRumors, "Apple Announces macOS Golden Gate Release Date" (10 settembre 2026) — https://www.macrumors.com/2026/09/10/macos-27-golden-gate-release-date/
23. Apple Developer, `requestPersonalVoiceAuthorization(completionHandler:)` — https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/requestpersonalvoiceauthorization(completionhandler:)
24. WWDC23, "Extend Speech Synthesis with personal and custom voices" (sessione 10033) — https://developer.apple.com/videos/play/wwdc2023/10033/
25. Apple Developer, `setVoiceProcessingEnabled(_:)` — https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:)
26. WWDC23, "What's new in voice processing" (sessione 10235) — https://developer.apple.com/videos/play/wwdc2023/10235/
27. Apple Developer, `voiceProcessingOtherAudioDuckingConfiguration`, `setMutedSpeechActivityEventListener(_:)` — https://developer.apple.com/documentation/avfaudio/avaudioinputnode/voiceprocessingotheraudioduckingconfiguration
28. Apple Developer Forums, tag AVAudioEngine/AVAudioNode (volume basso e guadagno ridotto con voice processing; bypass invece del riavvio) — https://developer.apple.com/forums/tags/avaudionode?page=3 ; https://developers.apple.com/forums/thread/733733
29. Apple Support, Centro di Controllo (punto arancione del microfono) — https://support.apple.com/en-au/guide/mac-help/aside/glos269670b4/mac
30. ElevenLabs, "Models" — https://elevenlabs.io/docs/models
31. OpenAI, "Text to speech" — https://developers.openai.com/api/docs/guides/text-to-speech
32. DEV Community, "iOS 26's SpeechAnalyzer on a live mic: the 5 things the docs don't tell you" (fonte secondaria, confermata dalla misura B per il formato) — https://dev.to/simple_memo/ios-26s-speechanalyzer-on-a-live-mic-the-5-things-the-docs-dont-tell-you-2ng5

Misure A e B: script Swift in locale (`swiftc -O`) con SDK macOS 26 su Mac Studio M4 Max, macOS 26.7, il 2026-09-29. L'audio è sintetico (`say`, voci Alice e Samantha), non voce umana né microfono. La CPU è campionata con `ps`, il Neural Engine e la batteria non sono misurati.
