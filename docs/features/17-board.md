# 17 — Board delle Sessioni

Ticket: [#126](https://github.com/mgiuditta/bubo/issues/126) (ricerca), [#132](https://github.com/mgiuditta/bubo/issues/132) (prototipo: colonne, Bozze, gesti), [#134](https://github.com/mgiuditta/bubo/issues/134) (Bozze da issue, Apri PR), [#135](https://github.com/mgiuditta/bubo/issues/135) (costi), [#136](https://github.com/mgiuditta/bubo/issues/136) (Automazioni), [#140](https://github.com/mgiuditta/bubo/issues/140) (scorciatoie). Mappa: [#125](https://github.com/mgiuditta/bubo/issues/125).
Ricerca del 2026-09-30 su Superset (board Workspaces del 2026-08-16), Vibe Kanban classico ≤ v0.1.8 e cloud ≥ v0.1.9, Cline Kanban (anteprima), Conductor fino a 0.85.0, Claude Code agent view e Progetti (beta).

In sintesi: esistono tre tipi di board.
- **Derivate:** le colonne si calcolano dallo stato dell'agente e della PR, e non si trascina niente. Sono la strada presa da Claude (Progetti e agent view), Superset e Cursor.
- **Da tracker:** le colonne sono uno stato che l'utente trascina, e trascinare cambia solo l'etichetta. Sono Vibe Kanban, i Tasks di Superset e la kanban di Nimbalyst.
- **Ad azioni:** trascinare fa partire l'agente o pulisce il worktree. È Cline Kanban.

Le lamentele più frequenti vengono dalle board con trascinamento: lo stato trascinato si stacca da quello vero. Dove le colonne si derivano, la colonna più importante è sempre **"attende te"**, che per Bubo è un'**Attività**, non una **Fase**. Bubo sceglie la board derivata: sei colonne calcolate da Fase e Attività con una regola a precedenza fissa (Da iniziare, Attende te, Lavora, Da guardare, PR aperta, Fusa). Le card delle Sessioni non si trascinano. L'unico trascinamento con effetto è **Bozza → Avvia**, che fa anche ↩. La Board è la quarta **Vista delle Sessioni** (⌘4). Il "3D" richiesto all'inizio è già la Vista Orbita ed è fuori portata.

## Ricerca

### Come dispongono le sessioni i concorrenti

| Prodotto | Colonne | Chi le muove | Da compito a sessione | Card |
|---|---|---|---|---|
| **Claude, Progetti → Overview** (beta) | Ready for review (PR aperta), Waiting on you (risposta, approvazione, errore), Working, Landing (PR approvata o in coda di merge), Idle, Resolved [1] | **Automatiche.** Resolved la mette l'utente, Claude dopo il merge, o il tempo dopo una settimana di inattività; si può riaprire [1] | Si scrive un messaggio e Claude lo manda a un thread nuovo o esistente. Più compiti in un messaggio diventano thread separati. "Suggested threads": una freccia li avvia uno alla volta, un pulsante tutti insieme [1] | Pulsanti del passo successivo che scrivono al thread: Resolve conflicts, Fix CI, Address comments, Merge it [1] |
| **Claude Code, agent view** (`claude agents`) | Pinned, Ready for review (PR aperta), Needs input, Working, Completed (finite, fallite, fermate) [2] | **Automatiche.** Si riordina a mano con `Shift+↑/↓`, si fissa con `Ctrl+T`; niente mouse [2] | Prompt in basso + Invio [2] | Icona di stato, nome, riassunto di una riga da Haiku, età, `#PR`. Completed si piega in "… N more", ma fallite e PR aperte restano visibili. Filtri `s:<stato>`, `a:<agente>`, `#PR`; `Ctrl+S` raggruppa per cartella [2] |
| **Claude Desktop, scheda Code** | Nessuna board: barra laterale filtrata per stato, Progetto, ambiente [3] | — | `⌘N` | Diff `+12 -1`, barra della CI dopo la PR con Auto-fix e Auto-merge, archiviazione automatica a PR fusa o chiusa [3] |
| **Superset, Workspaces** (board dal 2026-08-16) | Needs attention, Working, Needs review, Idle, Merged, Deleted. Merged e Deleted "sono storia" e spariscono se vuote [4][5] | **Automatiche**: `deriveBoardColumn` prende la prima regola che vale (archiviato → PR fusa → permesso o errore → lavora → PR aperta → revisione). L'ordine è fisso, "mai riordinabile"; nessun trascinamento [6] | — (vedi Tasks) | Branch, Progetto, PR, ahead/behind, diff, avanzamento dei check, ultima attività; al passaggio revisione, CI, anteprima. Filtri Progetto, stato della PR, agente, fissati, dispositivo [5] |
| **Superset, Tasks** | Kanban o tabella per stato; fonti: compiti nativi, Linear, GitHub Issues [7] | **A mano** (dnd-kit): lasciare una card chiama solo `updateStatus` [8] | "Run in workspace": si sceglie Progetto e agente, nasce un workspace per compito. L'interruttore "Auto-run" decide se l'agente parte subito; il prompt viene da un modello [7] | — |
| **Nimbalyst, Session kanban** | "Senza fase", Backlog, Planning, Implementing, Validating, Complete [9] | **Agente o utente.** L'agente con lo strumento MCP `update_session_meta`, l'utente trascinando. La fase è tenuta separata dallo stato operativo (idle, running, waiting_for_input) [9] | — | Badge dello stato (running, needs input, review, idle, done), fino a 4 tag, file non committati, tempo dall'ultimo aggiornamento, anteprima della trascrizione. Tastiera: frecce, `Invio`, `Spazio`, `⌘→/←` per la fase successiva o precedente, selezione multipla [10] |
| **Vibe Kanban** (classico, ≤ v0.1.8) | To do, In Progress, In Review, Done, Cancelled [11] | **Automatiche**: avvio → In Progress; tentativo finito, riuscito o no → In Review; merge o PR fusa (controllo ogni 60 s) → Done. "Puoi trascinare, ma non attiva nessuna funzione" [12] | "Create & Start", oppure **+** sul compito con agente, variante e branch di base. Un compito ha più **tentativi**, ognuno una sessione con il suo worktree [12][13] | Merge e Create PR nell'intestazione del diff, con commit ahead e behind [14] |
| **Vibe Kanban** (cloud, ≥ v0.1.9) | To do, In progress, In review, Done; Backlog e Cancelled come schede; colonne personalizzabili [15] | **A mano**, sincronizzate con il team, vince l'ultima scrittura [15] | Dal pannello dell'issue, sezione Workspaces: **+**; la descrizione diventa il prompt [16] | ID, titolo, priorità, assegnatari, tag. Tastiera `X`, `Shift+J/K`, `⌘K`. I limiti WIP sono solo un consiglio della doc [15] |
| **Cline Kanban** (anteprima) | Backlog, In Progress, Review, Done (internamente `trash`) [17] | **Il trascinamento fa cose.** Backlog → In Progress **avvia l'agente** in un worktree effimero; → Done pulisce il worktree e conserva l'id di ripresa. In Progress ↔ Review solo dall'app; da Done si torna solo a Review [18][19] | Trascinare in In Progress oppure ▶ sulla card. Le card si collegano con ⌘+clic: finita una, partono le collegate [20] | Ultimo messaggio o strumento dell'agente (da hook); commit e PR automatici a scelta [20] |
| **Conductor** | Nessuna board. Barra laterale raggruppata per stato: backlog, in progress, in review, done (0.35.0); per repo (0.35.2); sezioni personali (0.85.0) [21][22][23] | Non documentato (da verificare) | `⌘N` con Dispatcher e "create more" (0.63.0); "Create from…" issue Linear o GitHub `⌘I` (0.66.0) [24][25] | Stato GitHub (fusa, CI fallita, conflitti) (0.44.0) [26] |
| **Cursor, Agents Window** | "Group by status": Draft, Running, Needs attention, Done [27] | Automatiche (dal forum ufficiale, da verificare) | — | Richiesta di una griglia visiva colorata per stato [28] |
| **Warp, Agent Management** | Lista filtrabile: Working, Blocked, Canceled, Failed, Success [29] | Automatiche | — | Filtri per origine (interattivo, API, CLI, Slack/Linear, programmato), data, autore, stato [29] |
| **Linear** (riferimento) | La board è quella delle issue [30] | L'agente sposta l'issue "al primo stato `started` quando inizia" [31] | Si assegna l'issue all'agente; la persona assegnataria resta responsabile [30]. Stati della sessione dell'agente: pending, active, error, awaitingInput, complete, stale [32] | — |
| **Codex app, GitHub Copilot, opcode, Raycast, Sculptor, Devin** | Nessuna board trovata. Codex ordina per Progetto con fissa e archivia [33]; Copilot parte da un'issue assegnata e ha una lista di sessioni [34] | — | — | — |

**Cosa ne esce.**

1. **Le colonne si derivano, non si trascinano.** Claude, Superset e Cursor calcolano la colonna dallo stato dell'agente e della PR. Superset lo scrive nel codice: la board "percorre gli stessi gruppi della lista, così le due viste non possono mai essere in disaccordo" [4].
2. **"Attende te" è la prima colonna.** È sempre un'Attività (permesso, domanda, errore), non una tappa della vita della sessione. Gli errori ci finiscono dentro: Claude li mette in "Waiting on you", Superset in "Needs attention", e agent view non li piega mai.
3. **Le colonne finali seguono la PR.** "Ready for review" vuol dire PR aperta in Claude e in Superset. Claude aggiunge "Landing" (approvata o in coda di merge). Nella nostra lingua sono **In revisione** e **Fusa**.
4. **Da compito a sessione con un pulsante.** Vibe ("Create & Start", **+**), Superset ("Run in workspace" con Auto-run), Conductor (`⌘I` da issue), Claude ("Suggested threads"). Solo Cline usa il trascinamento come azione, e per farlo deve vietare le mosse insensate.
5. **Nessun concorrente ha limiti WIP.** Gli utenti li chiedono. Contro l'eccesso di card si usano la piegatura ("… N more"), le colonne che si nascondono, i filtri per Progetto, stato e agente.

### Cosa chiedono e lamentano gli utenti

- **Stato trascinato che mente.** In Vibe Kanban lo stato salta tra In Progress e In Review a ogni messaggio [#1702](https://github.com/BloopAI/vibe-kanban/issues/1702). Un compito resta "in progress" se l'agente non committa [#1234](https://github.com/BloopAI/vibe-kanban/issues/1234). Archiviare nella lista non aggiorna la board [#2109](https://github.com/BloopAI/vibe-kanban/issues/2109). In Cline la sessione è in `awaiting_review` ma la card resta in In Progress, e l'automazione della revisione si ferma [#224](https://github.com/cline/kanban/issues/224). Dopo un riavvio le sessioni non tornano nelle colonne [#411](https://github.com/cline/kanban/issues/411). In Superset "Needs review" è sempre vuota per il checkout principale, mentre il pallino della barra laterale dice altro [#7126](https://github.com/superset-sh/superset/issues/7126). Una chat risulta idle con i subagent ancora al lavoro [#7395](https://github.com/superset-sh/superset/issues/7395).
- **Gli errori non sono "fatto".** In Cline i compiti falliti finiscono in Done: si chiede Review con un banner d'errore [#524](https://github.com/cline/kanban/issues/524). Una card fallita non si può riportare nel Backlog [#65](https://github.com/cline/kanban/issues/65). Done colorato di rosso sembra un errore [#445](https://github.com/cline/kanban/issues/445).
- **Due tipi di revisione.** Si chiede di separare "l'agente ha finito, guarda tu in locale" da "PR in attesa di code review" [#879](https://github.com/BloopAI/vibe-kanban/issues/879), [#1945](https://github.com/BloopAI/vibe-kanban/issues/1945).
- **Board locale e personale.** Il passaggio di Vibe Kanban a una board cloud con login ha causato la reazione più forte ("il motivo per cui usavo questo progetto se ne va") [#2687](https://github.com/BloopAI/vibe-kanban/issues/2687), [#3444](https://github.com/BloopAI/vibe-kanban/issues/3444), [#2509](https://github.com/BloopAI/vibe-kanban/issues/2509). La nuova UI chiede due passi dove bastava un trascinamento [#2730](https://github.com/BloopAI/vibe-kanban/issues/2730). Vibe Kanban ha poi annunciato la chiusura dei servizi remoti (2026-04-10): resta open source della comunità [35].
- **Una board per tutti i Progetti.** Colorata o etichettata per Progetto: [#2021](https://github.com/BloopAI/vibe-kanban/issues/2021), [#1106](https://github.com/BloopAI/vibe-kanban/issues/1106), [#2343](https://github.com/BloopAI/vibe-kanban/issues/2343). Raggruppare per Progetto: Nimbalyst [#619](https://github.com/nimbalyst/nimbalyst/issues/619).
- **Limiti WIP.** Gli agenti dovrebbero prendere dal To do da soli, ma fermarsi a 4 card in revisione [#1833](https://github.com/BloopAI/vibe-kanban/issues/1833).
- **Card che dicono abbastanza.** La lista ordinata per ultima attività rimescola tutto e le righe dicono troppo poco: si chiede la vista per stato in barra laterale [#7364](https://github.com/superset-sh/superset/issues/7364). Check della PR sulle icone [#7805](https://github.com/superset-sh/superset/issues/7805). Una kanban delle sessioni slegata da Linear [#1926](https://github.com/superset-sh/superset/issues/1926).
- **Colonne su misura.** Backlog, Planning, Implementing, Validating e Complete non vanno bene per il lavoro che non è codice [#82](https://github.com/nimbalyst/nimbalyst/issues/82).

## Il meglio da battere

I riferimenti sono **Superset Workspaces** per le colonne derivate, mai in disaccordo con la lista, e **Claude Progetti** per i pulsanti del passo successivo. Nessuno dei due unisce la board delle sessioni e quella dei compiti. Nessuno avvia un compito senza cambiare vista, e nessuno approva una Richiesta dalla card. Criteri candidati (quelli definitivi sono nella Specifica):

1. **0 disaccordi con la verità.** La colonna di ogni Sessione si calcola dalla Fase e dall'Attività registrate, mai da un'etichetta trascinata. Board, Colonna, Orbita e Striscia mostrano la stessa cosa, e un test lo verifica sugli stessi eventi.
2. **Attende te sempre in vista.** Le Sessioni in Attende te o in Errore stanno in alto, ordinate per tempo di attesa. Alla Richiesta di permesso si risponde dalla card (↩ Solo ora, esc No), come nelle altre Viste.
3. **Un solo gesto dal compito alla Sessione.** Un pulsante, oppure il trascinamento da "da iniziare", avvia la Sessione nel suo worktree con il testo del compito come prompt. Merge e archiviazione restano azioni esplicite.
4. **Il fallimento non sparisce.** Una Sessione in Errore non va mai da sola in Fusa o in Archiviata.
5. **Card che bastano.** Titolo, riassunto di una riga, Progetto · branch, diff, PR con i check, tempo dall'ultima attività; le finite si piegano.
6. **Locale e personale.** Nessun login né servizio per la Board.

## Rischi e casi limite

- **Colonne solo per Fase.** Le Fasi di Bubo sono Aperta, In revisione, Fusa e Archiviata. Con colonne solo per Fase, quasi tutto il lavoro vivo finirebbe in **Aperta**, mescolando Lavora, Attende te ed Errore: si perderebbe proprio la distinzione che tutti i concorrenti mettono in cima. È il motivo per cui il prototipo scarta la variante A ([#132](https://github.com/mgiuditta/bubo/issues/132)).
- **Trascinare per cambiare Fase.** Trascinare in Fusa vorrebbe dire fare il merge; in Archiviata, rimuovere il worktree. Sono azioni con effetti, difficili da annullare ([02](02-diff-merge.md), [01](01-sessioni-worktree.md)). Cline le permette e deve vietare le mosse insensate, e gli utenti se ne lamentano.
- **Fase trascinata contro Fase vera.** Se la Fase si potesse spostare a mano senza un'azione, la Board mentirebbe, come in Vibe e in Cline. La Fase deve venire dagli eventi (PR aperta, merge, archiviazione), come in `deriveBoardColumn`.
- **Due stati "In revisione".** "L'agente ha finito, guarda il diff" non è "PR aperta in attesa di revisione". Bubo ha già la revisione del diff in app ([02](02-diff-merge.md)).
- **Compiti da iniziare e issue.** Superset tiene due board separate, Workspaces derivata e Tasks trascinabile, con Linear e GitHub come fonti. Conductor crea da issue con `⌘I`. Nei concorrenti sono fonti affiancate che confluiscono nello stesso pulsante di avvio.
- **Avvio in massa.** "Avvia tutti" (Suggested threads di Claude) su dieci compiti apre dieci worktree e consuma Quota in parallelo ([03](03-account-uso.md)).
- **Riavvio di Bubo.** Le card devono tornare nella colonna giusta dagli eventi salvati, non da uno stato in memoria (Cline [#411](https://github.com/cline/kanban/issues/411)).
- **Checkout principale.** La Sessione sul checkout principale non ha una PR sua: non deve sparire dalle colonne di revisione (Superset [#7126](https://github.com/superset-sh/superset/issues/7126)).

## Mappa

Architettura comune in [INDEX.md](INDEX.md). Si appoggia su Sessioni, Fase e worktree ([01](01-sessioni-worktree.md)), revisione e merge ([02](02-diff-merge.md)), Richiesta di permesso ([05](05-permessi.md)), Attività e Viste ([06](06-stato-sessioni.md)). Per le Bozze da issue e la PR si appoggia su GitHub e Linear (16, [#134](https://github.com/mgiuditta/bubo/issues/134)), per i risultati delle Automazioni sulla 19 ([#136](https://github.com/mgiuditta/bubo/issues/136)). Prototipo usa-e-getta: `prototypes/board-sessioni.html` sul branch `prototype/board-sessioni`, variante C.

### Dove vive (deciso)

- **Quarta Vista delle Sessioni** nell'HUD, accanto a Colonna, Orbita e Striscia. Stessi dati e stesse azioni delle altre Viste; cambiano solo la disposizione e le Bozze, che si vedono solo qui.
- Si sceglie in Impostazioni → Aspetto ([06](06-stato-sessioni.md)) oppure con **⌘1 / ⌘2 / ⌘3 / ⌘4** (Colonna / Orbita / Striscia / Board), solo con Bubo in primo piano ([#140](https://github.com/mgiuditta/bubo/issues/140)). Le scorciatoie compaiono nel menu e nella Palette (⌘K).
- **Una Board per tutti i Progetti**, con filtri a chip per Progetto ("Tutti i Progetti" di default) e per fonte delle Bozze (Ogni fonte, Bozze, GitHub, Linear).
- Nessun login e nessun servizio: la Board è locale e personale.

### Colonne e regola (deciso)

Sei colonne, da sinistra: **Da iniziare | Attende te | Lavora | Da guardare | PR aperta | Fusa**. Ogni Sessione sta in **una sola** colonna, calcolata dalla Fase e dall'Attività registrate, mai da un'etichetta trascinata. Vince la prima regola che vale:

1. Archiviata → fuori dalla Board (la si trova in Cronologia). Eccezione: vedi regola 2.
2. Fusa → **Fusa**. Dopo il merge, [01](01-sessioni-worktree.md) e [#134](https://github.com/mgiuditta/bubo/issues/134) archiviano la Sessione da soli (worktree rimosso, branch cancellato). La Board la tiene comunque in Fusa per **24 h** dal merge e poi la toglie. Senza questa finestra la colonna resterebbe sempre vuota.
3. Attività Attende te **o Errore** → **Attende te**.
4. Attività Lavora → **Lavora**.
5. In revisione con PR aperta → **PR aperta**.
6. Tutto il resto (Ferma in Aperta, In revisione senza PR) → **Da guardare**: l'agente ha finito e c'è un diff da guardare.

**Da iniziare** contiene solo Bozze, mai Sessioni.

Conseguenze:
- I due significati di "In revisione" si separano: Da guardare (diff in app, [02](02-diff-merge.md)) e PR aperta (code review su GitHub).
- Una Sessione in Errore sta in Attende te e non finisce mai da sola in Fusa.
- La Sessione sul checkout principale, che non ha PR, resta in Da guardare.
- PR chiusa senza merge → Aperta · Ferma con nota ([#134](https://github.com/mgiuditta/bubo/issues/134)) → Da guardare.
- Esecuzione di un'Automazione finita → Da guardare, con notifica ([#136](https://github.com/mgiuditta/bubo/issues/136)). Un'Esecuzione Senza modifiche si archivia da sola ed esce dalla Board.

**Ordine dentro la colonna.** Attende te: attesa più lunga in cima. Le altre: ultima attività più recente in cima. **Piegatura**: in Fusa oltre 2 card si piegano in "… N altre", apribili. Le altre colonne non si piegano.

### Card (deciso)

- **Sessione**: pallino dell'Attività, titolo, tempo dall'ultimo cambio, riassunto di una riga ([06](06-stato-sessioni.md)), Progetto · branch, `+n −m`, tag della Fase (serve perché le colonne mescolano le Fasi), PR con numero e check. Riferimento dell'issue come etichetta (`#42`, `ENG-123`) quando la Sessione ne nasce ([#134](https://github.com/mgiuditta/bubo/issues/134)). Segno "Automazione" con nome e ora per le Esecuzioni ([#136](https://github.com/mgiuditta/bubo/issues/136)).
- **Nessun costo sulla card**: il totale della Sessione sta nella sua intestazione, a 0 clic ([#135](https://github.com/mgiuditta/bubo/issues/135)).
- **Richiesta di permesso inline**: comando visibile, **↩ Solo ora**, **esc No**, come nelle altre Viste. Le altre risposte (Per questa Sessione, Sempre in questo Progetto) si danno dentro la Sessione ([05](05-permessi.md)).
- **Azioni del passo successivo** (solo se la Sessione non è in Attende te):
  - Da guardare: **Apri PR** accanto a **Fondi…**, e **Archivia**. Apri PR apre il foglio con anteprima e l'azione "Crea PR" ([#134](https://github.com/mgiuditta/bubo/issues/134)); `gh` assente → Apri PR disattivato con il motivo.
  - PR aperta: **Aggiorna PR** se ci sono commit nuovi; **Correggi** se un check è fallito (manda il log all'agente come nuovo turno); Fondi… e Archivia.
  - Nessun Auto-fix né auto-merge.
- **Bozza**: fonte (Bozza, GitHub `#n`, Linear `ID`), titolo, Progetto, **Avvia ↩**, **Programma…** (crea un'Automazione dalla Bozza, [#136](https://github.com/mgiuditta/bubo/issues/136)).

### Bozze (deciso)

- **Bozza**: un lavoro da iniziare su un Progetto. Titolo e testo diventano il prompt. Vive solo nella colonna Da iniziare.
- **Nascita**:
  - a mano: **+ Nuova Bozza** in testa alla colonna, oppure **⌥⌘N** ([#140](https://github.com/mgiuditta/bubo/issues/140)), con Progetto, titolo e testo;
  - da un'issue GitHub con **⌘I** (solo le issue del repo del Progetto): ↩ avvia subito, ⌥↩ salva come Bozza ([#134](https://github.com/mgiuditta/bubo/issues/134));
  - da ingressi esterni (script "Open in coding tool" di Linear, link `bubo://`): **sempre e solo una Bozza**, mai una Sessione che lavora.
- **Niente doppioni**, con chiave (Progetto, fonte, id):
  - esiste già una Bozza → si apre quella;
  - esiste una Sessione non Archiviata → si apre la Sessione;
  - la Sessione è Archiviata o Fusa → si sceglie tra "Riprendi" e "Nuova Sessione".
- **Avvia**:
  - crea la Sessione nel suo worktree ([01](01-sessioni-worktree.md)); la Sessione parte sempre in **Aperta · Lavora** e la Bozza sparisce;
  - branch: `bubo/<slug>` per le Bozze scritte a mano; `bubo/42-<slug>` per GitHub; `bubo/<branchName di Linear senza prefisso utente>` per Linear;
  - per le issue, il contesto (titolo, corpo, commenti, label, URL) si legge **ad Avvia**, non quando nasce la Bozza. Entra come Allegato "scritto da altri", mai come istruzione. Le immagini restano link.
- **Niente "Avvia tutti" in v1**: dieci worktree e dieci consumi di Quota in parallelo.
- **Filtri**: Progetto e fonte.

### Gesti (deciso)

- **L'unico trascinamento è Bozza → area delle Sessioni = Avvia.** Qualunque colonna si scelga, la Sessione parte in Aperta · Lavora. Se la Bozza viene lasciata fuori da Lavora o da Attende te, un avviso lo spiega.
- **Le card delle Sessioni non si trascinano.** La Fase cambia solo con un'azione: merge, PR, archiviazione.
- **Fondi…** chiede conferma e scrive l'azione per intero ("Unisce `<branch>` in `<branch di partenza>`; non si annulla dalla Board"). La conferma si dà con ↩, esc annulla. **Archivia** è un pulsante: worktree rimosso, branch tenuto ([01](01-sessioni-worktree.md)).
- **Tastiera**: ↩ su una Bozza la avvia; ↩ / esc su una card con Richiesta rispondono Solo ora / No. Ogni azione dei pulsanti si raggiunge con il fuoco da tastiera e con VoiceOver: Avvia non dipende dal trascinamento.
- Scorciatoie: ⌘4 Board, ⌥⌘N Nuova Bozza, ⌘I Bozza da issue GitHub, ⌘N Nuova Sessione, ⌘K Palette ([#140](https://github.com/mgiuditta/bubo/issues/140)).

### Moduli

Architettura comune in [INDEX.md](INDEX.md).

- `Sessions/BoardColumn`: una funzione pura (Fase, Attività, PR, istante del merge, adesso) → colonna o nessuna. Contiene la regola a precedenza fissa e l'ordinamento dentro la colonna. Le altre Viste la usano per il raggruppamento, così non possono essere in disaccordo con la Board.
- `Sessions/DraftStore`: le Bozze (Progetto, fonte, id esterno, titolo, testo, creazione), persistite accanto a `Sessions/SessionStore` ([01](01-sessioni-worktree.md)). Gestisce la chiave anti-doppioni e **Avvia** (→ `WorktreeManager`, branch per fonte, Allegato dell'issue letto ad Avvia tramite 16).
- `HUD/SessionViews/BoardView`: le sei colonne, le card di Sessione e di Bozza, i chip dei filtri, il trascinamento solo per le Bozze, il foglio di conferma di Fondi…, la piegatura di Fusa. Si affianca alle Viste Colonna, Orbita e Striscia ([06](06-stato-sessioni.md)).
- Riuso: `Sessions/ActivityTracker` (06), la Richiesta inline di 05, merge e revisione di `Git/` (02), Apri PR, Aggiorna PR, Correggi e ⌘I da 16, segno Automazione da 19, `System/Intents` e la Palette per ⌘1–4 e ⌥⌘N (#140).

### Flusso

1. ⌘4 → `BoardView` legge Sessioni e Bozze → ogni Sessione passa da `BoardColumn` → sei colonne.
2. Evento del ponte (`session_state_changed`, `canUseTool`, `result`) → Attività aggiornata → `BoardColumn` → la card cambia colonna entro 1 s.
3. Bozza → ↩ o trascinamento → `DraftStore.avvia` → worktree e branch → Sessione Aperta · Lavora in colonna Lavora → Bozza rimossa.
4. Card in Da guardare → Apri PR → foglio → Crea PR → Fase In revisione con PR → colonna PR aperta. Oppure Fondi… → conferma → merge (02) → Fusa → dopo 24 h fuori dalla Board.

### Casi limite

- **Riavvio di Bubo**: le colonne si ricalcolano da Fase, Attività e PR persistite, mai da uno stato in memoria. Una Richiesta pendente al riavvio segue le regole di 06.
- **Errore**: resta in Attende te finché non si risolve o si archivia a mano; non entra mai da sola in Fusa.
- **Checkout principale**: niente PR, niente worktree da rimuovere; resta in Lavora, Attende te o Da guardare, mai invisibile.
- **Colonne vuote**: restano visibili con il loro titolo, in ordine fisso, perché la posizione non cambi.
- **Bozza di un Progetto rimosso o non raggiungibile**: Avvia disattivato con il motivo; la Bozza resta.
- **`gh` assente o non autenticato**: ⌘I vuoto con spiegazione e Apri PR disattivato, entrambi con **Apri nel terminale**; Fondi… locale intatto ([#134](https://github.com/mgiuditta/bubo/issues/134)).
- **Stessa issue due volte** (⌘I e script Linear, o doppio clic su `bubo://`): la chiave (Progetto, fonte, id) apre la Bozza o la Sessione esistente.
- **Molte Sessioni**: Fusa piegata oltre 2; filtro per Progetto; Attende te mai piegata.
- **Riduci movimento**: niente animazioni di spostamento tra colonne, cambi diretti.
- **Budget esaurito su un'Automazione**: l'Esecuzione non parte e non compare sulla Board. La notifica "Saltata" e [Avvia ora] stanno nella 19.

### Test

- **Concordanza**: con Swift Testing, stesse sequenze di eventi registrati (quelle della macchina delle Attività di 06); `BoardColumn` e il raggruppamento della Vista Colonna danno lo stesso risultato per ogni Sessione.
- **Tavola della regola**: una riga per ogni combinazione Fase × Attività × PR (presente, assente, chiusa), con la colonna attesa. Casi dedicati: Errore con PR fusa → Attende te; checkout principale Ferma → Da guardare; Fusa da 25 h → fuori.
- **Riavvio**: si salva lo stato, si riavvia, si confrontano le colonne: 100% uguali.
- **Gesti**: trascinamento di una card di Sessione → nessun effetto; Bozza lasciata su qualunque colonna → Sessione Aperta · Lavora; Fondi… senza conferma → nessun merge.
- **Doppioni**: la stessa issue da ⌘I, da `bubo://` e dallo script Linear → una sola Bozza o Sessione.
- **Prestazioni**: 500 Sessioni e 100 Bozze sintetiche; tempo di `BoardColumn` su tutte, fotogrammi a 60 fps durante lo scorrimento, tempo di ⌘4.
- **Accessibilità**: audit SwiftUI della Board. Ogni card ha l'etichetta con Attività e Fase; Avvia, Fondi…, Archivia, Apri PR e la Richiesta si fanno senza mouse.

### Ordine di costruzione

1. **Board in sola lettura**: `BoardColumn`, `BoardView` con le cinque colonne delle Sessioni, card, Richiesta inline, ⌘4. Dipende da 01 (SessionStore), 06 (ActivityTracker, Vista Colonna) e 05 (Richiesta inline).
2. **Bozze scritte a mano**: `DraftStore`, + Nuova Bozza e ⌥⌘N, Avvia con ↩ e con il trascinamento, colonna Da iniziare, filtro per Progetto. Dipende dal passo 1 e da 01 (WorktreeManager).
3. **Azioni del passo successivo**: Fondi… con conferma e Archivia (da 02 e 01); Apri PR, Aggiorna PR, Correggi e i check sulla card PR aperta. Dipende dal passo 1, da 02 e da 16 (Sessione → PR).
4. **Bozze da issue e Automazioni**: ⌘I, script Linear e `bubo://` come Bozze, chiave anti-doppioni, filtro per fonte, segno Automazione e Programma… Dipende dal passo 2, da 16 (issue → Sessione) e da 19.

## Specifica "migliore di"

Miglior concorrente: **Superset Workspaces**, colonne derivate e mai in disaccordo con la lista ma nessun avvio dai compiti sulla stessa board, e **Claude Progetti**, pulsanti del passo successivo ma nessuna approvazione dalla card. Le board con trascinamento (Vibe Kanban, Cline) mentono sullo stato.
Bubo li supera così (i valori di tempo e prestazioni sono obiettivi, da misurare in costruzione):

1. **0 disaccordi**: sulle sequenze di eventi registrati, la colonna della Board e il gruppo della Vista Colonna coincidono per il **100%** delle Sessioni. Dopo un riavvio, il **100%** delle card torna nella stessa colonna.
2. **Attende te subito**: la Sessione che aspetta da più tempo è la **prima card** di Attende te, visibile con **0 scorrimenti e 0 clic** dopo ⌘4. La card entra in colonna **entro 1 s** dall'evento.
3. **Risposta dalla card**: **1 tasto** (↩ Solo ora, esc No) per una Richiesta di permesso, senza aprire la Sessione. Nessun concorrente approva dalla board.
4. **Da Bozza a Sessione**: **1 gesto** (↩ o trascinamento) e Sessione in Lavora **< 2 s** con 1 GB di dipendenze (01). Da issue GitHub **≤ 2 azioni** (⌘I + ↩).
5. **Nessun trascinamento con effetti nascosti**: **0 trascinamenti** con effetto oltre Bozza → Avvia; **0 merge** senza conferma scritta; **0 push** senza un gesto esplicito (Crea PR, Aggiorna PR).
6. **Il fallimento non sparisce**: **0 Sessioni** in Errore finite in Fusa o fuori dalla Board senza un'azione dell'utente. **0 Sessioni** del checkout principale invisibili.
7. **0 doppioni**: la stessa issue sullo stesso Progetto apre sempre la Bozza o la Sessione esistente.
8. **0 avvii silenziosi**: **0 Sessioni** avviate da un ingresso esterno (Linear, `bubo://`) senza un gesto dell'utente.
9. **Locale**: **0 login** e 0 servizi per la Board; **0 richieste** GitHub o Linear a riposo. Il polling della CI parte solo con una PR aperta e Bubo in primo piano.
10. **Prestazioni** (obiettivo): **60 fps** durante lo scorrimento con 500 Sessioni e 100 Bozze; `BoardColumn` su 500 Sessioni **< 5 ms**; ⌘4 → Board disegnata **< 100 ms**.
11. **Accessibilità**: il **100%** delle azioni della Board (Avvia, risposta alla Richiesta, Fondi…, Archivia, Apri PR) si fa da tastiera e con VoiceOver, senza trascinare.

## Fonti

1. Claude Code, "Projects" (Overview, Threads, Suggested threads) — https://code.claude.com/docs/en/claude-projects
2. Claude Code, "Agent view" — https://code.claude.com/docs/en/agent-view
3. Claude Code, "Desktop" — https://code.claude.com/docs/en/desktop
4. Superset, changelog 2026-08-16 "Workspaces triage" — https://superset.sh/changelog/2026-08-16-workspaces-triage-editable-markdown
5. Superset, docs "Workspaces" — https://docs.superset.sh/workspaces
6. Superset, `deriveBoardColumn.ts` e `V2WorkspacesBoard.tsx` — https://github.com/superset-sh/superset/blob/main/apps/desktop/src/renderer/routes/_authenticated/_dashboard/v2-workspaces/utils/deriveBoardColumn/deriveBoardColumn.ts
7. Superset, docs "Tasks" — https://docs.superset.sh/tasks
8. Superset, `TasksBoardView.tsx` — https://github.com/superset-sh/superset/blob/main/apps/desktop/src/renderer/routes/_authenticated/_dashboard/tasks/components/TasksView/components/TasksBoardView/TasksBoardView.tsx
9. Nimbalyst, `sessionPhaseTransition.ts` — https://github.com/nimbalyst/nimbalyst/blob/main/packages/electron/src/main/services/session/sessionPhaseTransition.ts ; README — https://github.com/nimbalyst/nimbalyst
10. Nimbalyst, `SessionKanbanBoard.tsx` — https://github.com/nimbalyst/nimbalyst/blob/main/packages/electron/src/renderer/components/TrackerMode/SessionKanbanBoard.tsx
11. Vibe Kanban, `crates/db/src/models/task.rs` — https://github.com/BloopAI/vibe-kanban/blob/main/crates/db/src/models/task.rs
12. Vibe Kanban, docs "Creating tasks" — https://github.com/BloopAI/vibe-kanban/blob/main/docs/core-features/creating-tasks.mdx
13. Vibe Kanban, docs "New task attempts" — https://github.com/BloopAI/vibe-kanban/blob/main/docs/core-features/new-task-attempts.mdx
14. Vibe Kanban, docs "Completing a task" — https://github.com/BloopAI/vibe-kanban/blob/main/docs/core-features/completing-a-task.mdx
15. Vibe Kanban, docs "Kanban board" (cloud) — https://github.com/BloopAI/vibe-kanban/blob/main/docs/cloud/kanban-board.mdx
16. Vibe Kanban, docs "Issue management" — https://github.com/BloopAI/vibe-kanban/blob/main/docs/issue-management.mdx
17. Cline Kanban, `web-ui/src/data/board-data.ts` — https://github.com/cline/kanban/blob/main/web-ui/src/data/board-data.ts
18. Cline Kanban, `web-ui/src/hooks/use-board-interactions.ts` — https://github.com/cline/kanban/blob/main/web-ui/src/hooks/use-board-interactions.ts
19. Cline Kanban, `web-ui/src/state/drag-rules.ts` — https://github.com/cline/kanban/blob/main/web-ui/src/state/drag-rules.ts
20. Cline Kanban, README — https://github.com/cline/kanban
21. Conductor, 0.35.0 "Workspace status" — https://www.conductor.build/changelog/0.35.0-workspace-status ; 0.33.5 (sperimentale) — https://www.conductor.build/changelog/0.33.5-better-archiving
22. Conductor, 0.35.2 — https://www.conductor.build/changelog/0.35.2-group-workspaces-by-repo-gpt-5-3-codex-spark
23. Conductor, 0.85.0 — https://www.conductor.build/changelog/0.85.0-sections-routines-and-a-new-model-picker
24. Conductor, 0.63.0 Dispatcher — https://www.conductor.build/changelog/0.63.0-cursor-support-dispatcher
25. Conductor, 0.66.0 "Create workspace from issue" — https://www.conductor.build/changelog/0.66.0-create-workspace-from-issue
26. Conductor, 0.44.0 nuova barra laterale — https://www.conductor.build/changelog/0.44.0-new-sidebar-rebuilt-composer-codex-checkpoints
27. Cursor, forum ufficiale "Agent window statuses broken" — https://forum.cursor.com/t/agent-window-statuses-broken/157310
28. Cursor, forum "Making list of agents more visual" — https://forum.cursor.com/t/making-list-of-agents-more-visual/157526
29. Warp, "Managing cloud agents" — https://docs.warp.dev/agent-platform/cloud-agents/managing-cloud-agents
30. Linear, "Agents in Linear" — https://linear.app/docs/agents-in-linear
31. Linear, "Agent best practices" — https://linear.app/developers/agent-best-practices
32. Linear, "Agent interaction" — https://linear.app/developers/agent-interaction
33. OpenAI, Codex "Projects" — https://learn.chatgpt.com/docs/projects.md ; "Cloud" — https://learn.chatgpt.com/docs/cloud.md
34. GitHub Docs, "About Copilot coding agent" — https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-coding-agent ; "Track Copilot sessions" — https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/track-copilot-sessions
35. Vibe Kanban, "Shutdown" — https://vibekanban.com/blog/shutdown
