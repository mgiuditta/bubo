# 12 — Secondo cervello

Ticket: [#46](https://github.com/mgiuditta/bubo/issues/46) (ricerca), [#54](https://github.com/mgiuditta/bubo/issues/54) (decisioni), [#55](https://github.com/mgiuditta/bubo/issues/55) (Indice). Mappa: [#42](https://github.com/mgiuditta/bubo/issues/42).

In sintesi: il Secondo cervello è una cartella Markdown qualunque dell'utente; un vault Obsidian è solo il caso più comune. Bubo ci legge soltanto attraverso lo strumento `cerca` dell'Indice e ci scrive soltanto dentro `Bubo/`, direttamente su disco, senza plugin e con Obsidian anche chiuso.

## Ricerca

La ricerca è in [13-memoria.md](13-memoria.md), che copre insieme Memoria di Progetto e Secondo cervello:

- [Secondo cervello (feature 12)](13-memoria.md#secondo-cervello-feature-12): strumenti (Smart Connections, Copilot for Obsidian, Khoj, Obsidian URI, CLI, Local REST API, MCP per Obsidian, obsidian-skills) e convenzioni per scrivere note (proprietà, wikilink, cartella dedicata, riconoscere un vault, scrittura diretta su disco).
- [Come fanno i concorrenti](13-memoria.md#come-fanno-i-concorrenti): Copilot for Obsidian è l'unico che scrive un riassunto a fine chat in Markdown.
- [Rischi e casi limite](13-memoria.md#rischi-e-casi-limite): note dell'utente, nomi di file, cartella di Bubo nella ricerca, iCloud e sync.

L'Indice (modello, archivio, aggiornamento, limiti) è in [indice-semantico.md](indice-semantico.md).

Punti che decidono la forma della feature:

1. **Scrittura diretta su disco** è l'unica via che funziona con Obsidian chiuso e con qualunque cartella Markdown (Logseq, iA Writer, cartella qualsiasi). URI, CLI e Local REST API chiedono l'app aperta, la CLI anche una password di amministratore.
2. **Proprietà di Obsidian** = frontmatter YAML; date `AAAA-MM-GG`; link nelle proprietà tra virgolette (`"[[Nota]]"`).
3. **Cartella dedicata** esclusa dalla propria ricerca, come fa Copilot con `copilot/`, altrimenti l'Indice risponde con se stesso.
4. **L'indice non va nel vault**: Smart Connections mette `.smart-env/` nel vault e deve escluderlo da git e dalla sincronizzazione. L'Indice di Bubo sta in Application Support.
5. **Obsidian rinomina i link solo se rinomina lui**: Bubo non rinomina né sposta note.

## Mappa

Architettura comune in [INDEX.md](INDEX.md). Dipende dall'Indice ([indice-semantico.md](indice-semantico.md)); il Riassunto di Sessione che scrive qui è specificato in [13-memoria.md](13-memoria.md#riassunto-di-sessione).

- **Cosa è**: una cartella scelta dall'utente. Nessun Progetto la possiede. Obsidian è un extra: niente plugin, niente API di Obsidian.
- **Scelta della cartella**: nelle impostazioni, oppure al primo Riassunto di Sessione o al primo "Ricordati questo" in una Domanda. Per proporre i vault Obsidian si legge `~/Library/Application Support/obsidian/obsidian.json` (file interno, solo per suggerire) e si riconosce `.obsidian/` nella radice; si accetta qualunque cartella. Se l'utente rifiuta, non si scrive nessuna nota.
- **Configurazione guidata** ([#554](https://github.com/mgiuditta/bubo/issues/554)): in Impostazioni › Generale, tre passi saltabili, uno per schermata: quale cartella (vault di Obsidian rilevati, predefinito il primo), quali cartelle in cima leggere (predefinito tutte), quali mettere prima (predefinito nessuna). Le risposte diventano il profilo salvato in locale (`SecondBrainLocation.excludedFolders` e `priorityFolders`), modificabile nelle sezioni Cartelle escluse e Cartelle prioritarie. In `cerca` le note delle cartelle prioritarie vengono prima delle altre, ciascun gruppo nel suo ordine.
- **Domanda di chiarimento**: se `cerca` trova note con lo stesso titolo a parte la data (per esempio due standup), la risposta dello strumento chiede al modello una sola domanda con quelle note come opzioni, mai due di seguito.
- **Lettura**: solo tramite lo strumento MCP interno `cerca` dell'Indice, quando il modello lo chiama. Nulla viene iniettato in automatico nel contesto. Ogni chiamata compare come riga "Richiamato" ([13-memoria.md](13-memoria.md#memoria-di-progetto)). I frammenti vanno solo a Claude o ai modelli locali; agli altri fornitori solo con consenso.
- **Cosa indicizza l'Indice qui**: `.md` e `.txt`; saltati `.obsidian/`, `.trash/`, cartelle nascoste, `Bubo/Sessioni/` e le cartelle escluse a mano ([indice-semantico.md](indice-semantico.md)).
- **Scrittura**: solo dentro `Bubo/` nella radice del Secondo cervello.
  - `Bubo/Sessioni/`: Riassunti di Sessione ([13-memoria.md](13-memoria.md#riassunto-di-sessione)).
  - `Bubo/Note/`: "Ricordati questo" detto in una Domanda. In una Sessione lo salva invece l'agente nella Memoria di Progetto.
  - `Bubo/Riunioni/`: le Riunioni registrate (#545), con proprietà `titolo`, `data`, `ora`, `durata`, `app`, `partecipanti`, `fonte: Riunione`, poi Riassunto, Decisioni, Azioni e Trascrizione con «Io» e «Altri». L'Indice le legge: sono fonti, non riassunti di Bubo. L'audio resta in `Application Support/Bubo/Riunioni/`, 30 giorni o fino alla trascrizione (Impostazioni › Generale).
- **Moduli**:
  - `SecondBrain/SecondBrainLocation`: cartella scelta, bookmark, suggerimento dei vault, raggiungibilità.
  - `SecondBrain/NoteWriter`: unico scrittore su disco. Scrive solo sotto `Bubo/`, nomi senza `/ : * ? " < > |`, frontmatter valido per Obsidian, scrittura atomica, hash della versione scritta per riconoscere le modifiche a mano.
  - `Index/` e lo strumento `cerca`: da [indice-semantico.md](indice-semantico.md).
- **Flusso**:
  1. Scelta della cartella → l'Indice la osserva con FSEvents e la indicizza in background.
  2. Turno di Claude → il modello chiama `cerca` → frammenti con percorso → riga "Richiamato" con Apri (apre la nota nell'app predefinita per `.md`).
  3. Risposta con citazioni ([#546](https://github.com/mgiuditta/bubo/issues/546)): `cerca` dà a ogni nota la sua citazione, `[[percorso senza .md]]`, e chiede al modello di metterla dopo ogni affermazione che ne viene (per una Riunione col minuto, `[[…#12:40]]`); con 0 risultati il modello dice che nel Secondo cervello non c'è niente. Nella risposta della Domanda (HUD e bolla del Panel) le citazioni diventano link: aprono la nota in Obsidian (`obsidian://open?path=`) se la cartella è un vault e Obsidian è sul Mac, altrimenti in Quick Look.
  4. "Ricordati questo" in una Domanda → `NoteWriter` → `Bubo/Note/AAAA-MM-GG Titolo.md` → nota trovabile con `cerca` entro 5 s.
- **Casi limite**:
  - Cartella in iCloud Drive non scaricata o disco esterno scollegato: `NoteWriter` non scrive, avviso; l'Indice mantiene l'ultima copia.
  - Obsidian Sync o iCloud che portano modifiche da un altro Mac: FSEvents le vede come modifiche esterne.
  - Nota di Bubo modificata a mano: mai sovrascritta (regola dell'hash in [13-memoria.md](13-memoria.md#riassunto-di-sessione)).
  - Utente che sposta o rinomina `Bubo/`: al prossimo scritto Bubo ricrea `Bubo/` e non cerca la vecchia.
  - Vault con link Markdown invece di wikilink: le proprietà usano comunque `"[[…]]"`, che Obsidian risolve in entrambe le modalità.
  - Cartella molto grande: oltre 100.000 frammenti l'Indice avvisa e propone esclusioni ([indice-semantico.md](indice-semantico.md)).
- **Test**:
  - Monitor su tutta la cartella durante un giorno d'uso: 0 file creati, modificati o spostati fuori da `Bubo/`.
  - Nota scritta da Bubo aperta in Obsidian: 0 errori sulle proprietà; stessa nota leggibile in un editor Markdown qualsiasi.
  - Obsidian chiuso: riassunto e "Ricordati questo" scritti lo stesso.
  - Nota salvata in `Bubo/Note/` → trovata da `cerca` entro 5 s.
  - Domanda che non chiama `cerca`: 0 frammenti del Secondo cervello nel contesto.

## Specifica "migliore di"

Miglior concorrente: **Copilot for Obsidian** (chat sul vault e riassunto di fine chat in Markdown), che però vive dentro Obsidian aperto, mette la sua cartella nel vault e richiede il plugin; Smart Connections e Khoj vogliono un plugin o un server.
Bubo lo supera così:

1. **Qualunque cartella Markdown**, Obsidian chiuso compreso: **0 plugin**, **0 API** di Obsidian richieste.
2. **Rispetto delle note**: **0 note** dell'utente create, modificate o spostate fuori da `Bubo/`; **0 sovrascritture** di note di Bubo modificate a mano.
3. **Note valide**: frontmatter letto da Obsidian **senza errori**.
4. **Trovabile**: nota salvata trovabile con `cerca` **entro 5 s**; Recall@1 **≥ 0,80** sul set fisso italiano dell'Indice.
5. **Locale e senza iniezioni**: indice fuori dal vault, **0 byte** del Secondo cervello a fornitori diversi da Claude o dai modelli locali senza consenso; **0 frammenti** nel contesto se il modello non chiama `cerca`.

## Fonti

Fonti della ricerca in [13-memoria.md](13-memoria.md#fonti) (numeri 12, 13, 15, 17–26 per il Secondo cervello) e in [indice-semantico.md](indice-semantico.md#fonti).
