# Ricerca #110 — Barge-in a voce

Ticket: [#110](https://github.com/mgiuditta/bubo/issues/110) (spike). Collegati: [#108](https://github.com/mgiuditta/bubo/issues/108) (interruzione con hotkey ed Esc, chiuso), [#107](https://github.com/mgiuditta/bubo/issues/107) (Sintesi parlata v1), [#109](https://github.com/mgiuditta/bubo/issues/109) (voce OpenAI opt-in), [#51](https://github.com/mgiuditta/bubo/issues/51) (motori, wake word, interruzione). Spec: [`docs/features/08-voce.md`](../features/08-voce.md). ADR: [0001](../adr/0001-solo-macos-26.md), [0005](../adr/0005-claude-senza-i-permessi-tcc-di-bubo.md).
Ricerca del 2026-10-02. Fonti lette alla stessa data.

**Domanda.** L'utente può interrompere Bubo **parlando** mentre l'Orb è in Parla, con la cancellazione dell'eco del motore audio di macOS 26, senza che la voce di Bubo dagli altoparlanti faccia scattare interruzioni false? Criteri del ticket: 5 minuti di risposta dagli altoparlanti senza interruzioni false, interruzione vera in ≤ 300 ms, esito "si costruisce o resta fuori".

**Nessuna prova sul Mac.** Questa ricerca è stata fatta da un agente su Linux: niente misure, niente codice eseguito. Tutti i numeri qui sotto vengono dalle fonti. Il protocollo di prova in fondo è per l'umano, su un Mac **con microfono** (il Mac Studio delle misure di spec 08 non ne ha uno integrato: serve un MacBook o uno Studio Display).

## In sintesi

- **La cancellazione dell'eco c'è ed è la strada giusta**, ma vale solo per l'audio che esce **dallo stesso `AVAudioEngine`** con voice processing acceso [1][2]. Oggi Bubo ha due motori separati (`SpeechOutput` di sola uscita, `SpeechListener` di solo ingresso): lo spike deve prima unirli in uno. La voce OpenAI passa già dallo stesso `AVAudioPlayerNode`, quindi verrebbe cancellata anche lei.
- **Il pezzo che manca è il rilevatore di "l'utente ha cominciato a parlare".** `SpeechDetector` di macOS 26 non lo dà: i suoi `Result` "per ora supportano solo la gestione degli errori" e serve solo a filtrare l'audio per il transcriber [3]. `SpeechTranscriber` dà il primo testo dopo ~1 s (misura B di spec 08): troppo tardi per 300 ms, buono come conferma. Restano tre candidati da misurare: un **VAD di Apple** (rilevamento del parlato col microfono muto del voice processing [4][5], o la proprietà HAL `kAudioDevicePropertyVoiceActivityDetectionState` [5]), **Silero VAD** in locale [6][7], o una **soglia di energia** sul segnale già ripulito dall'eco.
- **Il budget di 300 ms è stretto ma possibile**: chi lo fa in produzione decide dopo 200–250 ms di voce (Pipecat `start_secs` 0,2 [8]; LiveKit mediana 216 ms [9]; Silero `min_speech_duration_ms` 250 [10]). Restano ~50–100 ms per buffer del tap e arresto del player: il tap di 4096 frame di oggi (~85 ms a 48 kHz) va ridotto.
- **Il rischio vero sono i falsi positivi, non la latenza**: l'eco non è cancellato nei primi ~200 ms finché l'algoritmo converge [11]; l'audio delle **altre app** (musica, video) non viene cancellato ma solo abbassato [12], quindi una canzone con voce può far scattare il VAD; tosse, "mh", persone nella stanza.
- **Raccomandazione:** lo spike si fa, con un motore unico VPIO e **tre rilevatori in parallelo in sola registrazione**, poi si sceglie sui dati. Se nessuno passa dagli altoparlanti, il barge-in resta fuori o si accende **solo con le cuffie**. La decisione di prodotto da prendere prima: barge-in vuol dire **microfono aperto e punto arancione durante Parla**, il contrario di quanto deciso per la v1.

## Vincoli già decisi

- **Spec 08, v1** ([#107](https://github.com/mgiuditta/bubo/issues/107)): il TTS suona in un `AVAudioEngine` di sola uscita, **a microfono chiuso**, "quindi senza punto arancione durante Parla. Voice processing e motore condiviso arrivano con il barge-in a voce, se passa lo spike."
- **Spec 08, interruzione** ([#108](https://github.com/mgiuditta/bubo/issues/108), fatto): ⌥Spazio tenuto ferma l'audio e riapre l'Ascolto; Esc ferma e basta; audio fermo ≤ 100 ms p95; un Morph iniziato arriva in fondo. Il barge-in a voce si aggiunge, non sostituisce.
- **Spec 08, architettura prevista**: `Voice/AudioEngine` con "un solo `AVAudioEngine` con voice processing sempre attivo (`isVoiceProcessingBypassed` invece del riavvio)"; TTS con `AVSpeechSynthesizer.write(_:toBufferCallback:)` suonato da un `AVAudioPlayerNode` nello stesso motore. Già così in `Bubo/Voice/SpeechOutput.swift`, ma nel motore sbagliato.
- **Zero rete** nella catena voce locale: niente VAD in cloud (LiveKit adaptive gira solo su LiveKit Cloud [13]).
- **ADR 0001**: solo macOS 26, quindi tutte le API di macOS 14+ e 26 sono disponibili.
- **ADR 0005**: il Microfono è di Bubo; `claude` parte col disclaim. Il barge-in non cambia i permessi, solo **quando** il microfono è aperto.
- **Wake word esclusa dalla v1** ([#51](https://github.com/mgiuditta/bubo/issues/51)): un barge-in "a parola chiave" ("Bubo, stop") ne erediterebbe i problemi ("Bubo" trascritto male in inglese, spec 08).

## Codice esistente

- `SpeechOutput` (`Bubo/Voice/SpeechOutput.swift`): `AVSpeechSynthesizer.write` o voce OpenAI → `AVAudioPlayerNode` → `mainMixerNode` di un motore **senza ingresso**. Tap sul player per il livello dell'Orb. `stop()` ferma subito (criterio #108).
- `SpeechListener` (`Bubo/Voice/SpeechListener.swift`): un **altro** `AVAudioEngine` creato a ogni `start`, tap di 4096 frame sull'`inputNode`, conversione al formato di `SpeechAnalyzer.bestAvailableAudioFormat`, `SpeechTranscriber`. Nessun voice processing.
- `PushToTalk`: alla pressione chiama `interrupt` (ferma la voce) prima di aprire il microfono.
- Nel repo non c'è `setVoiceProcessingEnabled`, `SpeechDetector` né un VAD.

## Le API, una per una

### Cancellazione dell'eco: Voice Processing I/O

- **`AVAudioInputNode.setVoiceProcessingEnabled(_:)`** (macOS 10.15): accende AUVoiceProcessingIO su ingresso **e** uscita del motore; cancellazione dell'eco, riduzione del rumore, controllo automatico del guadagno [1][4]. Per cancellare l'eco VPIO deve possedere sia la cattura sia la riproduzione [2]: un `AVSpeechSynthesizer.speak(_:)` o un secondo motore non entrano nel riferimento.
- **Convergenza**: l'algoritmo ha bisogno di ~200 ms (per > 20 dB di soppressione) prima di essere efficace; in alcuni casi di più. Il consiglio di un ingegnere Apple (giugno 2026): **far salire il volume dell'uscita in ~200 ms** all'inizio invece di partire al massimo [11].
- **Volume più basso**: con VPIO l'uscita è più bassa "per progetto" (catena DSP a banda limitata per la voce), con un controllo del volume separato [12].
- **Ducking delle altre app**: con VPIO acceso il sistema **abbassa** tutto l'audio che non è l'uscita voice processing, anche di altre app [12]. `voiceProcessingOtherAudioDuckingConfiguration` (macOS 14) regola `enableAdvancedDucking` (ducking dinamico solo quando qualcuno parla) e `duckingLevel` (`default`, `min`, `mid`, `max`) [14][4]. Su macOS non c'è modo noto di spegnerlo del tutto (domanda di luglio 2026 senza risposta) [15].
- **Formato dell'ingresso**: con VPIO l'`inputNode` può passare da 1 a 3, 5 o 9 canali e cambiare frequenza [16]; il tap va chiesto in un formato mono esplicito o convertito come già fa `SpeechListener`.
- **Dispositivi diversi per ingresso e uscita** (es. microfono AirPods + altoparlanti del MacBook): VPIO costruisce un dispositivo aggregato e può fallire con `-10875` e "Failed expectation of constructed aggregate" (dicembre 2025, senza risposta) [17]. Su un dispositivo professionale l'`engine.start()` può riuscire e poi fermarsi con una notifica di cambio configurazione [15].
- **Bypass**: `isVoiceProcessingBypassed` spegne l'elaborazione senza riavviare il motore (spec 08, [18] lì). Riavviare il motore per accendere VPIO costa e resetta la convergenza.

### Rilevare la voce dell'utente

| Rilevatore | Cosa dà | Latenza attesa | Note |
|---|---|---|---|
| **`SpeechDetector`** (Speech, macOS 26) [3] | Filtro "c'è voce?" per il transcriber; `SensitivityLevel` regolabile (`medium` consigliato) | — | **Non emette l'inizio del parlato**: i `Result` "per ora supportano solo la gestione degli errori". Funziona solo con un transcriber. **Non usabile come trigger.** |
| **`SpeechTranscriber` volatile** [3] | Prime parole | ~1,0 s dall'inizio della voce con `.fastResults` (misura B spec 08) | Troppo lento per 300 ms; ottimo come **conferma** (min parole, come Pipecat [8]). |
| **Rilevamento del parlato a microfono muto** (VPIO, macOS 14) [4][5] | Evento `SpeechActivityHasStarted/Ended` | Non documentata | Scatta **solo** se l'ingresso VPIO è muto. Idea da provare: mettere muto l'ingresso durante Parla e usare l'evento come trigger. Pensato da Apple per le chiamate, dove l'audio remoto esce dagli altoparlanti: dovrebbe reggere l'eco. Si perde la prima sillaba (ingresso muto). |
| **HAL `kAudioDevicePropertyVoiceActivityDetectionEnable/State`** (macOS 14) [5] | VAD sul dispositivo d'ingresso, a listener | Non documentata | Apple la indica "per chi non usa il voice processing": non è chiaro se veda il segnale prima o dopo la cancellazione dell'eco. Da provare. |
| **Silero VAD** (MIT) [6] | Probabilità di voce per blocco | < 1 ms di CPU per blocco da 30+ ms [6]; deciso dopo `min_speech_duration_ms` (250 ms di default) [10] | 8/16 kHz, ~2 MB, addestrato su 6000+ lingue [6]. A 5 % di falsi positivi trova l'87,7 % della voce contro il 50 % di WebRTC VAD [19]. In Swift: FluidAudio (Apache-2.0) su Core ML, Silero v6, F1 85 % su MUSAN (rumore e musica) [7]; i benchmark usano finestre di **256 ms**, da verificare se lo streaming scende a 32 ms. |
| **WebRTC VAD** (BSD) [19] | Voce sì/no per blocchi da 10–30 ms | Minima | Leggerissimo ma meno preciso; aggressività 3 → 2,8 % di falsi allarmi su un dataset di riunioni [19]. Reagisce all'energia: la voce residua di Bubo lo inganna più facilmente. |
| **Soglia di energia** sul segnale dopo l'AEC | RMS sopra soglia per N ms | ~blocco + N | Zero dipendenze, già calcolato per l'Orb (`SpeechListener.level`). Cieca alla differenza voce/rumore. Utile come confronto. |

### Soglie usate da chi lo fa in produzione

- **OpenAI Realtime, `server_vad`**: `threshold` 0,5, `prefix_padding_ms` 300, `silence_duration_ms` 500; `interrupt_response` vero di default: l'inizio del parlato interrompe la risposta [20][21]. Il client poi manda `conversation.item.truncate` con `audio_end_ms` per allineare il contesto a ciò che l'utente ha davvero sentito [22]. `semantic_vad` decide la **fine** del turno dalle parole, non l'inizio [20].
- **Pipecat**: Silero locale, `start_secs` 0,2, `stop_secs` 0,2, `min_volume` 0,6 [8]. Qualunque voce interrompe, a meno di strategie: `MinWordsUserTurnStartStrategy` (almeno 3 parole mentre il bot parla), filtro dei "mh" con Krisp VIVA, muto durante il bot [23]. Consiglio: togliere il rumore **a monte** con un filtro d'ingresso, non alzare la soglia del VAD [8]. Nel contesto entra solo il testo davvero pronunciato [23].
- **LiveKit Agents**: "adaptive interruption handling" (marzo 2026), un classificatore audio che separa interruzioni vere da "mh-mh", tosse, sospiri e rumore: 86 % di precisione, 100 % di richiamo, mediana 216 ms di audio per decidere, scarta il 51 % dei falsi positivi del VAD; su falso allarme **riprende** dal punto in cui si era fermato [9]. Gira **solo su LiveKit Cloud** [13].
- **Krisp VIVA 2.0**: "Interrupt Prediction v1", classificatore solo audio tra "voglio la parola" e backchannel; SDK con chiave, lato server [24].
- **Gemini Live API**: rilevamento automatico dell'attività con `startOfSpeechSensitivity`, `prefixPaddingMs`, `silenceDurationMs`; di default l'inizio dell'attività interrompe e il server manda `interrupted`. Chi lo integra avverte: se l'audio del modello rientra nel microfono, scatta un barge-in falso; serve l'AEC del client [25][26].

## Come fanno gli altri prodotti

| Prodotto | Barge-in | Dove gira il rilevamento | Note |
|---|---|---|---|
| **ChatGPT Voice (GPT-Live, 8 luglio 2026)** | Full-duplex: il modello ascolta mentre parla e decide "più volte al secondo" se parlare, aspettare o interrompere; fa anche "mh" [27][28] | Cloud, nel modello | iOS, Android, web; il Mac non è citato [28]. Prima di GPT-Live gli utenti segnalavano interruzioni per rumori di fondo [29]. |
| **Claude voice mode** | "Ricomincia a parlare e Claude si ferma" (spec 08, [8] lì) | Cloud | Mani libere di default, o push-to-talk. |
| **Gemini Live** | "Mentre Gemini parla puoi interromperlo parlando"; interruttore per spegnere le interruzioni [30] | Cloud | Solo Android, non nel web [30]. |
| **Siri** | Di default si interrompe a qualunque voce; opzione di Accessibilità "Richiedi Siri per le interruzioni": solo con "Siri"/"Ehi Siri" [31] | Sul dispositivo (wake word) | Documentato per iOS 17–18; su macOS non trovato. |
| **OpenAI Realtime API** | `server_vad` con `interrupt_response` [20][21] | Server; AEC a carico del client (browser in WebRTC) | Il client tronca l'audio già sentito [22]. |
| **Pipecat / LiveKit** | VAD locale Silero + strategie / classificatore in cloud [8][9][23] | Server dell'agente | Tutti contano sull'AEC del client (browser o app). |

Cosa ne segue per Bubo: **tutti spostano il problema sul cloud o sul browser**, e due su tre aggiungono un secondo livello (parole minime, classificatore) per non fermarsi a ogni "mh". Siri, l'unico tutto locale, offre lo spegnimento delle interruzioni libere. Nessun assistente desktop fa barge-in **locale** dagli altoparlanti del Mac: è lo spazio di Bubo, ma nessuno ha dimostrato che regga.

## Opzioni

| # | Strada | Trigger | Latenza stimata | Falsi positivi attesi | Dipendenze | Stato rispetto alle decisioni |
|---|---|---|---|---|---|---|
| 0 | **Nessun barge-in a voce** (oggi) | ⌥Spazio / Esc | ≤ 100 ms (#108) | 0 | — | Già costruito |
| 1 | **VPIO + VAD Apple col microfono muto** | `SpeechActivityHasStarted` con ingresso VPIO muto durante Parla | Non documentata | Da misurare; pensato per l'eco | Nessuna | Ammesso; da provare per primo |
| 2 | **VPIO + VAD HAL** | `kAudioDevicePropertyVoiceActivityDetectionState` | Non documentata | Da misurare; non è chiaro se il segnale sia già senza eco | Nessuna | Ammesso |
| 3 | **VPIO + Silero VAD** | Probabilità ≥ soglia per ~200 ms | ~200–250 ms + tap | Bassi su voce residua, sensibile a musica con voce | FluidAudio o ONNX Runtime | Ammesso con dipendenza |
| 4 | **VPIO + soglia di energia** | RMS sopra soglia per ~150 ms | ~150–200 ms | Alti | Nessuna | Ammesso, solo come confronto |
| 5 | **VPIO + parole del transcriber** | ≥ 1–2 parole volatili | ~1 s | Molto bassi | Nessuna | Non rispetta i 300 ms |
| 6 | **Due stadi**: VAD (1–4) abbassa la voce subito, il transcriber conferma e ferma; su falso allarme il volume torna su | VAD + parole | Reazione ≤ 300 ms (abbassa), arresto ~1 s | Bassi, e un falso allarme costa solo un calo di volume | Come il VAD scelto | Ammesso se "interruzione" = reazione udibile (domanda 2) |
| 7 | **Solo con le cuffie** | Come 1–4, acceso solo se l'uscita è cuffie/AirPods | Come sopra | Quasi zero (niente eco acustico) | Come sopra | Ripiego se gli altoparlanti falliscono |
| 8 | **Parola chiave** ("Bubo, stop") | Transcriber che cerca il nome | ~1 s | Bassi | Nessuna | Escluso: eredita i problemi della wake word (#51) |
| 9 | **VAD in cloud** (LiveKit adaptive, Realtime) | Server | ~200 ms + rete | Bassi | Rete e servizio | Escluso: zero rete nella catena voce |

## Raccomandazione

1. **Lo spike si fa**, in un ramo, con un **motore unico**: `inputNode.setVoiceProcessingEnabled(true)` prima di `start`, il `player` di `SpeechOutput` nello stesso motore, ducking `enableAdvancedDucking = true` e `duckingLevel = .min`, volume della voce che sale in 200 ms a ogni inizio [11], tap d'ingresso da ~10–20 ms (480–960 frame a 48 kHz) invece di 4096.
2. **Tre rilevatori in parallelo, in sola registrazione** (opzioni 1, 3 e 4; la 2 se costa poco), ciascuno con un signpost "Barge-in candidato" e il motivo. Nessuno ferma davvero la voce finché i dati non dicono chi vince: così una sola sessione di 5 minuti dà i falsi positivi di tutti.
3. **Regole fisse per tutti**: ignorare i primi 300 ms di ogni Sintesi parlata (convergenza dell'AEC [11]); trigger solo dopo ~150–200 ms di voce continua (come Pipecat e LiveKit [8][9]); su trigger vero `SpeechOutput.stop()` (già ≤ 100 ms, #108) e apertura dell'Ascolto con lo stesso motore, così le parole dell'utente non si perdono.
4. **Esito**: si costruisce se un rilevatore passa i criteri **dagli altoparlanti integrati** di un MacBook; se passa solo in cuffia, opzione 7 (acceso solo con le cuffie, detto nelle Impostazioni); se non passa nemmeno lì, resta fuori e restano ⌥Spazio ed Esc.
5. **In ogni caso opt-in** (Impostazioni › Voce, spento di default) finché la domanda 1 non è decisa: tiene il microfono aperto durante Parla.

## Rischi

- **Punto arancione durante Parla.** Il barge-in richiede il microfono aperto mentre Bubo parla: va contro la scelta v1 "senza punto arancione durante Parla" e contro "punto arancione acceso solo mentre ⌥Spazio è tenuto" della specifica "migliore di".
- **Musica e video delle altre app** non sono nel riferimento dell'eco: vengono solo abbassati [12]. Una canzone o un video con voce durante Parla può far scattare qualunque VAD. Il ducking stesso cambia l'esperienza di chi ascolta musica mentre usa Bubo, e su macOS non si spegne del tutto [15].
- **Convergenza dell'AEC**: i primi ~200 ms di ogni frase rientrano nel microfono [11]. Senza rampa e finestra cieca, ogni inizio di Sintesi parlata è un falso positivo potenziale.
- **Volume più basso con VPIO** [12]: la voce di Bubo si sentirà meno anche quando nessuno interrompe. Va misurato in dB e deciso se accettabile.
- **Altoparlanti del MacBook a volume alto**: distorsione non lineare e vibrazioni dello chassis sono il caso peggiore per qualunque AEC (conoscenza generale, non misurata qui).
- **Dispositivi misti** (AirPods come microfono, altoparlanti del Mac come uscita; microfono USB): VPIO può non partire [17]. Serve un ripiego pulito: barge-in spento, voce come oggi.
- **Formato e canali** che cambiano con VPIO [16]: un buffer nel formato sbagliato non dà testo (spec 08).
- **Backchannel e tosse**: "mh", "sì", una risata fermano la voce se il trigger è il solo VAD. Pipecat e LiveKit lo risolvono con parole minime o un classificatore [9][23]; in locale c'è solo la conferma del transcriber (~1 s).
- **Altre persone nella stanza**: nessun VAD distingue l'utente da un collega; servirebbe un'impronta della voce, fuori portata.
- **Dipendenza esterna** per Silero (FluidAudio o ONNX Runtime): peso, aggiornamenti, Core ML; i benchmark di FluidAudio usano finestre da 256 ms [7], da verificare in streaming.
- **API Apple poco documentate**: le opzioni 1 e 2 non hanno latenza né robustezza dichiarate; le domande sui forum del 2025–2026 su VPIO macOS restano spesso senza risposta [15][17].
- **Contesto della conversazione**: se l'utente interrompe, Claude non sa fin dove è arrivata la voce. Per Bubo pesa poco (la risposta completa è già scritta nel Panel), ma se la nuova domanda dice "no, l'ultima cosa" il riferimento è all'ultima frase **sentita**, non scritta.

## Protocollo di prova (per l'umano, sul Mac)

**Hardware.** Un Mac con microfono integrato: MacBook Air/Pro (altoparlanti e microfono nello stesso chassis, il caso peggiore) e, se c'è, Mac Studio + Studio Display. macOS 26.x aggiornato. Stanza silenziosa, poi rumore normale d'ufficio.

**Strumento.** Un target di prova (o voce di menu Debug) che:
- usa un solo `AVAudioEngine` con VPIO, il `player` di `SpeechOutput` e un tap d'ingresso da 960 frame;
- registra in WAV il segnale d'ingresso **dopo** l'AEC, con l'host time del primo campione;
- fa girare in parallelo i rilevatori 1, 3, 4 (e 2) e scrive un signpost per ogni trigger con nome e host time;
- scrive un signpost "Primo audio" e "Audio fermo" per ogni Sintesi parlata;
- legge un file di testo lungo (≥ 5 minuti di Sintesi parlata reale, italiano e inglese alternati).

**Prove.**

| # | Prova | Come | Criterio di successo |
|---|---|---|---|
| P1 | **Falsi positivi dagli altoparlanti** | 5 min di Sintesi parlata, voce `default` it-IT, altoparlanti integrati al 50 % e al 75 %; nessuno parla. Ripetere con voce enhanced/premium e con voce OpenAI se attiva | **0 trigger** al 50 % e 75 % (criterio del ticket). Al 100 % si registra, non blocca |
| P2 | **Interruzioni vere** | 40 interruzioni (20 it, 20 en) a punti diversi delle frasi, 10 nei primi 500 ms di una frase; frasi brevi ("aspetta", "stop") e lunghe ("no, intendevo il progetto di ieri"); a 50 cm e a 1,5 m | **≥ 38/40 trovate** (95 %) e latenza **p95 ≤ 300 ms**, dall'inizio della voce (segnato a mano nel WAV, es. in Audacity) al signpost "Audio fermo" |
| P3 | **Backchannel e rumori** | 10 "mh"/"sì", 5 colpi di tosse, 5 risate, digitazione continua, porta che sbatte | Solo registrato: decide se serve la conferma del transcriber (opzione 6) |
| P4 | **Musica di un'altra app** | Musica con voce in Music al 30 % durante P1 | Registrato: numero di trigger e ducking percepito; se > 0, va detto nelle Impostazioni |
| P5 | **Cuffie e dispositivi** | AirPods (ingresso e uscita), cuffie con filo + microfono integrato, microfono USB + altoparlanti integrati, AirPods microfono + altoparlanti integrati | Con cuffie P1 = 0 trigger e P2 come sopra; con dispositivi misti il motore parte **oppure** il barge-in si spegne da solo senza rompere la voce |
| P6 | **Costi** | Livello d'uscita VPIO acceso vs spento (stessa frase, dB misurati con il tap del player e con un fonometro da telefono); CPU del processo durante P1 | Calo di volume e CPU annotati; CPU < 5 % di un core |
| P7 | **Ascolto dopo il trigger** | Dopo un trigger vero l'Ascolto parte nello stesso motore | Il testo finale contiene anche le prime parole dette durante Parla |

**Esito da scrivere nel ticket**: rilevatore scelto (o nessuno), tabella P1–P2 per dispositivo, e una delle tre conclusioni: si costruisce dagli altoparlanti / solo con le cuffie / resta fuori.

## Domande per il fondatore

1. **Punto arancione durante Parla**: accettabile che il microfono sia aperto mentre Bubo parla? Se sì, barge-in acceso di default o opt-in in Impostazioni › Voce?
2. **Cosa vuol dire "interruzione in ≤ 300 ms"**: audio **fermo** entro 300 ms, oppure va bene una reazione udibile (voce che si abbassa subito, si ferma alla conferma, torna su se era un falso allarme)? La seconda abbassa molto i falsi positivi (opzione 6).
3. **Solo con le cuffie** è un esito accettabile, o se non regge dagli altoparlanti si lascia fuori?
4. **Dipendenza**: ammessa una libreria esterna (Silero via FluidAudio, Apache-2.0/MIT) se i VAD di Apple non bastano, o solo API di sistema?
5. **Ducking**: va bene che la musica delle altre app si abbassi mentre Bubo parla (effetto di VPIO, non spegnibile del tutto)?
6. **"Mh" e "sì"** devono interrompere Bubo, o vanno ignorati come fa ChatGPT con GPT-Live?
7. **Mac per la prova**: quale Mac con microfono integrato usiamo? Il Mac Studio delle misure di spec 08 non ne ha.

## Fonti

1. Apple Developer, `setVoiceProcessingEnabled(_:)` — https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:)
2. Talon, "feat(ios): real echo cancellation/NR via native Voice-Processing engine" (VPIO deve possedere cattura e riproduzione; fonte secondaria) — https://code.iamtalon.me/Talon/voice-cat/commit/6c17881cc03ae83a0d23a543c3ff73407a7a7e79
3. Apple Developer, `SpeechDetector` (macOS 26.0; `Result` "currently only support error handling") — https://developer.apple.com/documentation/speech/speechdetector
4. WWDC23, "What's new in voice processing" (sessione 10235): ducking, rilevamento del parlato a microfono muto, VAD HAL su macOS 14 — https://developer.apple.com/videos/play/wwdc2023/10235/ ; trascrizione: https://nonstrict.eu/wwdcindex/wwdc2023/10235/
5. WWDC Notes, sessione 10235 (`kAUVoiceIOProperty_MutedSpeechActivityEventListener`, `kAudioDevicePropertyVoiceActivityDetectionEnable/State`) — https://wwdcnotes.com/documentation/wwdc23-10235-whats-new-in-voice-processing/
6. Silero VAD (README, licenza MIT) — https://github.com/snakers4/silero-vad
7. FluidAudio (Apache-2.0) e benchmark del VAD Silero v6 su Core ML — https://github.com/FluidInference/FluidAudio ; https://docs.fluidinference.com/reference/benchmarks
8. Pipecat, "Speech input" (`VADParams`: `start_secs` 0,2, `stop_secs` 0,2, `min_volume` 0,6; filtri d'ingresso) — https://docs.pipecat.ai/pipecat/learn/speech-input
9. LiveKit, "Adaptive interruption handling" (19 marzo 2026) — https://livekit.com/blog/adaptive-interruption-handling
10. Parametri predefiniti di Silero (`threshold` 0,5, `min_speech_duration_ms` 250; fonte secondaria) — https://doc.pyvideotrans.com/en/vad
11. Apple Developer Forums 829784, "Acoustic Echo Cancellation does not work initially" (giugno 2026, risposta accettata di un ingegnere Apple: ~200 ms di convergenza, rampa del volume) — https://developer.apple.com/forums/thread/829784
12. Apple Developer Forums 829753, "Voice Processing" (giugno 2026, ingegnere Apple: volume più basso per progetto, ducking delle altre app) — https://developer.apple.com/forums/thread/829753
13. LiveKit docs, "Adaptive interruption handling" (solo LiveKit Cloud; requisiti) — https://docs.livekit.io/agents/logic/turns/adaptive-interruption-handling/
14. Apple Developer, `voiceProcessingOtherAudioDuckingConfiguration` — https://developer.apple.com/documentation/avfaudio/avaudioinputnode/voiceprocessingotheraudioduckingconfiguration
15. Apple Developer Forums 839831, "VPIO Audio Ducking" (luglio 2026, macOS, senza risposta) — https://developer.apple.com/forums/thread/839831
16. Apple Developer Forums 771530, "Turning on setVoiceProcessingEnabled bumps channel count to 5" — https://developer.apple.com/forums/thread/771530
17. Apple Developer Forums 810129, "AVAudioEngine Voice Processing Fails with Mismatched Input/Output Devices" (dicembre 2025) — https://developer.apple.com/forums/thread/810129
18. Spec 08, fonte [28] (bypass invece del riavvio) — [`docs/features/08-voce.md`](../features/08-voce.md)
19. Confronto WebRTC VAD / Silero (Displace 2023, arXiv 2406.15516; TPR a 5 % FPR) — https://arxiv.org/pdf/2406.15516
20. OpenAI, "Voice activity detection (VAD)" — https://developers.openai.com/api/docs/guides/realtime-vad
21. LiveKit docs, parametri VAD di OpenAI Realtime (default `threshold` 0,5, `prefix_padding_ms` 300, `silence_duration_ms` 500) — https://docs.livekit.io/agents/integrations/openai/customize/vad
22. OpenAI Python, eventi Realtime (`conversation.item.truncate`, `audio_end_ms`, `output_audio_buffer.clear`) — https://www.mintlify.com/openai/openai-python/api/realtime/events
23. Pipecat, "Interruptions" — https://docs.pipecat.ai/pipecat/fundamentals/interruptions
24. Speech Technology, "Krisp Launches VIVA 2.0" — https://www.speechtechmag.com/Articles/News/Speech-Technology-News/Krisp-Launches-VIVA-2.0-an-Infrastructure-for-Voice-AI-Agents%c2%a0-174689.aspx ; Pipecat, "Krisp VIVA" — https://docs.pipecat.ai/pipecat/features/krisp-viva
25. Google Cloud, "Gemini Live API overview" — https://docs.cloud.google.com/vertex-ai/generative-ai/docs/live-api?hl=en
26. Sipfront, "baresip Gemini Live voicebot deep dive" (gennaio 2026) e Google AI forum sul barge-in di Gemini 3.1 Flash Live — https://sipfront.com/blog/2026/01/baresip-gemini-live-voicebot-deepdive/ ; https://discuss.ai.google.dev/t/gemini-3-1-flash-live-preview-live-api-server-never-emits-interrupted-barge-in-when-the-user-is-already-speaking-as-the-models-turn-begins/174346
27. The Decoder, "ChatGPT can now listen and talk at the same time" — https://the-decoder.com/chatgpt-can-now-listen-and-talk-at-the-same-time-making-ai-conversations-seem-more-human/
28. The Next Web, "OpenAI's new GPT-Live lets ChatGPT listen and speak at the same time" (8 luglio 2026) — https://thenextweb.com/news/openai-gpt-live-chatgpt-voice-full-duplex
29. OpenAI Community, "Feature Request: Major Improvements to Voice Mode Audio Handling" — https://community.openai.com/t/feature-request-major-improvements-to-voice-mode-audio-handling-scene-awareness/1384660
30. Google, "Talk naturally with Gemini Live" — https://support.google.com/gemini/answer/15274899?hl=en
31. Double Tap, "Stop Siri interrupting itself" ("Require Siri for interruptions", iOS 17–18) — https://doubletaponair.com/michael-babcocks-top-tip-stop-siri-interrupting-itself/

Nessuna misura su Mac: la ricerca è stata fatta su Linux. Le latenze e i tassi di errore citati sono delle fonti, su hardware e audio diversi da quelli di Bubo.
