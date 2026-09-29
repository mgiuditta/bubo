# Bubo

Assistente agentico nativo per macOS, con un orb 3D che parla, ascolta e prende forma in base a ciò che gli si chiede.

## Language

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

## Relationships

- L'**Orb** vive in un **Panel** oppure in un **HUD**: è lo stesso Orb, cambia solo il contenitore
- Lo **Stato** si applica a qualunque forma dell'**Orb**, **Blob** compreso
- Il **Catalogo** contiene molte **Varianti**; ogni **Variante** appartiene a una sola **Categoria** e usa una sola **Forma**
- Il router sceglie la **Variante** iniziale; durante il lavoro la **Variante** può cambiare a ogni fase
- **Stato**, **Variante** e **Tinta** sono indipendenti: un **Orb** a forma di `lente` può essere in Pensiero con la Tinta di un altro fornitore

## Flagged ambiguities

- "campo" nel brief indicava sia la Categoria sia la forma scelta: risolto in **Categoria** (raggruppamento) e **Variante** (la cosa scelta).
- "orb" indicava sia la presenza sia la forma sferica di riposo: risolto in **Orb** (presenza) e **Blob** (forma di riposo).
