# Feature di Bubo: stato

Obiettivo: per ogni feature, battere il miglior concorrente con criteri misurabili. Ogni feature ha un file `NN-nome.md` con ricerca, mappa e specifica "migliore di".

Mappe wayfinder: [Bubo — feature 1–6: base competitiva](https://github.com/mgiuditta/bubo/issues/11), [Bubo — feature 8–13: voce, sistema, router, galassia, memoria](https://github.com/mgiuditta/bubo/issues/42). Si costruisce sopra [Bubo — fase 1 e 2: fondamenta e Orb](https://github.com/mgiuditta/bubo/issues/1).

Stati: **da fare**, **in corso**, **fatta**, **bloccata**.

| # | Feature | Stato | Note |
|---|---|---|---|
| 01 | Sessioni Claude Code in parallelo in git worktree | in corso | specifica pronta; costruzione dopo la shell |
| 02 | Revisione diff e merge in-app, approvazione per blocco | in corso | specifica pronta; costruzione dopo la shell |
| 03 | Login abbonamento dalla CLI, API key, fallback, uso visibile | in corso | specifica pronta ([ADR 0003](../adr/0003-login-con-la-cli-claude-dell-utente.md)); costruzione dopo la shell |
| 04 | Riuso di `~/.claude`: skill, hook, CLAUDE.md, MCP, cronologia | in corso | specifica pronta; costruzione dopo la shell |
| 05 | Permessi in GUI con regole "consenti sempre" per progetto | in corso | specifica pronta; costruzione dopo la shell |
| 06 | Stato delle sessioni, notifiche native, badge nel Dock | in corso | specifica pronta; costruzione dopo la shell |
| 07 | Orb 3D in Metal: stati vocali e Morph | in corso | mappa fase 1–2; Catalogo di Varianti al posto di 12×1.000 (ADR 0002) |
| 08 | Voce: push-to-talk, dettatura locale, Sintesi parlata, interruzione | in corso | specifica pronta; wake word fuori v1; barge-in dietro spike |
| 09 | Integrazione Finder e sistema | in corso | specifica pronta ([ADR 0005](../adr/0005-claude-senza-i-permessi-tcc-di-bubo.md)); pipeline degli ingressi condivisa con 08 e 10 |
| 10 | Router multi-modello con scelta spiegata e override | in corso | specifica pronta ([ricerca Jev](10-router-jev.md)); Jev facoltativo dietro cancello di adozione |
| 11 | Galassia: mappa 2,5D del Progetto con le Sessioni al lavoro e diff in vetro | in corso | specifica pronta; finestra a sé |
| 12 | Secondo cervello: qualunque cartella Markdown, Obsidian facoltativo | in corso | specifica pronta; legge solo via [Indice](indice-semantico.md) |
| 13 | Memoria di Progetto visibile e Riassunto di Sessione | in corso | specifica pronta; dopo Indice e 12 |
| 14 | Cronologia ricercabile per significato | da fare | |
| 15 | Terminale, editor, anteprima server, browser in-app | da fare | |
| 16 | Integrazioni GitHub e Linear | da fare | |
| 17 | Task board / kanban delle sessioni, anche 3D | da fare | |
| 18 | Dashboard di costo e uso, budget e avvisi | da fare | |
| 19 | Agenti personalizzati e automazioni programmate | da fare | |
| 20 | Marketplace di skill, MCP e agenti | da fare | |
| 21 | App iPhone compagna | da fare | |
| 22 | Esecuzione in sandbox o container | da fare | |
| 23 | Workspace remoti e cloud | da fare | |
| 24 | Multiplayer | da fare | |
| 25 | Performance nativa: avvio < 1 s, poca RAM, 60 fps con 10 sessioni | da fare | |
| 26 | Onboarding di 60 secondi | da fare | |
| 27 | Rifinitura premium e aggiornamenti automatici | da fare | |

## Architettura comune (feature 1–6)

Un solo target app (XcodeGen, cartelle per modulo). I pezzi condivisi si scrivono una volta:

- `Agent/AgentBridge` + `bridge/` (TS, `bun build --compile`): protocollo JSON versionato su stdio; una Conversazione dell'agente per processo figlio; `env` costruito da zero (API key solo lì, `CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS=1`); `cwd` = worktree, `projectConfigRoot` = checkout principale.
- `Sessions/` (Sessione, Attività, Fase, worktree, porte): base di 1, 2, 6 e più avanti 13, 17, 18.
- `Git/` (git CLI, niente libgit2): worktree, diff per blocco (`git apply --cached --recount`), `merge-tree --write-tree`, stato via FSEvents, mai polling.
- `Permissions/`, `Account/`, `Config/`, `System/` (notifiche, badge), `HUD/` (Viste delle Sessioni, revisione, pannelli).

## Ordine di implementazione (feature 1–6)

0. **Shell dell'app** (mappa fase 1–2: [Shell dell'app](https://github.com/mgiuditta/bubo/issues/6)): progetto, design tokens, HUD vuoto. Prerequisito di tutto.
1. **Ponte agente minimo**: una Conversazione in una cartella, streaming nell'HUD. Serve a 1, 3, 4, 5, 6. Ticket: [#66](https://github.com/mgiuditta/bubo/issues/66).
2. **03 Account e uso** e **04 configurazione `~/.claude`**: poco codice, sbloccano l'uso reale. Ticket: [#67](https://github.com/mgiuditta/bubo/issues/67), [#68](https://github.com/mgiuditta/bubo/issues/68) (03), [#73](https://github.com/mgiuditta/bubo/issues/73), [#74](https://github.com/mgiuditta/bubo/issues/74) (04).
3. **01 Sessioni in worktree**. Ticket: [#69](https://github.com/mgiuditta/bubo/issues/69), [#70](https://github.com/mgiuditta/bubo/issues/70), [#71](https://github.com/mgiuditta/bubo/issues/71), [#72](https://github.com/mgiuditta/bubo/issues/72).
4. **06 Attività, notifiche e badge** (Vista Colonna per prima). Ticket: [#75](https://github.com/mgiuditta/bubo/issues/75), [#76](https://github.com/mgiuditta/bubo/issues/76), [#77](https://github.com/mgiuditta/bubo/issues/77).
5. **05 Permessi**. Ticket: [#78](https://github.com/mgiuditta/bubo/issues/78), [#79](https://github.com/mgiuditta/bubo/issues/79), [#80](https://github.com/mgiuditta/bubo/issues/80).
6. **02 Revisione e merge**. Ticket: [#81](https://github.com/mgiuditta/bubo/issues/81), [#82](https://github.com/mgiuditta/bubo/issues/82), [#83](https://github.com/mgiuditta/bubo/issues/83), [#84](https://github.com/mgiuditta/bubo/issues/84).

## Architettura comune (feature 8–13)

Stesso target, stesse regole: locale per default, nessun contenuto del Progetto a fornitori diversi da Claude senza consenso, `claude` avviato senza i permessi TCC di Bubo ([ADR 0005](../adr/0005-claude-senza-i-permessi-tcc-di-bubo.md)). Pezzi condivisi nuovi:

- `Intake/` (**pipeline degli ingressi**, [09](09-sistema.md)): ogni ingresso (voce, trascinamento, Servizio, App Intent) diventa una Domanda con Allegati, passa dal classificatore e arriva all'Orb. `AttachmentPolicy` decide cosa può andare a quale fornitore.
- `Router/` ([10](10-router.md)): `RequestClassifier` (Apple FM + regole, Jev facoltativo) produce insieme Tipo di richiesta e Variante; `ModelRouter` sceglie modello e sforzo; `Providers` con un solo client OpenAI-compatibile.
- `Index/` + strumento MCP `cerca` (**Indice**, [indice-semantico.md](indice-semantico.md)): SQLite di sistema + FTS5 + vettori in Accelerate su Secondo cervello, Memoria di Progetto e conversazioni. Serve 12, 13 e più avanti 14.
- `Agent/ProcessSpawner`: avvio di `claude` con disclaim, parte del ponte agente minimo.

Moduli per feature: `Voice/` (08), `System/Services`, `System/Intents`, `System/ScreenCapture`, `Panel/OrbDropTarget` (09), `HUD/RouterLine` e `HUD/RouterChip` (10), `Galaxy/` (11), `SecondBrain/` (12), `Memory/`, `HUD/MemoryPanel` (13).

## Ordine di implementazione (feature 8–13)

Parte dopo l'ordine delle feature 1–6 e il PRD fase 1–2 (Stati, Tinte, Catalogo e Morph dell'Orb). Pezzi condivisi prima.

0. **Ponte agente con disclaim** (ADR 0005): prerequisito di tutto ciò che avvia `claude`. È lo stesso ticket del ponte agente minimo: [#66](https://github.com/mgiuditta/bubo/issues/66).
1. **Pipeline degli ingressi + classificatore** (`Intake/` e `Router/RequestClassifier`, senza Jev): nascono insieme, perché il classificatore produce la Variante e la pipeline lo chiama. Primo ingresso: il prompt scritto. Ticket: [#85](https://github.com/mgiuditta/bubo/issues/85), [#86](https://github.com/mgiuditta/bubo/issues/86), [#87](https://github.com/mgiuditta/bubo/issues/87).
2. **10 Router**: `ModelRouter`, riga del motivo, chip, "Rifai con…", Domande su Apple FM e client OpenAI-compatibile. Ticket: [#88](https://github.com/mgiuditta/bubo/issues/88), [#89](https://github.com/mgiuditta/bubo/issues/89), [#90](https://github.com/mgiuditta/bubo/issues/90), [#91](https://github.com/mgiuditta/bubo/issues/91), [#92](https://github.com/mgiuditta/bubo/issues/92), [#93](https://github.com/mgiuditta/bubo/issues/93), [#94](https://github.com/mgiuditta/bubo/issues/94), [#95](https://github.com/mgiuditta/bubo/issues/95), [#96](https://github.com/mgiuditta/bubo/issues/96), [#97](https://github.com/mgiuditta/bubo/issues/97).
3. **09 Sistema**: trascinamento sull'Orb, poi Servizio, poi App Intents, poi selettore di finestra. Ticket: [#98](https://github.com/mgiuditta/bubo/issues/98), [#99](https://github.com/mgiuditta/bubo/issues/99), [#100](https://github.com/mgiuditta/bubo/issues/100), [#101](https://github.com/mgiuditta/bubo/issues/101), [#102](https://github.com/mgiuditta/bubo/issues/102), [#103](https://github.com/mgiuditta/bubo/issues/103).
4. **08 Voce**: push-to-talk nella pipeline, poi Sintesi parlata, poi interruzione; barge-in dietro spike. Ticket: [#104](https://github.com/mgiuditta/bubo/issues/104), [#105](https://github.com/mgiuditta/bubo/issues/105), [#106](https://github.com/mgiuditta/bubo/issues/106), [#107](https://github.com/mgiuditta/bubo/issues/107), [#108](https://github.com/mgiuditta/bubo/issues/108), [#109](https://github.com/mgiuditta/bubo/issues/109), [#110](https://github.com/mgiuditta/bubo/issues/110).
5. **Indice**: prima FTS5 (parole) con `cerca`, poi vettori, poi conversazioni. Ticket: [#111](https://github.com/mgiuditta/bubo/issues/111), [#112](https://github.com/mgiuditta/bubo/issues/112), [#113](https://github.com/mgiuditta/bubo/issues/113).
6. **12 Secondo cervello**: cartella, `NoteWriter`, lettura via `cerca`. Ticket: [#114](https://github.com/mgiuditta/bubo/issues/114), [#115](https://github.com/mgiuditta/bubo/issues/115).
7. **13 Memoria e Riassunto**: il pannello della Memoria di Progetto può partire subito dopo il ponte; il Riassunto di Sessione dopo 12. Ticket: [#116](https://github.com/mgiuditta/bubo/issues/116), [#117](https://github.com/mgiuditta/bubo/issues/117), [#118](https://github.com/mgiuditta/bubo/issues/118).
8. **11 Galassia**: indipendente da voce, router e Indice; dopo 01, 02 e 06. Ticket: [#119](https://github.com/mgiuditta/bubo/issues/119), [#120](https://github.com/mgiuditta/bubo/issues/120), [#121](https://github.com/mgiuditta/bubo/issues/121), [#122](https://github.com/mgiuditta/bubo/issues/122), [#123](https://github.com/mgiuditta/bubo/issues/123).
9. **Jev** (10): solo dopo il cancello di adozione (+5 punti su Apple FM in italiano, 200 richieste). Ticket: [#124](https://github.com/mgiuditta/bubo/issues/124).

