# 21 — App iPhone compagna: il Telecomando

Ticket: [#232](https://github.com/mgiuditta/bubo/issues/232) (ricerca), [#235](https://github.com/mgiuditta/bubo/issues/235) (decisioni), [#239](https://github.com/mgiuditta/bubo/issues/239) (prototipo delle schermate). Mappa: [#231](https://github.com/mgiuditta/bubo/issues/231).
Ricerca del 2026-09-30 con CLI `claude` **2.1.285**, Agent SDK TS **0.3.285** (`sdk.d.ts` letto in locale), documentazione Apple e Anthropic alla stessa data. Ricerca completa: [`21-iphone-compagna.md`](https://github.com/mgiuditta/bubo/blob/research/iphone-compagna/docs/features/research/21-iphone-compagna.md) sul branch `research/iphone-compagna`. Prototipo (da buttare): [`prototypes/telecomando.html`](https://github.com/mgiuditta/bubo/blob/prototype/telecomando/prototypes/telecomando.html) sul branch `prototype/telecomando`. Decisione di architettura: [ADR 0007](../adr/0007-telecomando-su-cloudkit-senza-server.md).

> **Nota sulla ricerca.** È scritta prima delle decisioni. Remote Control non è la strada: non si aggancia alle Sessioni dell'Agent SDK, richiede un abbonamento e non è cifrato end-to-end. Il Telecomando è un'app di Bubo su CloudKit, con una cifratura propria concordata all'accoppiamento, che non dipende da ADP. La Live Activity e la revisione del diff dal telefono restano fuori dalla v1. Valgono la Mappa e la Specifica qui sotto.

In sintesi: il **Telecomando** è l'app iPhone di Bubo. Non esegue niente: segue le Sessioni del Mac, mostra cosa aspetta una decisione e manda indietro un **Verdetto** firmato con Face ID. Il motore resta sul Mac. Il trasporto è il database privato CloudKit dell'utente, con i record cifrati da una chiave concordata all'accoppiamento: niente server di Bubo, niente relay di terzi, niente dati leggibili da Apple anche senza Protezione avanzata dei dati. Remote Control di Anthropic fa già un telecomando ricco, ma solo per le sessioni interattive della CLI, solo in abbonamento e con la trascrizione sui server Anthropic. Happy è l'unico concorrente cifrato end-to-end, ma passa da un proprio server. Bubo è il primo a farlo senza server, con approvazioni firmate nel Secure Enclave e decidibili dalla schermata di blocco.

## Ricerca

Riassunto; dettagli, prove e fonti complete nel file di ricerca.

### Remote Control di Claude Code

- **Cosa fa** [1][2]: collega claude.ai/code e l'app Claude a una sessione `claude` che gira sul Mac. Conversazione dal vivo, pannello diff, subagent e workflow fermabili, cambio di modello ed effort, Richieste di permesso e `AskUserQuestion` approvabili dal telefono, push "when actions required". In server mode (`claude remote-control`) dal telefono si creano anche nuove sessioni.
- **Non vede le Sessioni di Bubo** [3]: nessuna opzione dell'Agent SDK lo accende su una `query()`; `remoteControlAtStartup` vale per "each interactive Claude Code process". In prova, `claude -p --remote-control` completa il turno senza creare una sessione remota.
- **Requisiti** [1]: Pro, Max, Team o Enterprise; niente API key né `setup-token`; solo `api.anthropic.com` (niente Bedrock, Vertex, gateway).
- **Privacy** [1]: HTTPS in uscita con relay Anthropic, **nessuna cifratura end-to-end**: la trascrizione, compresa l'attività degli strumenti, resta sui server Anthropic. Non usabile con ZDR o HIPAA.
- **Sicurezza** [1]: Trusted Devices (beta) con registrazione del dispositivo, login recente con Face ID o passkey, revoca da claude.ai.
- **Integrazione**: nessuna API per registrare una sessione dall'esterno. **Channels** (research preview) inoltra le Richieste di permesso a un server MCP, ma i canali personalizzati richiedono flag di sviluppo [5].

### Concorrenti

| Prodotto | Dove gira l'agente | Trasporto | E2E | Approvazioni dal telefono |
|---|---|---|---|---|
| **App Claude + Remote Control** [1][2] | Mac, sessioni interattive | relay Anthropic | No | Sì |
| **Happy** (MIT) [7][8] | Mac, guida Claude via SDK | Happy Server (ospitabile da sé) | **Sì** (NaCl / AES-GCM, chiavi per sessione) | Sì |
| **Codex nell'app ChatGPT** [10] | Mac o Windows con l'app desktop | relay OpenAI | Non dichiarata | Sì |
| **Cursor Remote Control** [11][12] | loop nel cloud Cursor, strumenti sul Mac | server Cursor | No | Non documentato |
| **Conductor** [13] | solo workspace cloud | — | — | — |

Schema comune: QR per accoppiare, account del fornitore, relay del fornitore, push dal backend del fornitore. Nessuno usa CloudKit o la rete locale.

### Trasporto Apple senza server

- **CloudKit, database privato** [15]–[20]: `CKQuerySubscription` e `CKDatabaseSubscription` generano push **visibili** con `category` (azioni) e `shouldSendMutableContent` (una Notification Service Extension scarica e decifra prima di mostrare), oppure silenziose (~2–3 all'ora, non garantite). **Nessuna latenza documentata.** Serve lo stesso container e lo stesso account iCloud su Mac e iPhone.
- **Cifratura** [23]: `encryptedValues` cifra sul dispositivo, ma Apple garantisce chiavi solo dell'utente **con ADP**. Per un E2E certo serve una chiave propria concordata all'accoppiamento (CryptoKit) e solo testo cifrato in CloudKit.
- **APNs diretto e Live Activity via push** [24]–[26]: richiedono un provider server con la chiave `.p8`. Metterla nell'app del Mac darebbe a chiunque il potere di mandare push a tutte le app del team.
- **Rete locale** [31]–[34]: Bonjour funziona solo in primo piano su iOS. Wi‑Fi Aware e DeviceDiscoveryUI di iOS 26 non supportano il Mac.
- **Developer ID** [22]: CloudKit e push su un'app Mac fuori dall'App Store richiedono un provisioning profile Developer ID con quelle capability. Non dichiarato in chiaro da Apple: va provato.

### Approvazioni sicure

- `UNNotificationAction` con `.authenticationRequired` esegue l'azione solo dopo Face ID o codice [28].
- Chiave P-256 nel **Secure Enclave**, non sincronizzata, invalidata da un nuovo enrollment con `.biometryCurrentSet` [36][37]. Il Mac verifica la firma con la chiave pubblica ricevuta all'accoppiamento. È lo stesso principio dei Trusted Devices.

## Il meglio da battere

Il riferimento è **Remote Control** nell'app Claude: vede tutto, approva le Richieste, manda push, protegge i dispositivi con Face ID. Ma non vede le Sessioni dell'Agent SDK, non funziona con API key e tiene la trascrizione sui server Anthropic. **Happy** è l'unico con cifratura end-to-end, ma serve un suo server. **Codex nell'app ChatGPT** approva comandi da remoto passando dal relay di OpenAI. Nessuno approva una Richiesta dalla schermata di blocco con una firma verificabile, nessuno funziona senza un server del fornitore.

## Rischi e casi limite

- **Latenza CloudKit non documentata**: se le push arrivano in minuti, il Telecomando non serve per le Richieste. Per questo il primo ticket è un cancello di misura.
- **Developer ID e CloudKit**: se il provisioning non funziona fuori dall'App Store, la strada si ferma.
- **Push silenziose limitate e non garantite**: il Battito non può contare su di esse. Si basa su record scritti dal Mac e letti quando l'app è aperta.
- **Mac in stop**: nessun lavoro, nessun Battito. Il coperchio chiuso senza monitor esterno ferma tutto.
- **Verdetto rigiocato o in ritardo**: un Verdetto intercettato o arrivato dopo che la Richiesta è stata risolta sul Mac non deve valere.
- **Face ID cambiato**: la chiave del Secure Enclave si invalida; l'iPhone non può più firmare.
- **Doppia notifica**: Mac e iPhone che suonano insieme mentre l'utente è al Mac.
- **Quota iCloud piena**: `quotaExceeded`, record non scritti.
- **Account iCloud diverso** su Mac e iPhone: nessun record visibile.
- **Testo della notifica**: i campi cifrati non possono andare negli argomenti di localizzazione di CloudKit; il testo si costruisce nell'estensione.
- **Dati sensibili sul telefono**: il comando di una Richiesta può contenere percorsi, nomi di host, a volte segreti.

## Mappa

Architettura comune in [INDEX.md](INDEX.md). Si appoggia su Sessioni, Attività e Fase (01, 06), Richieste di permesso, Regole e Livello di rischio (05), pipeline degli ingressi e Domanda (09, 10), Budget (18), Automazioni (19), Canali e firma (27).

### Strada (deciso)

Fonte: [#235](https://github.com/mgiuditta/bubo/issues/235), [ADR 0007](../adr/0007-telecomando-su-cloudkit-senza-server.md).

- **App iPhone di Bubo** (il Telecomando) su **CloudKit**, database privato, cifrata end-to-end con una chiave propria. Niente server né relay di Bubo o di terzi.
- **Non Remote Control**: chi usa `claude --rc` nel terminale continua con l'app Claude.
- **Dispositivi**: solo iPhone, iOS 26. iPad come "Designed for iPhone"; Apple Watch solo con le notifiche in copia. Niente app Watch in v1.

### Schermate e azioni (deciso)

Fonte: [#235](https://github.com/mgiuditta/bubo/issues/235), [#239](https://github.com/mgiuditta/bubo/issues/239) (vince la variante **B, Coda**, con la scheda Sessioni e il dettaglio della variante A).

- **Schede**: Attende te (contatore) · Sessioni · Domanda · Mac. L'app si apre sempre su Attende te.
- **Attende te**: riga del Battito in cima; riquadri dal più vecchio, ognuno con Progetto e titolo.
  - Richiesta di Livello 1–3: motivo, strumento e comando, percorso, "scade tra N min", pulsanti No · Solo ora · Per questa Sessione (primario), nota "Sempre in questo Progetto: solo dal Mac".
  - Richiesta di Livello 4–5: un solo pulsante, "Rivedi e decidi", che apre l'approvazione a pagina intera.
  - Domanda dell'agente (`AskUserQuestion`): le opzioni come pulsanti più "Rispondi…".
  - Vuoto: "Niente da decidere", quante Sessioni lavorano e, sotto, **Novità**: l'ultimo messaggio di ogni Sessione senza richieste.
- **Sessioni**: gruppi per Progetto; riga con punto di Attività, titolo, "Attività · Fase · N file".
- **Dettaglio**: Progetto, Fase, titolo, Attività, statistiche del diff (file e righe ±), Richiesta o domanda in attesa, estratto degli ultimi messaggi, barra Rispondi (testo o dettatura), **Ferma** in alto a destra in rosso.
- **Domanda**: scelta del Progetto (l'ultimo usato per default) e barra di testo o dettatura, con la riga "Parte sul Mac".
- **Mac**: Mac accoppiati con il Battito, "+ Accoppia un altro Mac", "Revoca questo iPhone" in rosso, nota "Serve lo stesso Apple ID".
- **Fuori v1**: revisione del diff e merge, nuova Sessione, Board, Galassia, Costi, Live Activity.

### Richieste di permesso da remoto (deciso)

- **Livelli 1–3**: dall'azione della notifica o dal riquadro, con Face ID. Risposte No, Solo ora, Per questa Sessione.
- **Livelli 4–5**: solo aprendo l'app, sulla pagina di approvazione con il comando completo, con Face ID. Risposte solo No o Solo ora.
- **Sempre in questo Progetto**: solo dal Mac.
- **Verdetto** firmato nel Secure Enclave (P-256, `.biometryCurrentSet`) su ID della Richiesta, nonce, risposta e ora. Il Mac scarta i Verdetti non firmati, con firma di un Dispositivo accoppiato revocato, scaduti (> 10 min) o per Richieste già risolte.

### Accoppiamento e revoca (deciso)

- **Stesso Apple ID** su Mac e iPhone: requisito dichiarato.
- **QR** in Impostazioni › iPhone, valido 5 minuti, con la chiave pubblica ECDH del Mac e un codice monouso. Lo scambio passa da CloudKit. La chiave simmetrica derivata cifra tutti i record.
- **Codice di verifica a 6 cifre** mostrato su Mac e iPhone durante l'accoppiamento ([#239](https://github.com/mgiuditta/bubo/issues/239)): protegge da un QR fotografato da altri.
- **Molti a molti**: una chiave per coppia Mac–iPhone.
- **Revoca** da entrambi i lati: ruota la chiave e cancella i record. Un nuovo enrollment di Face ID invalida la chiave di firma: serve un nuovo accoppiamento.

### Dati che escono dal Mac (deciso)

- **Escono, cifrati**: titolo della Sessione, Progetto, Attività, Fase, estratto degli ultimi messaggi, Richiesta in attesa (strumento, comando, percorso), statistiche del diff.
- **Mai**: contenuti dei file, trascrizione completa, Allegati.
- **Consenso**: accendere il Telecomando in Impostazioni › iPhone è il consenso; il testo accanto all'interruttore elenca cosa esce. Sull'iPhone lo stesso elenco sta nel riquadro "Cosa arriva sull'iPhone" dell'accoppiamento.
- **Vita dei record**: cancellati alla risoluzione e comunque dopo 24 h.
- **Progetti solo Mac**: interruttore per Progetto; le sue Sessioni non escono.

### Push (deciso)

- **Time-sensitive con azioni**: Richiesta di permesso e domanda dell'agente.
- **Passive**: errore, fine lavoro, avviso di Budget. Automazione: solo se fallita.
- **Nessuna push** se l'utente è attivo al Mac: input negli ultimi 2 minuti e schermo sbloccato.
- **Già risolta**: se la Richiesta si risolve sul Mac, la notifica si ritira; un'azione arrivata tardi mostra "Già risolta sul Mac". Un Verdetto scaduto mostra "Scaduta: rispondi dal Mac".

### Mac in stop (deciso)

- Bubo impedisce lo stop per inattività mentre una Sessione Lavora o Attende te, **solo con l'alimentatore**, acceso per default e disattivabile.
- L'iPhone mostra sempre il Battito ("Visto 30 s fa", in `textSecondary`); con più di 2 minuti o il Mac che dorme il testo passa a `textPrimary` con un simbolo (orologio o luna) e "i dati possono essere vecchi". Nessuna tinta: è il design system (ADR 0004), non un segnale.
- Coperchio chiuso senza monitor esterno: limite dichiarato.

### Cancello (deciso)

Primo ticket di costruzione: 100 push Mac → iPhone con una build Developer ID con CloudKit. Soglia **p50 ≤ 5 s, p95 ≤ 30 s**.
- **Latenza fallita** → ripiego "Telecomando in rete locale" (Bonjour, solo in primo piano) e un ADR.
- **Developer ID senza CloudKit** → la 21 si ferma, si riapre la questione del relay con un ADR.

### Dettagli di costruzione

Scelti scrivendo la spec, non nelle issue. Si possono cambiare senza toccare le decisioni sopra.

- **Un solo container** `iCloud.<team>.bubo` condiviso da Mac e iPhone, zona personalizzata `Telecomando` nel database privato. Ambiente Production dallo stesso schema; lo schema si distribuisce con uno script in CI, non dalla console a mano.
- **Tipi di record** (tutti con un unico campo `payload` di byte cifrati, più metadati in chiaro non sensibili):
  - `Pairing`: chiave pubblica ECDH, codice monouso, scadenza. È l'unico record in chiaro, e vive 5 minuti.
  - `Device`: identificativo casuale del Dispositivo accoppiato, chiave pubblica di firma, nome scelto dall'utente (cifrato), stato (attivo o revocato).
  - `Heartbeat`: uno per Mac, riscritto ogni 60 s mentre Bubo è aperto e il Mac è sveglio.
  - `SessionCard`: una per Sessione esposta, riscritta a ogni cambio di Attività, Fase o estratto, al massimo una volta ogni 5 s per Sessione.
  - `Request`: una per Richiesta di permesso o domanda dell'agente in attesa; il suo `category` pilota le azioni della notifica.
  - `Verdict`: scritto dall'iPhone, con la firma; lo legge il Mac con una subscription.
  - `Command`: scritto dall'iPhone per Rispondi, Domanda e Ferma, firmato come un Verdetto.
- **Metadati in chiaro**: tipo di record, ID casuale del Mac, scadenza, `category` della notifica. Mai titoli, Progetti, comandi o percorsi.
- **Cifratura**: X25519 per l'accordo, HKDF-SHA256 con il codice monouso come sale, ChaCha20-Poly1305 per i record, con l'ID del record come dato associato. Una chiave per coppia Mac–iPhone; il Mac cifra una copia per ogni Dispositivo accoppiato.
- **Firma**: P-256 nel Secure Enclave con `.biometryCurrentSet` e `.privateKeyUsage`. Il messaggio firmato è `requestID ‖ nonce ‖ risposta ‖ timestamp ‖ macID`. Il Mac tiene gli ultimi nonce per 10 minuti e rifiuta i doppioni.
- **Testo della notifica**: `shouldSendMutableContent`, `category` e `desiredKeys` (`payload`, `macID`, `deviceID`) stanno nella `CKQuerySubscription` sui record `Request`, una per categoria con predicato sul campo in chiaro `category`, con un alert di ripiego. La Notification Service Extension legge il `payload` dalla push, lo decifra con la chiave della coppia (portachiavi condiviso con l'app) e scrive titolo ("Progetto · Sessione"), corpo (motivo e comando abbreviato) e sottotitolo ("Livello N · scade tra 10 min"), con `interruptionLevel = .timeSensitive`. Se la decifratura fallisce: "Bubo: una Sessione aspetta una decisione", senza azioni. Una Richiesta risolta sul Mac dopo la push riscrive il record come risolta (categoria `RESOLVED`): l'estensione mostra "Già risolta sul Mac" senza azioni; senza push il record si cancella.
- **Azioni della notifica**: la categoria viene dalla Richiesta, non dal solo Livello, come per le notifiche del Mac. `REQUEST_LOW` con Consenti per questa Sessione · Consenti solo ora · No (distruttiva), tutte `.authenticationRequired`; `REQUEST_LOW_ONCE` senza Per questa Sessione, quando il Mac non la offre; `REQUEST_HIGH` con la sola "Apri per decidere" per i Livelli 4–5, le chiamate che `claude` vuole confermate e quello che la notifica del Mac non approverebbe (comando lungo, caratteri invisibili, fuori Sandbox); categoria `QUESTION` con fino a 3 opzioni più "Rispondi…" (`UNTextInputNotificationAction`). Dall'azione, la firma usa un `LAContext` con `touchIDAuthenticationAllowableReuseDuration`: il Face ID dello sblocco vale anche per la chiave; se la firma fallisce, una notifica dice perché e apre la Richiesta.
- **Presenza al Mac**: `CGEventSourceSecondsSinceLastEventType` < 120 s, schermi accesi e sessione utente in primo piano (`NSWorkspace`, segnali pubblici) → il record `Request` si scrive senza `category`, quindi senza push. Se l'utente si allontana con la Richiesta ancora aperta, il record riceve la categoria e la notifica parte al passaggio (ricontrollo ogni 30 s). Un Mac bloccato con lo schermo acceso conta come assente dopo i 2 minuti. Con una Richiesta fuori, il Mac legge i `Verdict` ogni 3 s invece di aspettare le push silenziose.
- **Stop impedito**: `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep)` presa quando la prima Sessione passa a Lavora o Attende te con alimentatore, rilasciata quando nessuna resta in quegli stati o si passa a batteria.
- **Ferma dal telefono**: stesso effetto di Ferma sul Mac (interruzione del turno). Nessuna conferma ulteriore oltre Face ID.
- **Rispondi e Domanda**: il testo arriva al Mac come `Command` e passa dalla pipeline degli ingressi (09) come un prompt scritto; la Domanda usa il Progetto scelto e il router (10). Gli Allegati dal telefono sono fuori v1.
- **Pulizia**: il Mac cancella `Request`, `Verdict` e `Command` risolti; un job all'avvio e ogni ora cancella tutto ciò che ha più di 24 h. L'iPhone non conserva niente su disco oltre la cache del dettaglio aperto.
- **Solo Mac**: il Progetto con l'interruttore acceso non produce `SessionCard` né `Request`; la Domanda dal telefono non lo elenca.
- **Budget e Automazioni**: le notifiche passive usano i testi già scritti per le notifiche del Mac (18, 19), senza importi quando il Progetto è solo Mac.
- **Canali**: l'app iPhone esce con TestFlight insieme alle beta del Mac e in App Store per la stabile; la versione del protocollo sta nel record `Device` e un iPhone troppo vecchio vede "Aggiorna il Telecomando".

### Moduli

Architettura comune in [INDEX.md](INDEX.md). Target nuovi:

- `BuboRemote` (app iOS 26, SwiftUI) con `RemoteNotificationService` (Notification Service Extension).
- `RemoteKit` (pacchetto condiviso Mac e iPhone): tipi dei record, cifratura (`PairingCrypto`, `RecordSealer`), firma e verifica (`VerdictSigner`, `VerdictVerifier`), versione del protocollo. Codice puro dove possibile, testato su entrambe le piattaforme.

Moduli nuovi sul Mac:

- `Remote/RemoteBridge`: pubblica `SessionCard`, `Request` e `Heartbeat`; legge `Verdict` e `Command` con `CKDatabaseSubscription`.
- `Remote/PairingController`: QR, codice di verifica, scambio, revoca.
- `Remote/PresenceMonitor`: utente al Mac sì o no.
- `Remote/SleepGuard`: asserzione contro lo stop.
- `Settings/RemoteSettingsView`: Impostazioni › iPhone.

Estensioni: `Permissions/RequestCenter` (una Richiesta può essere risolta da un Verdetto; stesso percorso della risposta dall'HUD), `Intake/` (Command → prompt), `System/Notifications` (niente doppioni quando il Telecomando manda la push), `Sessions/` (estratto degli ultimi messaggi per la card).

### Flusso

1. **Accoppiamento**: Impostazioni › iPhone → accendi il Telecomando (consenso) → QR → l'iPhone lo inquadra → scambio ECDH via CloudKit → codice a 6 cifre uguale sui due schermi → "Accoppia con Face ID" crea la chiave di firma → il Mac salva la chiave pubblica → "Accoppiato".
2. **Richiesta di Livello 1–3**: la Sessione chiede → `RequestCenter` → `PresenceMonitor` dice "non al Mac" → `RemoteBridge` scrive `Request` → push visibile → estensione decifra → l'utente tocca "Consenti per questa Sessione" → Face ID → firma → `Verdict` → il Mac verifica (firma, scadenza, non risolta, nonce) → risponde a `canUseTool` → cancella i record.
3. **Richiesta di Livello 4–5**: come sopra, ma la notifica ha solo "Apri per decidere" → pagina di approvazione → No o Consenti solo ora con Face ID.
4. **Risposta, Domanda, Ferma**: dall'app → `Command` firmato → il Mac verifica → pipeline degli ingressi o interruzione.
5. **Revoca**: da un lato qualsiasi → record `Device` revocato → l'altro lato cancella la chiave e i record.

### Casi limite

- **Richiesta risolta sul Mac mentre l'iPhone decide**: il Verdetto arriva, il Mac lo scarta; l'iPhone mostra "Già risolta sul Mac".
- **Verdetto dopo 10 minuti**: scartato; la Richiesta resta aperta sul Mac.
- **Due iPhone accoppiati che rispondono insieme**: vale il primo Verdetto valido; il secondo vede "Già risolta".
- **Nonce ripetuto**: scartato e registrato nel log del Mac.
- **Face ID riconfigurato**: la firma fallisce; l'app mostra "Accoppia di nuovo questo iPhone" e rimanda a Mac › + Accoppia.
- **Mac che dorme o Bubo chiuso**: il Battito invecchia; le azioni di Rispondi, Domanda e Ferma restano in coda nel record e il Mac le esegue al risveglio solo se hanno meno di 10 minuti; poi scadono con una nota sull'iPhone.
- **Quota iCloud piena**: il Mac mostra in Impostazioni › iPhone "iCloud pieno: il Telecomando è fermo" e smette di scrivere; nessuna notifica di sistema.
- **Account iCloud diverso o disconnesso**: accoppiamento impossibile, con il testo "Serve lo stesso Apple ID su Mac e iPhone".
- **Progetto solo Mac** con una Richiesta: nessun record, nessuna push; la Richiesta resta sul Mac.
- **Automazione riuscita**: nessuna push; fallita: push passiva.
- **iPhone con versione del protocollo vecchia**: nessun record decifrato; l'app chiede di aggiornarsi.
- **Sessione su una Macchina remota** (23): uguale a una locale; la card porta anche il nome dell'host.
- **Comando lungo**: nella notifica si abbrevia; nella pagina di approvazione va a capo e non si tronca mai.

### Test

- `RemoteKit`: accordo di chiave, cifratura e decifratura, dati associati sbagliati → fallimento; firma e verifica su tutti i campi; nonce ripetuto, scadenza, Dispositivo revocato → rifiuto. Test su macOS e iOS.
- **Cancello di latenza**: 100 Richieste finte dal Mac, misura dall'`insert` del record alla consegna della notifica sull'iPhone (timestamp nell'estensione) → p50 e p95 nel report; build Developer ID.
- **End-to-end su dispositivo**: accoppiamento in ≤ 30 s dal QR; Richiesta di Livello 2 approvata dalla schermata di blocco; Livello 5 solo da app; Verdetto scaduto scartato; Richiesta risolta sul Mac prima del Verdetto; revoca da ciascun lato.
- **Presenza**: con input negli ultimi 2 minuti e schermo sbloccato → 0 push; dopo 2 minuti → push.
- **Dati in chiaro**: ispezione dei record in CloudKit Dashboard durante i test → nessun titolo, Progetto, comando o percorso leggibile.
- **Pulizia**: record più vecchi di 24 h → 0 dopo il job.
- **Stop impedito**: con una Sessione che Lavora e l'alimentatore, `pmset -g assertions` mostra l'asserzione; a batteria o senza Sessioni attive no.
- Accessibilità: audit SwiftUI dell'app (riquadri come gruppi VoiceOver con azioni personalizzate, contatore "N in attesa", Dynamic Type sul comando) e di Impostazioni › iPhone.

### Ordine di costruzione

1. **Cancello di latenza e Developer ID**: container CloudKit, provisioning del Mac con CloudKit e push, app iPhone minima che riceve una push da `CKQuerySubscription`, misura su 100 push. Esito nel ticket; se fallisce, ADR di ripiego. Dipende da 27 (certificato e profili, [#220](https://github.com/mgiuditta/bubo/issues/220)).
2. **Accoppiamento e cifratura**: `RemoteKit` (cifratura, firma), `PairingController`, Impostazioni › iPhone con consenso e QR, scheda Mac dell'iPhone, codice a 6 cifre, revoca. Dipende da 1.
3. **Sessioni e Battito**: `RemoteBridge` con `SessionCard` e `Heartbeat`, schede Sessioni e dettaglio (senza Richieste), Progetti solo Mac, pulizia a 24 h. Dipende da 2 e da 06.
4. **Richieste dalla notifica e dall'app**: record `Request`, Notification Service Extension, categorie e azioni, Verdetto firmato, verifica sul Mac, scheda Attende te, pagina dei Livelli 4–5, `PresenceMonitor`. Dipende da 3 e da 05.
5. **Rispondi, Domanda e Ferma**: `Command` firmati, pipeline degli ingressi, scheda Domanda, domande dell'agente. Dipende da 4 e da 09.
6. **Notifiche passive e Mac in stop**: errore, fine lavoro, Budget, Automazioni fallite; `SleepGuard`. Dipende da 4, 18 e 19.

## Specifica "migliore di"

Migliori concorrenti: **Remote Control** (ricco, ma senza Agent SDK, solo in abbonamento, trascrizione sui server Anthropic), **Codex nell'app ChatGPT** (approvazioni via relay OpenAI) e **Happy** (E2E, ma con un server proprio).
Bubo li supera così:

1. **Zero server**: **0** relay di Bubo o di terzi; solo il database privato CloudKit dell'utente.
2. **E2E sempre**: **0** campi sensibili leggibili in CloudKit, anche senza ADP (verifica sui record).
3. **Qualunque account**: funziona con abbonamento **e** con API key.
4. **Decisione dalla schermata di blocco**: Livelli 1–3 approvati con **1 tocco + Face ID**, senza aprire l'app.
5. **Verdetti sicuri**: **100%** firmati nel Secure Enclave, **0** riutilizzabili, scadenza **10 min**.
6. **Richiesta → notifica**: **p50 ≤ 5 s, p95 ≤ 30 s** (cancello di costruzione).
7. **Accoppiamento veloce**: **≤ 30 s** dal QR all'"Accoppiato".
8. **Nessun doppione**: **0** push quando l'utente è al Mac.

### Dove perdiamo

- **Latenza best effort**: CloudKit non garantisce tempi; Remote Control e Happy hanno un canale sempre aperto.
- **Niente Live Activity** (richiede un server APNs).
- **Niente revisione del diff né merge dal telefono**: solo statistiche.
- **Stesso Apple ID** obbligatorio su Mac e iPhone.
- **Solo iPhone**: niente app Watch, niente iPad nativo, niente Android.

## Fonti

1. Claude Code, *Remote Control* — https://code.claude.com/docs/en/remote-control
2. Claude Code, *Claude Code on mobile* — https://code.claude.com/docs/en/mobile
3. `@anthropic-ai/claude-agent-sdk` 0.3.285, `sdk.d.ts`; CLI `claude` 2.1.285, prova `claude -p --remote-control`
4. Claude Code, *Desktop — Sessions from Dispatch* — https://code.claude.com/docs/en/desktop
5. Claude Code, *Channels reference* — https://code.claude.com/docs/en/channels-reference
6. Claude Code, *Cross-session messaging* — https://code.claude.com/docs/en/cross-session-messaging
7. Happy, README — https://github.com/slopus/happy
8. Happy, *encryption.md* — https://github.com/slopus/happy/blob/main/docs/encryption.md
9. Happy, documentazione dell'architettura — https://github.com/slopus/happy/tree/main/docs
10. OpenAI, *Remote connections* — https://learn.chatgpt.com/docs/remote-connections
11. Cursor, *Web and mobile* — https://cursor.com/docs/cloud-agent/web-and-mobile
12. Cursor, *Mobile* — https://cursor.com/docs/cloud-agent/mobile
13. Conductor, changelog — https://www.conductor.build/changelog
14. Omnara — https://github.com/omnara-ai/omnara
15. Apple, `CKDatabaseSubscription` — https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription
16. Apple, `CKQuerySubscription` — https://developer.apple.com/documentation/cloudkit/ckquerysubscription
17. Apple, `CKSubscription.NotificationInfo` — https://developer.apple.com/documentation/cloudkit/cksubscription/notificationinfo-swift.class
18. Apple, *Pushing background updates to your App* — https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app
19. Apple, `CKSyncEngine` — https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5
20. Apple, `CKError.quotaExceeded`, `requestRateLimited` — https://developer.apple.com/documentation/cloudkit/ckerror/code/quotaexceeded
21. Apple, `icloud-container-identifiers` — https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.icloud-container-identifiers
22. Apple Developer Forums, CloudKit con Developer ID — https://developer.apple.com/forums/thread/18443
23. Apple, `CKRecord.encryptedValues` — https://developer.apple.com/documentation/cloudkit/ckrecord/encryptedvalues ; ADP — https://support.apple.com/guide/security/advanced-data-protection-for-icloud-sec973254c5f/
24. Apple, *Setting up a remote notification server* — https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server
25. Apple, *Establishing a token-based connection to APNs* — https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns
26. Apple, *Starting and updating Live Activities with ActivityKit push notifications* — https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications
27. Apple, *Displaying live data with Live Activities* — https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
28. Apple, `authenticationRequired` — https://developer.apple.com/documentation/usernotifications/unnotificationactionoptions/authenticationrequired
29. Apple, `UNNotificationCategory`, `UNNotificationInterruptionLevel` — https://developer.apple.com/documentation/usernotifications/unnotificationcategory
30. Apple, entitlement critical alerts — https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.usernotifications.critical-alerts
31. Apple, `NSLocalNetworkUsageDescription` — https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription
32. Apple, `NSBonjourServices`, `NWBrowser` — https://developer.apple.com/documentation/network/nwbrowser
33. Apple, DeviceDiscoveryUI — https://developer.apple.com/documentation/devicediscoveryui
34. Apple, Wi‑Fi Aware — https://developer.apple.com/documentation/wifiaware
35. Apple, `NSUserActivity` — https://developer.apple.com/documentation/foundation/nsuseractivity
36. Apple, *Protecting keys with the Secure Enclave* — https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave
37. Apple, `biometryCurrentSet` — https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/biometrycurrentset
