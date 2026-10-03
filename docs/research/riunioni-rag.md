# Riunioni nel Secondo cervello

Ricerca del 2026-10-03: `/last30days` su Reddit, YouTube, Hacker News e GitHub (72 voci), più tre ricerche web. Il file grezzo è in `~/Documents/Last30Days/obsidian-rag-for-meeting-notes-and-transcripts-raw-v3.md`. Richiesta dell'utente: un RAG gestito dall'AI di Bubo, con le riunioni salvate e indicizzate nel vault Obsidian.

In sintesi: **il RAG c'è già.** Il **Secondo cervello** è il vault, l'**Indice** fa la ricerca locale per significato e per parole (Qwen3-Embedding, SQLite, FSEvents) e l'agente lo interroga con lo strumento `cerca`. Mancano tre pezzi: le Riunioni come sorgente (registrazione e import), i documenti non Markdown, e le risposte con le note citate.

## Cosa fanno gli altri (settembre e ottobre 2026)

- **Registratori per Mac senza bot**: Quill, Daisy, Meetily (oltre 11.000 stelle), Meeting Transcriber, Parrot (Show HN del 30/09). Lo schema è lo stesso per tutti:
  - due tracce, il microfono con AVFoundation e l'audio dell'app con i **Core Audio process taps** (macOS 14.2+, nessun bot nella chiamata);
  - trascrizione sul Mac;
  - diarizzazione offline (sherpa-onnx o WhisperKit), cioè chi ha parlato e quando;
  - una nota Markdown come risultato.

  Gli utenti chiedono "locale, gratis, niente cloud", come in Shepit #3: "Existing meeting-note tools are paid, cloud-based".
- **Trascrizione**: su macOS 26, SpeechAnalyzer con SpeechTranscriber gira sul Mac, è pensato per "lectures, meetings, and conversations", ed è circa il 55% più veloce di Whisper Large-v3. Bubo lo usa già per la voce (`SpeechListener`).
- **Obsidian più AI**: i video più visti (Greg Isenberg 460.000 visualizzazioni, Nick Milo 330.000) usano Claude Code sul vault. Nick Milo avverte: "if you point an AI at 17,000 interconnected notes with no map, it's going to pretend that it's reviewed all of your notes". Il recupero conta più del modello che genera la risposta.
- **Qualità del recupero**: LifeOS (#1250, 29/09) ha corretto prima BM25 e i facet, misurando su 28 coppie domanda→file reali, e solo dopo è passato agli embedding. Conferma la scelta dell'Indice (ricerca ibrida, Recall@1) e il ticket #424.

## Decisioni proposte

1. **Riunione** è un nuovo termine del glossario: una conversazione registrata o importata. Diventa una nota nel Secondo cervello con trascrizione, riassunto, decisioni e azioni.
2. **Cattura**: microfono e audio di un'app scelta, su due tracce. Permessi chiesti al primo uso. Niente bot e niente cloud. Avviso di registrazione sempre visibile, e l'utente dichiara di aver informato i partecipanti.
3. **Trascrizione**: SpeechTranscriber sul Mac. La diarizzazione arriva in un secondo ticket: le due tracce danno già "io / loro".
4. **Nota**: in `Bubo/Riunioni/AAAA-MM-GG titolo.md`, con proprietà Obsidian (data, durata, partecipanti, app). Riassunto e azioni li scrive il motore dei riassunti, che esiste già (`SummaryEngine`). L'audio resta fuori dal vault, in Application Support, con una durata scelta dall'utente.
5. **Indice**: oggi la cartella `Bubo/` è esclusa dalla ricerca, per evitare che l'Indice risponda con se stesso. `Bubo/Riunioni/` diventa un'eccezione: le Riunioni sono fonti, non riassunti di Bubo.
6. **Risposte con citazioni**: quando una Domanda usa `cerca`, la risposta cita le note con `[[nota]]` e, per le Riunioni, il minuto. Le citazioni sono cliccabili e aprono Obsidian o l'anteprima.
7. **Import**: trascinare audio o video, `.vtt`, `.srt`, `.txt`, PDF o `.docx` produce una nota Riunione o Documento, con la stessa pipeline.
