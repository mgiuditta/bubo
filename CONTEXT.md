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
Una cartella su cui Bubo lavora, dentro o fuori da un repo git. Se è un repo, è il checkout principale.
_Avoid_: repo, workspace, cartella di lavoro

**Sessione**:
Un'unità di lavoro durevole su un **Progetto**, con un titolo, una propria copia isolata del Progetto (se git) e la storia delle conversazioni dell'agente che la compongono.
_Avoid_: task, workspace, chat, thread

**Conversazione dell'agente**:
Una singola sessione del motore agentico; una **Sessione** ne contiene una catena (ripresa, fork).
_Avoid_: sessione (per questo significato)

**Domanda**:
Una richiesta leggera senza **Progetto** né copia isolata (meteo, riassunto di un file). Si può trasformare in **Sessione**.
_Avoid_: chat, sessione rapida

**Attività**:
Cosa sta facendo una **Sessione** adesso: Lavora, Attende te, Ferma, Errore.
_Avoid_: stato (riservato all'Orb)

**Fase**:
Dove si trova una **Sessione** nella sua vita: Aperta, In revisione, Fusa, Archiviata.
_Avoid_: stato, status

**Cronologia CLI**:
Le conversazioni avviate fuori da Bubo con la riga di comando; si consultano e si riprendono solo come nuova **Sessione**.
_Avoid_: sessioni importate

**Vista delle Sessioni**:
Il modo in cui l'**HUD** dispone le **Sessioni**: Colonna (lista, predefinita), Orbita (satelliti attorno all'**Orb**), Striscia (carte sopra il prompt). La sceglie l'utente.
_Avoid_: layout, tema, modalità

**Galassia**:
La mappa del **Progetto** in cui ogni cartella è un ammasso a posizione fissa e ogni file una stella; mostra dove lavorano le **Sessioni** e accanto tiene sempre la lista dei file toccati.
_Avoid_: grafo del repo, città, albero

### Router

**Tipo di richiesta**:
La classe, da un elenco chiuso, in cui il router colloca ciò che l'utente chiede (per le Sessioni: Pianifica, Correzione piccola, Modifica ampia, Esplora il codice, Revisione; per le Domande: Fatto breve, Riassunto, Scrittura, Ragionamento, Ricerca sul web). Guida la scelta di modello e sforzo e dà il nome alle preferenze ricordate.
_Avoid_: intent, categoria (riservata alle Varianti), compito

**Scala**:
L'ordine dei gradini modello · sforzo che "Rifai più forte" sale uno alla volta, prima lo sforzo poi il modello; si ricava dai modelli disponibili all'utente.
_Avoid_: tier, livello

### Permessi

**Richiesta di permesso**:
La domanda che Bubo pone prima che l'agente compia un'azione non ancora consentita. Risposte: No, Solo ora, Per questa Sessione, Sempre in questo Progetto.
_Avoid_: popup, prompt, conferma

**Regola di permesso**:
Un'autorizzazione salvata che consente o nega un tipo di azione (es. un comando e i suoi argomenti) in un **Progetto** o ovunque.
_Avoid_: whitelist, eccezione

**Livello di rischio**:
La gravità di un'azione, da 1 a 5: Lettura, Modifica reversibile, Rete, Distruttivo locale, Irreversibile esterno. Dai livelli 4–5 non nasce mai una **Regola di permesso**.
_Avoid_: pericolosità, severità

**Modalità autonoma**:
Una **Sessione** che lavora senza **Richieste di permesso** fino al livello 3; possibile solo in una copia isolata del **Progetto**.
_Avoid_: yolo, bypass

### Memoria

**Memoria di Progetto**:
Ciò che l'agente ricorda di un **Progetto** tra una **Sessione** e l'altra; è la stessa memoria che vede la riga di comando, non una copia di Bubo.
_Avoid_: contesto, knowledge base

**Secondo cervello**:
Una cartella di note Markdown dell'utente (un vault Obsidian o qualunque altra) che Bubo consulta e in cui scrive; non appartiene a nessun **Progetto**.
_Avoid_: vault (quando non è Obsidian), wiki, archivio

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
- **Attività** e **Fase** sono indipendenti: una **Sessione** In revisione può essere Ferma o Lavora
- Una **Tinta** per fornitore, non per modello; un fornitore fuori elenco prende la **Tinta** neutra
- Lo **Stato** dell'**Orb** riflette l'**Attività** della **Sessione** che l'utente ha davanti
- Nella **Galassia** le **Sessioni** si distinguono per nome e segno, non per colore: la **Tinta** resta del fornitore, e le Sessioni sono tutte Claude
- Ogni richiesta ha un solo **Tipo di richiesta**; il **Tipo di richiesta** non è la **Categoria** della **Variante**: "Correzione piccola" può mostrare una Variante di Codice o di Ricerca
- Riprendere una conversazione della **Cronologia CLI** crea sempre una nuova **Sessione** (fork), mai la stessa

## Flagged ambiguities

- "campo" nel brief indicava sia la Categoria sia la forma scelta: risolto in **Categoria** (raggruppamento) e **Variante** (la cosa scelta).
- "orb" indicava sia la presenza sia la forma sferica di riposo: risolto in **Orb** (presenza) e **Blob** (forma di riposo).
- "stato" per la Sessione si scontrava con lo **Stato** dell'Orb: risolto in **Attività** e **Fase**.
- "sessione" indicava sia l'unità di lavoro di Bubo sia quella del motore agentico: risolto in **Sessione** e **Conversazione dell'agente**.
