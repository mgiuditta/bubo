# Casa = Secondo cervello: finestra, brand kit, video sull'Orb

**Data**: 2026-10-04 · **Origine**: richiesta del fondatore («la UI grossa fa un po' schifo, non si capisce lo storico; il punto principale è il second brain») · **Chiude**: mappa #690 · **ADR**: [0013](../../adr/0013-il-secondo-cervello-e-la-casa.md)

Tre parti indipendenti, in quest'ordine di dipendenza: 1 (finestra) usa i token di 2 (brand kit); 3 (video) è indipendente.

## 1. La finestra: Cervello + conversazioni

Sostituisce il layout dell'HUD (Orb grande al centro con anelli, Orbita, Striscia, scheda della Sessione separata dal campo).

### Struttura

`NavigationSplitView` a due colonne, solo scuro, barra laterale in vetro di sistema.

**Barra laterale** (dall'alto):

1. Intestazione: Orb piccolo + logotipo `bubo`.
2. **Cervello** (la casa) · **Neuroni** · **Riunioni**.
3. **Conversazioni**: un elenco unico di Domande e Sessioni, a gruppi per giorno (Oggi, Ieri, Questa settimana, Prima). Una Sessione mostra il chip `⟨progetto⟩` e il pallino di Attività (`attention` solo per «Attende te»). La Cronologia CLI entra nello stesso elenco dietro un filtro («Mostra anche la riga di comando»).
4. **Progetti**: un elemento per Progetto (apre l'elenco delle sue Sessioni) + **Lavoro** (la Board di oggi: Bozze, Aperte, In revisione).
5. In fondo a sinistra: pulsante **Impostazioni**, capsula Liquid Glass alta 32 pt con icona ed etichetta.

**Colonna di destra**, la selezione:

- **Conversazione**: storico completo + composer per continuarla. Vale per Domande e Sessioni (oggi la Sessione non ha un composer nell'HUD).
- **Cervello** (vuoto): Orb grande al centro, titolo display «Chiedi al tuo cervello», tre suggerimenti dal Profilo e dalle ultime note, composer.
- **Neuroni**, **Riunioni**, **Lavoro**: le viste che esistono già, ospitate qui.

### Composer e destinatario

- Un campo solo, con un chip a sinistra: `Cervello ▾` oppure `⟨progetto⟩ ▾`. Il chip dice sempre a chi si scrive e si può cambiare a mano.
- Da Cervello, se la richiesta chiede un Progetto («entra in bubo e sistema il login»), compare la scheda di proposta («Avvio una Sessione su bubo?», `SessionProposal`). Con **Conferma** nasce la Sessione, collegata alla Domanda di partenza (link «da: ‹titolo della Domanda›» in testa), e si apre nella stessa colonna. Con **No** la risposta resta nella Domanda.
- Un clic su `[[Nota]]` apre la nota (Visore o Neuroni).

### Comportamento

- Clic su un elemento delle Conversazioni = apre quella conversazione a destra. Nessun passaggio intermedio.
- La Domanda trasformata in Sessione non sparisce: resta nell'elenco con il link alla Sessione nata da lei (cambia la decisione di #681).
- Bolla e Panel restano. «Apri la chat completa» apre la finestra su quella conversazione.
- Orb: grande solo nella vista Cervello vuota; altrove piccolo nell'intestazione, e respira mentre risponde.

### Cosa si elimina

- Viste delle Sessioni Orbita e Striscia (`SessionOrbit`, `SessionStrip`) e la scelta della Vista. Resta Elenco (la barra laterale) e Board (Lavoro).
- Anelli dell'HUD attorno all'Orb grande (`HUDRings`) dentro la finestra.

### Dominio

- `CONTEXT.md`: **HUD** diventa «la finestra di lavoro: barra laterale con Cervello, Conversazioni e Progetti, e a destra la conversazione aperta». **Vista delle Sessioni** si riduce a Elenco e Board. Nuovo termine **Destinatario**: Cervello o un Progetto, a cui va il testo del composer.
- ADR 0013.

### Test

- Unit (Swift Testing): raggruppamento per giorno dell'elenco unico; ordinamento (ultima attività); filtro della Cronologia CLI; scelta del destinatario dopo una Conferma di proposta; la Domanda d'origine resta nell'elenco con il link.
- UI test: clic su una Sessione nell'elenco → la colonna destra mostra la sua conversazione e il composer ha il chip del suo Progetto.
- Accessibilità: elenco con intestazioni di gruppo, chip con etichetta «Destinatario: …», pulsante Impostazioni raggiungibile da tastiera.

## 2. Brand kit

### Posizionamento e tono

- Riga: «Il tuo secondo cervello sul Mac. Ascolta, ricorda, poi lavora.»
- Tono: italiano, del tu, frasi brevi; Bubo dice cosa ha salvato e dove, non promette.

### Colore

Invariato (Notte, ADR 0004).

### Tipografia

| Ruolo | Carattere | Misura |
|---|---|---|
| Display (logotipo, casa, titoli delle note) | Newsreader (OFL, nell'app) | 34 |
| Titolo | SF Pro semibold, tracking −0,2 | 22 |
| Corpo della conversazione | SF Pro | 15 |
| Interfaccia | SF Pro | 13 |
| Dati, etichette maiuscole | SF Mono, cifre tabulari | 12 |

Larghezza massima di lettura nella conversazione: 720 pt. Tutti i caratteri seguono le dimensioni dinamiche (`relativeTo:`).

### Spaziatura

Token `Spacing`: `xxs 4 · xs 8 · s 12 · m 16 · l 24 · xl 32 · xxl 48`. Righe della barra laterale alte almeno 36 pt; margini dei pannelli `m`/`l`. Le viste nuove non usano numeri a mano.

### Logotipo

`bubo` minuscolo in Newsreader Medium, con la sagoma del gufo dell'icona (#228) a sinistra, alta quanto la x. Sorgente `design/brand/logotype.svg`. L'icona dell'app resta quella di oggi.

### Componenti

Pulsante capsula di vetro · riga di conversazione · chip del destinatario · scheda di proposta della Sessione · composer · stato vuoto della casa. In Swift (`Bubo/Design/`) e nella pagina `reference/brand.html`.

### Consegne

`design/brand/logotype.svg`, `Bubo/Design/Typography.swift`, `Bubo/Design/Spacing.swift`, font in `Bubo/Resources/Fonts/` (registrato in `Info.plist` con `ATSApplicationFontsPath`), `docs/design-system.md` aggiornato, `reference/brand.html`.

## 3. Video e link sull'Orb → Riunione

### File (esiste già)

`OrbPanelController` passa già audio e video a `MeetingImporter` (`MeetingImportFile.isMeetingDrop`). Si aggiunge la scopribilità: durante il trascinamento di un file media o di un link compare sotto l'Orb l'etichetta «Rilascia: trascrivo e salvo nel cervello».

### Link (nuovo)

- Ingressi: URL trascinato sull'Orb (`public.url`, senza file), oppure un URL nel menu dell'Orb «Trascrivi un video da un link…».
- `VideoDownloader` (unico tipo nuovo, in `Bubo/Meetings/`):
  1. Trova `yt-dlp`: prima nel PATH di login dell'utente, poi `~/Library/Application Support/Bubo/bin/yt-dlp`.
  2. Se manca, chiede il permesso e scarica `yt-dlp_macos` dall'ultima release di `yt-dlp/yt-dlp`, verifica lo SHA-256 contro `SHA2-256SUMS` della stessa release, lo rende eseguibile. Se il checksum non torna, cancella il file e fallisce.
  3. Aggiorna con `-U` al più una volta al giorno (solo la copia di Bubo).
  4. Scarica con `Process` senza shell: `yt-dlp -f bestaudio -x --no-playlist --print-json -o <tmp>/%(id)s.%(ext)s -- <url>`.
- L'audio va a `MeetingImporter` come un file importato. Titolo della nota dal titolo del video, fonte = URL. Impronta = URL normalizzato (schema+host minuscoli, senza frammento e parametri di tracciamento `utm_*`, `si`, `feature`).
- Un URL che yt-dlp non sa scaricare dal drop sull'Orb diventa un Allegato come oggi.

### Errori

- Link senza video: «Questo link non ha un video che posso scaricare.»
- Rete o checksum: nessun file eseguito, messaggio «Non sono riuscito a scaricare yt-dlp».
- Annullare termina il processo e cancella il temporaneo.

### Note legali

Bubo scarica solo su azione esplicita dell'utente e conserva solo l'audio temporaneo, con la stessa regola di `MeetingAudioRetention`.

### Test

- Unit: normalizzazione dell'URL; riconoscimento dei drop (file media / URL / altro); analisi di `SHA2-256SUMS`; argomenti del processo (URL dopo `--`).
- Downloader con un `yt-dlp` finto (script di test che scrive un file audio e il JSON).
- A mano (`ready-for-human`): un link YouTube vero diventa una Riunione.

## Fuori scope

- Logotipo animato, icona nuova, palette nuova.
- Video lunghi a pezzi, sottotitoli scaricati invece dell'audio (possibile ottimizzazione più avanti: `--write-subs`).
- Trascrizione con Whisper: `SpeechAnalyzer` di macOS 26 c'è già, è offline e non aggiunge dipendenze.
