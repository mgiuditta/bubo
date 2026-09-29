# Bubo — brief di progetto originale

> Brief iniziale, conservato così com'è. Le decisioni prese dopo (mappa wayfinder, `CONTEXT.md`, `docs/adr/`) prevalgono dove lo contraddicono: per esempio ADR 0001 (solo macOS 26) e ADR 0002 (Catalogo di Varianti con nome al posto di 12 campi × 1.000 seed).

Costruisci **Bubo**, un assistente agentico nativo per macOS in stile "Jarvis": un orb 3D arancione sempre disponibile, che ascolta, parla, sceglie da solo il modello AI migliore per ogni richiesta, lavora su file e progetti tramite il Claude Agent SDK e, se l'utente lo vuole, gestisce il suo secondo cervello in Obsidian.

L'app deve sembrare **premium** in ogni dettaglio grafico e deve essere **proattiva e comoda**: raggiungibile da ovunque nel sistema, con il minimo di clic.

In allegato c'è `bubo.html` (ora `reference/bubo.html`), il prototipo web già approvato: look, stati, router, morph e shader. Usalo come riferimento visivo e porta la stessa resa in Metal.

---

## 1. Vincoli fondamentali

- **Solo macOS**, nativo: Swift 6, SwiftUI, AppKit dove serve, Metal per il rendering. Target macOS 15+ (usa le API di macOS 26 quando disponibili, con fallback).
- **Non clonare Claude Code**: è proprietario. Il motore agentico è il **Claude Agent SDK** (TypeScript), eseguito in un processo helper Node incluso nell'app.
- **Autenticazione**: il modo predefinito è l'**abbonamento Claude dell'utente** (login come da terminale), così chi non ha credito API usa comunque Claude. In alternativa, API key. Dettagli nella sezione 2-bis.
- **Distribuzione**: DMG firmato e notarizzato, fuori dal Mac App Store. L'app principale non è in sandbox (l'agente deve eseguire comandi e accedere ai file). Le estensioni (Finder, Share) seguono le regole di sandbox delle estensioni.
- **Nome e marchi**: il prodotto si chiama Bubo. Niente "Jarvis" nel prodotto, niente loghi di marchi reali (Anthropic, OpenAI, Google…): ogni fornitore ha una firma astratta (colore, texture, forma).

---

## 2. Architettura

```
Bubo.app (SwiftUI + Metal)
├─ OrbPanel         overlay NSPanel trasparente, sempre in primo piano, orb Metal
├─ HUD              interfaccia principale (stati, router, forme, cronologia)
├─ VoiceEngine      wake word, voce→testo, testo→voce, interruzione
├─ Router           classificatore veloce → scelta del modello e del "campo"
├─ ModelGateway     OpenRouter + Anthropic API, streaming
├─ AgentBridge      processo Node con Claude Agent SDK (file, bash, MCP, subagent)
├─ BrainService     integrazione Obsidian (opzionale)
├─ SystemIntegration Finder Sync, Apri con, Services, Share, App Intents, hotkey, menu bar
└─ Galaxy3D         vista 3D del progetto o del vault
```

- Comunicazione Swift ↔ Node via JSON in streaming su stdio (messaggi tipizzati, con versione del protocollo).
- Sessioni multiple in parallelo, ciascuna isolata in un git worktree quando si lavora su un repo.
- Tutti i dati restano in locale (cronologia, embedding, impostazioni).

---

## 2-bis. Accesso a Claude: abbonamento o API key

Bubo deve funzionare anche per chi **non ha credito API** ma ha un abbonamento Claude (Pro, Max, Team, Enterprise).

**Modalità A — Abbonamento Claude (predefinita)**
- Anthropic permette alle app di terze parti di autenticarsi con l'abbonamento dell'utente tramite l'Agent SDK. L'uso viene scalato da un **credito mensile dedicato all'Agent SDK**, separato dai limiti della chat: Pro 20 $, Max 5x 100 $, Max 20x 200 $, Team ed Enterprise per posto. Il credito è personale e si rinnova con il ciclo di fatturazione.
- Onboarding: Bubo controlla se la CLI `claude` è installata e già autenticata.
  - Se sì, mostra "Collegato come <account>" e la usa sotto il cofano.
  - Se no, un pulsante "Accedi con Claude" avvia il login ufficiale (stesso flusso di `claude /login` nel terminale, nel browser). Se manca la CLI, Bubo propone di installarla con l'installer ufficiale.
- Bubo **non legge, copia né salva** le credenziali di Claude: le gestisce la CLI/SDK ufficiale. Ogni utente usa il proprio account; nessuna credenziale condivisa.
- Mostrare nell'HUD il consumo del credito Agent SDK del mese e un avviso quando si avvicina al limite.
- Quando il credito finisce: se l'utente ha attivato i crediti extra nel suo account, si continua; altrimenti Bubo lo dice chiaramente e propone di passare alla modalità B o di aspettare il rinnovo.

**Modalità B — API key**
- API key Anthropic nel Portachiavi, per chi preferisce pagare a consumo o ha finito il credito.

**Modalità C — Altri modelli**
- OpenRouter (API key) per i modelli non Claude del router. Facoltativa: senza, il router sceglie solo tra i modelli Claude.

**Regole**
- Impostazioni → Account: scelta della modalità, stato del collegamento, credito residuo, pulsante "Esci".
- Fallback configurabile: abbonamento → API key → solo modelli Claude disponibili.
- Il router tiene conto del costo: con l'abbonamento preferisce modelli efficienti (Haiku/Sonnet) per le richieste semplici, per non consumare il credito.

---

## 3. L'orb (cuore visivo)

**Rendering**
- Shader Metal a raymarching su funzioni SDF, colore base arancione Claude `#D97757` con highlight `#FFB089`, fresnel sul bordo, bande interne animate, riflesso speculare, glow esterno, tone mapping morbido.
- Vive in un `NSPanel` senza bordi, trasparente, sempre in primo piano, trascinabile, con dimensione regolabile. Si richiama con hotkey o wake word.
- 60 fps stabili su Apple Silicon; con "Riduci movimento" attivo le animazioni rallentano.

**Stati** (transizioni sempre interpolate, mai a scatti)

| Stato | Comportamento |
|---|---|
| Riposo | respira lentamente |
| Ascolto | si deforma seguendo il volume reale del microfono |
| Pensiero | vortice interno, rumore più rapido |
| Parla | pulsa sincronizzato con l'ampiezza dell'audio TTS |
| Lavora | punte e filamenti, si collega alla vista galassia |

**Morph in oggetti 3D**
- 12 campi, ognuno con **1.000 varianti** generate da un seed deterministico (stesso seed = stessa forma): Codice (cubo scavato e ritorto), Meteo (nuvola con gocce), Musica (anello a onda), Tempo (orologio con lancette vive), Mail (busta), Ricerca (lente), Creativo (stella a petali), Finanza (pila di monete), Salute (cuore che pulsa), Viaggi (diamante bussola), Chat (fumetto), Agente (ingranaggio).
- Il seed controlla torsione, proporzioni, numero di elementi, dettagli opzionali e rotazione.
- Il passaggio tra due forme è un blend delle due SDF con easing, circa 1,1 s.
- Dopo la risposta l'oggetto resta qualche secondo, poi torna orb.
- Estensione futura: caricare modelli USDZ e generare oggetti con un servizio text-to-3D.

**Colore per modello**: quando il router sceglie un modello, l'orb sfuma verso la tinta e la texture di quel fornitore.

---

## 4. Router dei modelli

- Accesso a centinaia di modelli tramite **OpenRouter**, più l'API Anthropic diretta.
- Un classificatore veloce (Claude Haiku 4.5) legge ogni richiesta e restituisce in JSON: modello, campo della forma, motivazione breve, stima di latenza e costo.
- Regole di base:
  - codice, repo, azioni su file → **Claude Opus 5.5 via Agent SDK**
  - richiesta semplice o veloce → modello piccolo ed economico
  - immagini e video → modello multimodale forte
  - ricerca di notizie aggiornate → modello con web e fonti
  - scrittura creativa lunga → modello top per la scrittura
  - default → Claude Sonnet 5.5
- I modelli non Claude rispondono in chat; il lavoro agentico resta a Claude.
- L'utente può forzare la scelta a voce o a testo ("usa Opus").
- Animazione di scelta: un anello 3D di nomi di modelli ruota intorno all'orb, accelera, poi si ferma sul modello scelto, che si illumina.
- Pannello router: modello, fornitore, motore (Agent SDK o Gateway), motivazione, latenza, costo a 5 livelli, ultime 4 richieste.

---

## 5. Voce

| Funzione | Predefinito (locale) | Opzione alta qualità |
|---|---|---|
| Wake word "Hey Bubo" | openWakeWord o Porcupine | — |
| Voce → testo | SpeechAnalyzer di Apple o WhisperKit, in streaming | Deepgram / Whisper API |
| Testo → voce | AVSpeechSynthesizer con voci Premium | ElevenLabs in streaming |

- Flusso: wake word → trascrizione in streaming → router → risposta in streaming → TTS frase per frase. Obiettivo: prima parola parlata in meno di 1 s.
- Interruzione: se l'utente parla sopra, Bubo si ferma e ascolta.
- Sottotitoli sotto l'orb, con il nome di chi parla.
- Push-to-talk con tasto, oltre alla wake word.

---

## 6. Secondo cervello con Obsidian (opzionale)

Un vault è una cartella di Markdown: Bubo ci lavora direttamente.

- **Onboarding**: scegli un vault esistente o creane uno con struttura pronta (Inbox, Progetti, Aree, Risorse, Archivio, Daily). Scrive `BUBO.md` con le convenzioni dell'utente (cartelle, tag, stile dei titoli), letto a ogni sessione.
- **Cattura veloce** a voce o testo: nota in Inbox, già collegata a persone e progetti con `[[ ]]`.
- **Daily note automatica** ogni mattina: agenda, task aperti, cose rimaste da ieri.
- **Link automatici** suggeriti mentre si scrive.
- **Riordino dell'Inbox** giornaliero: Bubo propone spostamenti e tag, l'utente approva con un tocco.
- **Domande al vault**: ricerca semantica con embedding locali, risposte con citazione delle note.
- **Revisione settimanale**: riassunto, idee dimenticate, progetti fermi.
- **Grafo 3D del vault** nella vista galassia: le note si accendono quando Bubo le legge o le scrive.
- Apertura delle note in Obsidian via `obsidian://`; se presente il plugin Local REST API, inserimento nella nota aperta.
- Tutto disattivabile. Nessuna modifica distruttiva senza conferma.

---

## 7. Integrazione con macOS (priorità alta: deve essere comodissimo)

| Punto di accesso | Implementazione | Azioni |
|---|---|---|
| Tasto destro nel Finder | Finder Sync Extension | Apri con Bubo, Chiedi a Bubo su questi file, Riassumi, Aggiungi al secondo cervello |
| Apri con… | Cartelle e file come tipi supportati nell'Info.plist | Bubo in "Apri con", cartelle trascinabili sull'icona del Dock |
| Testo selezionato ovunque | macOS Services | Chiedi a Bubo, Salva nel secondo cervello |
| Condividi | Share Extension | Bubo nel foglio di condivisione |
| Scorciatoia globale | Hotkey (default ⌥ Spazio) | fa comparire l'orb ovunque |
| Barra dei menu | Icona con orb in miniatura | stato, ultime attività, azioni rapide |
| Comandi rapidi, Spotlight, Siri | App Intents | Chiedi a Bubo, Nuova nota, Apri progetto |
| Trascina sull'orb | Drag and drop | file, cartelle, immagini, link nel contesto |
| Link | Schema URL `bubo://` | apertura di sessioni e azioni da altre app |

"Apri con Bubo" su una cartella avvia una sessione con quella cartella come progetto. Se contiene `CLAUDE.md` o una memoria di Bubo, riparte da lì.

---

## 8. Vista galassia 3D

- Il progetto aperto è una galassia: cartelle come cluster, file come nodi.
- Nodi blu quando l'agente legge, arancioni quando modifica.
- Gli agenti e i subagent sono entità visibili che si spostano tra i file.
- Permessi e diff appaiono come pannelli in vetro che emergono dal nodo toccato.
- Timeline per riavvolgere la sessione.
- Stessa vista per il vault di Obsidian.

---

## 9. Design (premium)

- Scuro, caldo, stile HUD: fondo grafite calda `#0C0A09`, pannelli in vetro con blur, filetti sottili `rgba(255,206,180,.11)`, testo `#F4EBE4`, secondario `#9B8A80`, accento `#D97757` / `#FFB089`.
- Anelli HUD attorno all'orb: cerchio tratteggiato e tacche che ruotano lentamente in versi opposti.
- Tipografia: display largo e leggero per il marchio (spaziatura ampia), sans pulito per il testo, monospace per dati e etichette.
- Micro-interazioni curate: hover, pressione dei pulsanti, focus visibile, transizioni con easing.
- Aptica del trackpad, suoni discreti opzionali.
- Accessibilità: VoiceOver sui controlli, contrasto adeguato, Riduci movimento rispettato.

---

## 10. Posizionamento rispetto ai concorrenti

Concorrenti: l'app desktop ufficiale di Claude Code (sessioni parallele, worktree, diff), Conductor, Nimbalyst (ex Crystal), opcode, Sculptor, Superset, CodeAgentSwarm. Quasi tutti sono Electron o Tauri con sidebar, kanban e diff.

Bubo si distingue per: **nativo vero** (SwiftUI + Metal), **interfaccia spaziale 3D** come esperienza principale, **voce** come input primario, **router multi-modello**, **secondo cervello** integrato e **presenza in tutto il sistema** (Finder, Services, hotkey, menu bar).

---

## 11. Fasi di lavoro

1. **Fondamenta**: progetto Xcode, struttura dei moduli, design tokens, impostazioni, account (login con abbonamento Claude tramite CLI/SDK ufficiale, API key nel Portachiavi, fallback).
2. **Orb**: overlay NSPanel, shader Metal con stati e morph dei 12 campi × 1.000 varianti, colore per modello.
3. **Agent bridge**: processo Node con Agent SDK, protocollo JSON, streaming nell'HUD, gestione permessi.
4. **Router + gateway**: classificatore, OpenRouter, anello dei modelli, pannello router.
5. **Voce**: wake word, trascrizione, TTS, interruzione, sottotitoli.
6. **Integrazione macOS**: Finder Sync, Apri con, Services, Share, App Intents, hotkey, menu bar, `bubo://`.
7. **Secondo cervello**: onboarding vault, cattura, daily note, riordino Inbox, ricerca semantica, revisione settimanale.
8. **Galassia 3D**: repo e vault, agenti visibili, diff in vetro, timeline.
9. **Rifinitura e distribuzione**: performance, accessibilità, firma, notarizzazione, DMG, aggiornamenti automatici (Sparkle).

---

## 12. Criteri di accettazione

- L'orb gira a 60 fps e ogni transizione di stato o forma è fluida.
- Da wake word a prima parola parlata: meno di 1 s su una richiesta semplice.
- Tasto destro su una cartella nel Finder → "Apri con Bubo" apre una sessione su quella cartella.
- Il router sceglie il modello e mostra il motivo; l'utente può forzarlo.
- Con Obsidian attivo: una frase detta a voce diventa una nota collegata nell'Inbox.
- Nessuna azione distruttiva (cancellare file, inviare messaggi, modifiche massive al vault) senza conferma esplicita.
- Nessuna chiave API in chiaro su disco o nei log.
- Un utente con solo abbonamento Claude (nessuna API key) completa l'onboarding e usa Bubo, incluso l'agente sul codice.
- Credito Agent SDK residuo visibile; a credito esaurito, messaggio chiaro e fallback funzionante.

---

## Come procedere

Parti dalla **fase 1**, poi la **fase 2**. Alla fine di ogni fase: build funzionante, breve riepilogo di cosa è stato fatto e cosa manca. Chiedimi conferma solo per decisioni difficili da annullare; per il resto scegli l'opzione più sensata e annotala.
