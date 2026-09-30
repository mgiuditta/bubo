# Bubo

Assistente agentico nativo per macOS, con un orb 3D che parla, ascolta e prende forma in base a ciò che gli si chiede.

## Language

### Orb

**Orb**:
La presenza visiva di Bubo: il corpo 3D animato che si vede sullo schermo, qualunque forma abbia in quel momento.
_Avoid_: sfera, avatar, Jarvis

**Blob**:
La forma di riposo dell'**Orb**: una massa organica che respira. Ogni trasformazione parte dal Blob e ci ritorna.
_Avoid_: sfera, orb (quando si intende la forma)

**Stato**:
Il comportamento dell'**Orb** legato a ciò che Bubo sta facendo: Riposo, Ascolto, Pensiero, Parla, Lavora. È indipendente dalla forma.
_Avoid_: modalità, fase

**Panel**:
Il contenitore flottante, sempre in primo piano, che mostra l'**Orb** compatto ovunque nel sistema.
_Avoid_: overlay, widget

**HUD**:
La finestra di lavoro con l'**Orb** grande al centro e i pannelli di vetro attorno (router, cronologia, sessioni).
_Avoid_: dashboard, finestra principale

**Palette**:
L'unica casella, aperta sopra la finestra di Bubo attiva, in cui si cercano insieme comandi, conversazioni e **Secondo cervello**.
_Avoid_: command palette, ricerca globale, launcher

**Forma**:
Il solido 3D descritto da una funzione di distanza: la geometria che l'**Orb** assume. Il **Blob** è una Forma.
_Avoid_: shape, modello 3D, oggetto

**Variante**:
Una voce con nome del **Catalogo** (`lente`, `busta`, `drago`): lega un nome a una **Forma**, a una **Categoria** e al suo carattere. È ciò che viene scelto in base alla richiesta.
_Avoid_: campo, seed, skin

**Catalogo**:
L'elenco completo e unico delle **Varianti** (obiettivo: 500), condiviso da tutto ciò che le sceglie o le disegna.
_Avoid_: libreria, galleria

**Categoria**:
Il raggruppamento tematico delle **Varianti** (Codice, Meteo, Musica, Tempo, Mail, Ricerca, Creativo, Finanza, Salute, Viaggi, Chat, Agente).
_Avoid_: campo, field

**Morph**:
Il passaggio animato dell'**Orb** da una **Forma** all'altra, sempre attraverso il **Blob**.
_Avoid_: transizione, blend

**Tinta**:
La firma astratta di un fornitore di modelli (colore, texture, carattere) che l'**Orb** assume quando quel fornitore risponde.
_Avoid_: logo, tema, brand

### Lavoro

**Progetto**:
Una cartella su cui Bubo lavora, dentro o fuori da un repo git, su una **Macchina**. Se è un repo, è il checkout principale.
_Avoid_: repo, workspace, cartella di lavoro

**Macchina**:
Dove sta un **Progetto** e girano le sue **Sessioni**: il Mac di Bubo o un computer dell'utente raggiunto via SSH, con il suo `claude` e il suo login.
_Avoid_: server, host, remoto (come sostantivo)

**Sessione**:
Un'unità di lavoro durevole su un **Progetto**, con un titolo, una propria copia isolata del Progetto (se git) e la storia delle conversazioni dell'agente che la compongono.
_Avoid_: task, workspace, chat, thread

**Conversazione dell'agente**:
Una singola sessione del motore agentico; una **Sessione** ne contiene una catena (ripresa, fork).
_Avoid_: sessione (per questo significato)

**Domanda**:
Una richiesta leggera senza **Progetto** né copia isolata (meteo, riassunto di un file). Si può trasformare in **Sessione**.
_Avoid_: chat, sessione rapida

**Allegato**:
Testo, file o screenshot che accompagna una richiesta, arrivato da un ingresso di sistema (trascinamento, Servizi, Comandi rapidi, selettore di finestra) o aggiunto nel prompt.
_Avoid_: contesto, riferimento

**Attività**:
Cosa sta facendo una **Sessione** adesso: Lavora, Attende te, Ferma, Errore.
_Avoid_: stato (riservato all'Orb)

**Fase**:
Dove si trova una **Sessione** nella sua vita: Aperta, In revisione, Fusa, Archiviata.
_Avoid_: stato, status

**Cronologia CLI**:
Le conversazioni avviate fuori da Bubo con la riga di comando; si consultano e si riprendono solo come nuova **Sessione**. Bubo ne conserva una copia anche dopo che la riga di comando le cancella, salvo scelta contraria dell'utente.
_Avoid_: sessioni importate

**Vista delle Sessioni**:
Il modo in cui l'**HUD** dispone le **Sessioni**: Colonna (lista, predefinita), Orbita (satelliti attorno all'**Orb**), Striscia (carte sopra il prompt), Board (colonne derivate da **Fase** e **Attività**, più le **Bozze** da iniziare). La sceglie l'utente.
_Avoid_: layout, tema, modalità

**Bozza**:
Un lavoro da iniziare su un **Progetto**: titolo e testo che diventeranno il prompt. Si scrive a mano o nasce da un'issue GitHub o Linear; con Avvia diventa una **Sessione**.
_Avoid_: compito, task, backlog, ticket

**Automazione**:
Una richiesta programmata dall'utente che, all'ora stabilita e solo con Bubo aperto, parte come nuova **Sessione** su un **Progetto**.
_Avoid_: cron, routine, job

**Esecuzione**:
Uno scatto di un'**Automazione**. Se parte diventa una **Sessione**; esito Fatta, Senza modifiche, Saltata o Interrotta.
_Avoid_: run, job

**Anteprima**:
La vista web, dentro Bubo, di un server locale avviato da una **Sessione**; ogni Sessione ha la sua, con i suoi cookie. La vedono e la usano sia l'utente sia l'agente.
_Avoid_: browser, preview

**Galassia**:
La mappa del **Progetto** in cui ogni cartella è un ammasso a posizione fissa e ogni file una stella; mostra dove lavorano le **Sessioni** e accanto tiene sempre la lista dei file toccati.
_Avoid_: grafo del repo, città, albero

### Costi

**Quota**:
La parte usata dei limiti dell'abbonamento Claude (finestra di 5 ore, settimana), in percentuale; non è denaro.
_Avoid_: limite, crediti, uso

**Spesa**:
I dollari pagati a un fornitore a consumo (API key, OpenRouter, crediti extra dell'abbonamento), esatti o stimati dai token.
_Avoid_: costo (da solo), uso

**Valore a listino**:
Quanto costerebbe a consumo il lavoro fatto con l'abbonamento; si mostra ma non si paga e non si somma mai alla **Spesa**.
_Avoid_: risparmio, costo equivalente

**Budget**:
Il tetto mensile di **Spesa** che l'utente fissa per un fornitore a consumo, per un **Progetto** o in totale; alla soglia avvisa, al limite ferma e chiede.
_Avoid_: limite, tetto, quota

### Router

**Tipo di richiesta**:
La classe, da un elenco chiuso, in cui il router colloca ciò che l'utente chiede (per le Sessioni: Pianifica, Correzione piccola, Modifica ampia, Esplora il codice, Revisione; per le Domande: Fatto breve, Riassunto, Scrittura, Ragionamento, Ricerca sul web). Guida la scelta di modello e sforzo e dà il nome alle preferenze ricordate.
_Avoid_: intent, categoria (riservata alle Varianti), compito

**Scala**:
L'ordine dei gradini modello · sforzo che "Rifai più forte" sale uno alla volta, prima lo sforzo poi il modello; si ricava dai modelli disponibili all'utente.
_Avoid_: tier, livello

**Modello locale**:
Il modello scelto dall'utente tra quelli di un server sul Mac (Ollama, LM Studio); il router lo usa solo per preferenza dell'utente o come ripiego, mai da solo. Apple FM non è il Modello locale.
_Avoid_: modello offline, LLM locale

### Permessi

**Richiesta di permesso**:
La domanda che Bubo pone prima che l'agente compia un'azione non ancora consentita. Risposte: No, Solo ora, Per questa Sessione, Sempre in questo Progetto.
_Avoid_: popup, prompt, conferma

**Regola di permesso**:
Un'autorizzazione salvata che consente o nega un tipo di azione (es. un comando e i suoi argomenti) in un **Progetto**, in un'**Automazione** o ovunque.
_Avoid_: whitelist, eccezione

**Livello di rischio**:
La gravità di un'azione, da 1 a 5: Lettura, Modifica reversibile, Rete, Distruttivo locale, Irreversibile esterno. Dai livelli 4–5 non nasce mai una **Regola di permesso**.
_Avoid_: pericolosità, severità

**Modalità autonoma**:
Una **Sessione** che lavora senza **Richieste di permesso** fino al livello 3; possibile solo in una copia isolata del **Progetto**.
_Avoid_: yolo, bypass

### Telecomando

**Telecomando**:
L'app iPhone di Bubo che segue le **Sessioni** di un Mac e risponde alle sue **Richieste di permesso**; il lavoro resta sempre sul Mac.
_Avoid_: app mobile, companion

**Dispositivo accoppiato**:
Un iPhone autorizzato a comandare un Mac, con una chiave propria; si revoca da entrambi i lati.
_Avoid_: device, client

**Verdetto**:
La risposta firmata del **Telecomando** a una **Richiesta di permesso**; scade dopo 10 minuti e non vale se la Richiesta è già risolta sul Mac.
_Avoid_: approvazione remota

**Battito**:
L'ultimo segnale di vita del Mac visto dal **Telecomando**, per sapere quanto sono freschi i dati.
_Avoid_: heartbeat, ping

### Memoria

**Memoria di Progetto**:
Ciò che l'agente ricorda di un **Progetto** tra una **Sessione** e l'altra; è la stessa memoria che vede la riga di comando, non una copia di Bubo.
_Avoid_: contesto, knowledge base

**Secondo cervello**:
Una cartella di note Markdown dell'utente (un vault Obsidian o qualunque altra) che Bubo consulta e in cui scrive; non appartiene a nessun **Progetto**.
_Avoid_: vault (quando non è Obsidian), wiki, archivio

**Riassunto di Sessione**:
La nota Markdown che Bubo scrive nel **Secondo cervello** quando una **Sessione** diventa Fusa o Archiviata; una per Sessione.
_Avoid_: recap, log, diario

**Indice**:
La copia, tenuta sul Mac e ricostruibile, del **Secondo cervello**, della **Memoria di Progetto** e delle conversazioni passate (**Sessioni** e **Cronologia CLI**), in cui si cerca per significato e per parole; non contiene il codice dei **Progetti**.
_Avoid_: database vettoriale, vector store, indice semantico

### Voce

**Sintesi parlata**:
Le una o due frasi che Bubo dice ad alta voce quando gli si è parlato; il testo completo della risposta resta scritto nel **Panel**.
_Avoid_: lettura, TTS (per il contenuto)

## Relationships

- L'**Orb** vive in un **Panel** oppure in un **HUD**: è lo stesso Orb, cambia solo il contenitore
- Si vede un solo **Orb** alla volta: quando l'**HUD** è aperto il **Panel** sparisce, e torna quando l'HUD si chiude
- Lo **Stato** si applica a qualunque forma dell'**Orb**, **Blob** compreso
- Il **Catalogo** contiene molte **Varianti**; ogni **Variante** appartiene a una sola **Categoria** e usa una sola **Forma**
- Una **Forma** serve una sola **Variante**: i sinonimi non diventano Varianti nuove
- Il nome di una **Variante** è stabile: non si rinomina, al massimo si ritira
- Lo **Stato** non cambia mai la **Forma**; in Riposo l'**Orb** torna al **Blob**
- Il router sceglie la **Variante** iniziale; durante il lavoro la **Variante** può cambiare a ogni passo
- **Stato**, **Variante** e **Tinta** sono indipendenti; il colore viene sempre dalla **Tinta**, mai dalla Variante: un **Orb** a forma di `lente` può essere in Pensiero con la Tinta di un altro fornitore
- Un **Progetto** ha molte **Sessioni**; al massimo una lavora direttamente sul checkout principale, le altre ciascuna nella propria copia isolata
- Un **Progetto** sta su una sola **Macchina**, e tutte le sue **Sessioni** girano lì
- **Attività** e **Fase** sono indipendenti: una **Sessione** In revisione può essere Ferma o Lavora
- Una **Tinta** per fornitore, non per modello; un fornitore fuori elenco prende la **Tinta** neutra
- Lo **Stato** dell'**Orb** riflette l'**Attività** della **Sessione** che l'utente ha davanti
- La **Galassia** mostra un solo **Progetto** alla volta, vive fuori dall'**HUD** e non contiene mai l'**Orb**; non è una **Vista delle Sessioni**
- Nella **Galassia** le **Sessioni** si distinguono per nome e segno, non per colore: la **Tinta** resta del fornitore, e le Sessioni sono tutte Claude
- Ogni richiesta ha un solo **Tipo di richiesta**; il **Tipo di richiesta** non è la **Categoria** della **Variante**: "Correzione piccola" può mostrare una Variante di Codice o di Ricerca
- Riprendere una conversazione della **Cronologia CLI** crea sempre una nuova **Sessione** (fork), mai la stessa
- Un ingresso di sistema crea una **Domanda** con i suoi **Allegati**; diventa **Sessione** solo su proposta accettata, tranne un trascinamento nell'**HUD** con una **Sessione** davanti, che allega a quella
- Dal **Telecomando** una **Richiesta di permesso** riceve solo No, Solo ora o Per questa Sessione; dai livelli 4–5 solo No o Solo ora. Sempre in questo Progetto si decide solo sul Mac

- **Quota**, **Spesa** e **Valore a listino** hanno unità diverse (%, $, $ non pagati) e non si sommano mai
- Un **Budget** vale solo sulla **Spesa**: l'abbonamento ha la **Quota**, i modelli sul Mac sono gratis

## Flagged ambiguities

- "campo" nel brief indicava sia la Categoria sia la forma scelta: risolto in **Categoria** (raggruppamento) e **Variante** (la cosa scelta).
- "orb" indicava sia la presenza sia la forma sferica di riposo: risolto in **Orb** (presenza) e **Blob** (forma di riposo).
- "stato" per la Sessione si scontrava con lo **Stato** dell'Orb: risolto in **Attività** e **Fase**.
- "sessione" indicava sia l'unità di lavoro di Bubo sia quella del motore agentico: risolto in **Sessione** e **Conversazione dell'agente**.
