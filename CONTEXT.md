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

## Relationships

- L'**Orb** vive in un **Panel** oppure in un **HUD**: è lo stesso Orb, cambia solo il contenitore
- Lo **Stato** si applica a qualunque forma dell'**Orb**, **Blob** compreso
