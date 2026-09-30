# Feature di Bubo: stato

Obiettivo: per ogni feature, battere il miglior concorrente con criteri misurabili. Ogni feature ha un file `NN-nome.md` con ricerca, mappa e specifica "migliore di".

Mappe wayfinder: [Bubo — feature 1–6: base competitiva](https://github.com/mgiuditta/bubo/issues/11), [Bubo — feature 8–13: voce, sistema, router, galassia, memoria](https://github.com/mgiuditta/bubo/issues/42), [Bubo — feature 14–19: cronologia, terminale, integrazioni, board, costi, automazioni](https://github.com/mgiuditta/bubo/issues/125), [Bubo — feature 20, 22, 25–27: marketplace, sandbox, prestazioni, onboarding, rifinitura](https://github.com/mgiuditta/bubo/issues/178), [Bubo — feature 21, 23, 24: iPhone, remoti e cloud, multiplayer](https://github.com/mgiuditta/bubo/issues/231), [Bubo v2 — feature 24: consegna, risorse di squadra, condivisione dal vivo](https://github.com/mgiuditta/bubo/issues/259). Si costruisce sopra [Bubo — fase 1 e 2: fondamenta e Orb](https://github.com/mgiuditta/bubo/issues/1).

Stati: **da fare**, **in corso**, **fatta**, **bloccata**, **v2** (decisa per la versione 2: in app come **In arrivo** in Impostazioni › Aggiornamenti; si pianifica in una mappa v2 e si costruisce dopo la v1).

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
| 14 | Cronologia ricercabile per significato | in corso | specifica pronta ([ADR 0006](../adr/0006-bubo-conserva-le-conversazioni.md)); Palette ⌘K sopra l'Indice |
| 15 | Terminale, anteprima del server, apri nell'editor | in corso | specifica pronta; niente editor vero né browser generico |
| 16 | Integrazioni GitHub e Linear | in corso | specifica pronta; solo issue → Sessione e Sessione → PR, il resto via MCP |
| 17 | Board delle Sessioni con le Bozze | in corso | specifica pronta; il 3D è la Vista Orbita |
| 18 | Costi e uso, Budget e avvisi | in corso | specifica pronta; Quota, Spesa e Valore a listino mai sommati |
| 19 | Agenti personalizzati e Automazioni programmate | in corso | specifica pronta; solo con Bubo aperto, niente demone |
| 20 | Marketplace di plugin e Server MCP | in corso | specifica pronta; scrive solo la CLI `claude`, nessun catalogo di Bubo |
| 21 | App iPhone compagna: il Telecomando | in corso | specifica pronta ([ADR 0007](../adr/0007-telecomando-su-cloudkit-senza-server.md)); CloudKit cifrato senza server, non Remote Control; cancello di latenza come primo ticket |
| 22 | Esecuzione in Sandbox | in corso | specifica pronta; sandbox di Claude Code + cancello di Bubo, accesa di default nelle Automazioni |
| 23 | Sessioni remote via SSH e sessioni cloud | in corso | specifica pronta; Macchina SSH con il `claude` dell'host, dal cloud solo "Porta in Bubo"; cancello con spawn SSH reale |
| 24 | Multiplayer: Consegna e Risorse di squadra | v2 | specifica pronta ([ADR 0008](../adr/0008-consegna-come-file-hpke-verso-una-macchina.md), [ADR 0009](../adr/0009-risorse-di-squadra-con-fiducia-per-voce.md)); Consegna come file `.bubo` HPKE auth verso una Macchina, Risorse di squadra in `.bubo/` con fiducia per voce, dal vivo fuori; cancello con un secondo account vero come primo ticket; in v1 solo la voce In arrivo |
| 25 | Performance nativa: avvio < 1 s, poca RAM, 60 fps con 10 sessioni | in corso | specifica pronta; tabella unica dei budget, Sessioni inattive sospese |
| 26 | Onboarding di 60 secondi | in corso | specifica pronta; l'Orb guida nell'HUD, nessun `claude` nel bundle (supera la 03 su questo punto) |
| 27 | Rifinitura premium e aggiornamenti automatici | in corso | specifica pronta; Developer ID, Sparkle 2, Canali stabile e beta; checklist di rifinitura come definizione di fatto |

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

## Architettura comune (feature 14–19)

Stesso target, stesse regole: locale per default, `gh` e `~/.claude` dell'utente riusati, ogni processo avviato con disclaim ([ADR 0005](../adr/0005-claude-senza-i-permessi-tcc-di-bubo.md), esteso a terminale, server e `gh`), conversazioni conservate con una copia a specchio ([ADR 0006](../adr/0006-bubo-conserva-le-conversazioni.md)). Nessuna nuova scorciatoia globale: tutto passa da menu e **Palette**. Pezzi condivisi nuovi:

- `Palette/` (⌘K, [14](14-cronologia.md)): una casella per comandi, conversazioni e Secondo cervello, da HUD e Panel. Ogni feature registra i suoi comandi in `CommandCatalog`.
- `History/ConversationStore` ([14](14-cronologia.md)): copia a specchio via `sessionStore` delle Sessioni e della Cronologia CLI; la leggono 14 e 18.
- `Sessions/BoardColumn` e `Sessions/DraftStore` ([17](17-board.md)): regola fissa delle colonne da Fase e Attività, e Bozze. Le usano 16 (Bozze da issue, colonna PR aperta) e 19 (risultati in "Da guardare").
- `Costs/CostLedger` e `Costs/BudgetGuard` ([18](18-costi-budget.md)): registro di ogni turno e stop morbido. Li usano `Router/ModelRouter` (10) e 19.
- `Agent/ProcessSpawner` e `Sessions/PortAllocator` estesi ([15](15-terminale-anteprima.md)): terminale, server e porte per Sessione; server MCP dell'Anteprima nel `bridge/`.

Moduli per feature: `History/` (14), `Terminal/`, `Servers/`, `Preview/`, `Viewer/`, `Editor/` (15), `Integrations/` (16), `HUD/SessionViews/BoardView` (17), `Costs/` (18), `Agents/`, `Automations/` (19).

## Ordine di implementazione (feature 14–19)

Parte dopo gli ordini delle feature 1–6 e 8–13. I passi rimandano all'`Ordine di costruzione` di ogni spec.

1. **14 Conservazione** (passo 1): copia a specchio con `sessionStore`. Subito dopo il ponte agente e 01: ogni giorno di ritardo sono conversazioni perse dalla CLI. Ticket: [#141](https://github.com/mgiuditta/bubo/issues/141).
2. **18 Registro dei turni e prezzi** (passi 1–2): il totale della Sessione e lo storico devono accumularsi dal primo turno. Dopo 03 e 10. Ticket: [#142](https://github.com/mgiuditta/bubo/issues/142), [#143](https://github.com/mgiuditta/bubo/issues/143).
3. **17 Board** (passi 1–2): regola delle colonne, card, Bozze a mano, ⌘4. Dopo 01, 05, 06. Ticket: [#144](https://github.com/mgiuditta/bubo/issues/144), [#145](https://github.com/mgiuditta/bubo/issues/145).
4. **15 Terminale, server e Anteprima** (passi 1–3). Dopo il ponte con disclaim e 01. Ticket: [#147](https://github.com/mgiuditta/bubo/issues/147), [#148](https://github.com/mgiuditta/bubo/issues/148), [#149](https://github.com/mgiuditta/bubo/issues/149).
5. **16 GitHub e Linear** (passi 1–5) insieme a **17** (passi 3–4): ⌘I, Apri PR, CI e Correggi, Bozze da issue, `gh` mancante. Dopo 02, 13, 15 e 17. Ticket: [#146](https://github.com/mgiuditta/bubo/issues/146), [#151](https://github.com/mgiuditta/bubo/issues/151), [#152](https://github.com/mgiuditta/bubo/issues/152), [#153](https://github.com/mgiuditta/bubo/issues/153), [#154](https://github.com/mgiuditta/bubo/issues/154), [#155](https://github.com/mgiuditta/bubo/issues/155), [#156](https://github.com/mgiuditta/bubo/issues/156).
6. **14 Palette e Cronologia** (passi 2–4): dopo l'Indice ([#111](https://github.com/mgiuditta/bubo/issues/111)–[#113](https://github.com/mgiuditta/bubo/issues/113)) e 12. Da qui ogni comando delle 14–19 entra nella Palette. Ticket: [#157](https://github.com/mgiuditta/bubo/issues/157), [#158](https://github.com/mgiuditta/bubo/issues/158), [#159](https://github.com/mgiuditta/bubo/issues/159), [#160](https://github.com/mgiuditta/bubo/issues/160), [#161](https://github.com/mgiuditta/bubo/issues/161).
7. **18 Finestra Costi e Budget** (passi 3–4): dopo 1 e 06. Ticket: [#162](https://github.com/mgiuditta/bubo/issues/162), [#163](https://github.com/mgiuditta/bubo/issues/163), [#164](https://github.com/mgiuditta/bubo/issues/164), [#165](https://github.com/mgiuditta/bubo/issues/165).
8. **15 L'agente pilota l'Anteprima, visore, editor, Allegati dal terminale** (passi 4–6): dopo 05, `Intake/` e la Palette. Ticket: [#166](https://github.com/mgiuditta/bubo/issues/166), [#150](https://github.com/mgiuditta/bubo/issues/150), [#167](https://github.com/mgiuditta/bubo/issues/167).
9. **19 Agenti e Automazioni** (passi 1–5), con **18** passo 5 (Automazioni saltate a Budget esaurito): dopo 17 e i Budget. Ticket: [#168](https://github.com/mgiuditta/bubo/issues/168), [#169](https://github.com/mgiuditta/bubo/issues/169), [#170](https://github.com/mgiuditta/bubo/issues/170), [#171](https://github.com/mgiuditta/bubo/issues/171), [#172](https://github.com/mgiuditta/bubo/issues/172), [#173](https://github.com/mgiuditta/bubo/issues/173), [#174](https://github.com/mgiuditta/bubo/issues/174), [#175](https://github.com/mgiuditta/bubo/issues/175).

Dopo le 14–19: 20, 22, 25, 26, 27, con un'unica mappa (sotto). **21, 23 e 24 in fondo alla coda**, dopo tutte le altre.

## Architettura comune (feature 20, 22, 25–27)

Una sola mappa per le cinque feature: 25, 26 e 27 sono trasversali e toccano tutte le altre. Stesse regole: locale per default, riuso di `~/.claude` e di `claude`, disclaim ([ADR 0005](../adr/0005-claude-senza-i-permessi-tcc-di-bubo.md)). Pezzi condivisi nuovi:

- **Tabella unica dei budget** ([25](25-prestazioni.md)): ogni soglia di tempo, memoria e fotogrammi delle altre spec rimanda lì. `Perf/Signposts` (un solo signposter e catalogo di nomi), target `BuboPerfTests` con `PerfBudgets.swift`, `scripts/perf.sh`, CI che blocca a 2× il budget.
- `App/LaunchSequence` ([25](25-prestazioni.md)): unico posto per il lavoro dopo il signpost `HUD interattivo`. Ci passano il ponte, il rilevamento di `claude` (26) e MetricKit.
- `Sessions/SessionSuspender` e `Sessions/ProcessFootprintMonitor` ([25](25-prestazioni.md)): Sessioni ferme sospese dopo 10 minuti e riprese con `resume`; il protocollo del `bridge/` guadagna chiudi/riprendi Conversazione.
- `Account/ClaudeLocator`, `Account/ClaudeReadiness`, `Account/AuthFailure` ([26](26-onboarding.md)): percorso assoluto di `claude` per ponte, 03, 20 e 27; stato pronta / mancante / non loggata / vecchia. `System/SystemTerminal` (Terminale senza Apple Events, riusabile dalla 16) e `System/InstallWatcher`.
- `Plugins/ClaudeCLI` ([20](20-marketplace.md)): l'unico punto da cui Bubo scrive la configurazione di Claude Code (`claude plugin|mcp …`), dal checkout principale, in coda seriale, segreti solo su stdin. `Plugins/PluginInventory` dà il segno "fuori dalla sandbox" alla 22.
- `Sandbox/` ([22](22-sandbox.md)): `SandboxPolicy` (preset, credenziali negate), `SandboxStore` (per Progetto e per Automazione, mai nei settings di Claude Code), `SandboxGate` (hook `PreToolUse` sulle scritture), `ViolationParser`.
- `Agent/ClaudeCompatibility` + `bridge/compat.json` ([27](27-rifinitura-aggiornamenti.md)): versione minima di `claude` e `capabilities`, che ogni feature consulta.
- `Updates/` ([27](27-rifinitura-aggiornamenti.md)) con Sparkle 2, `scripts/release/`, workflow `release.yml`, `yank.yml`, `nightly-claude.yml`; release e appcast nel repository pubblico `mgiuditta/bubo-releases`.
- **Checklist di rifinitura** ([27](27-rifinitura-aggiornamenti.md)) come definizione di fatto per ogni ticket con interfaccia: `pull_request_template.md`, `scripts/polish-check.sh` in `check.sh`, `Design/LoadingLabel`, `Design/ErrorNotice`, token di movimento.

Moduli per feature: `Plugins/` (20), `Sandbox/`, `Settings/ProjectSandboxPane` (22), `Perf/`, `Diagnostics/` (25), `Onboarding/` (26), `Updates/` (27).

## Ordine di implementazione (feature 20, 22, 25–27)

La misura e le regole di rifinitura partono presto, perché valgono per tutto ciò che si costruisce dopo. I passi rimandano all'`Ordine di costruzione` di ogni spec.

1. **25 Misura** (passi 1–5): signpost, test di avvio, memoria e fotogrammi, `perf.sh`, CI, MetricKit. Il passo 1 serve solo lo script di verifica e può partire subito. Ticket: [#192](https://github.com/mgiuditta/bubo/issues/192), [#193](https://github.com/mgiuditta/bubo/issues/193), [#194](https://github.com/mgiuditta/bubo/issues/194), [#195](https://github.com/mgiuditta/bubo/issues/195), [#196](https://github.com/mgiuditta/bubo/issues/196).
2. **27 Ponte e checklist** (passi 1 e 9), più il lavoro umano sugli account (passo 2) in parallelo: entitlement minimi, `polish-check.sh` e template delle PR. Ticket: [#219](https://github.com/mgiuditta/bubo/issues/219), [#227](https://github.com/mgiuditta/bubo/issues/227), [#220](https://github.com/mgiuditta/bubo/issues/220).
3. **26 Onboarding** (passi 1–4): dopo 03 ([#38](https://github.com/mgiuditta/bubo/issues/38), [#39](https://github.com/mgiuditta/bubo/issues/39)), il ponte e 01. Supera la 03 su due punti: niente `claude` nel bundle, login aperto nel Terminale. Ticket: [#201](https://github.com/mgiuditta/bubo/issues/201), [#202](https://github.com/mgiuditta/bubo/issues/202), [#203](https://github.com/mgiuditta/bubo/issues/203), [#204](https://github.com/mgiuditta/bubo/issues/204).
4. **25 Avvio differito e Sessioni sospese** (passi 6–8): dopo il ponte e 01. Ticket: [#197](https://github.com/mgiuditta/bubo/issues/197), [#198](https://github.com/mgiuditta/bubo/issues/198), [#199](https://github.com/mgiuditta/bubo/issues/199).
5. **22 Sandbox** (passi 1–4): dopo 05; il passo 2 aggiunge l'interruttore della Modalità autonoma se manca. Il passo 5 (Automazioni) dopo 19. Ticket: [#214](https://github.com/mgiuditta/bubo/issues/214), [#215](https://github.com/mgiuditta/bubo/issues/215), [#216](https://github.com/mgiuditta/bubo/issues/216), [#217](https://github.com/mgiuditta/bubo/issues/217), [#218](https://github.com/mgiuditta/bubo/issues/218).
6. **20 Plugin e Server MCP** (passi 1–8): dopo 04, la Palette e la finestra Agenti della 19. Ticket: [#206](https://github.com/mgiuditta/bubo/issues/206), [#207](https://github.com/mgiuditta/bubo/issues/207), [#208](https://github.com/mgiuditta/bubo/issues/208), [#209](https://github.com/mgiuditta/bubo/issues/209), [#210](https://github.com/mgiuditta/bubo/issues/210), [#211](https://github.com/mgiuditta/bubo/issues/211), [#212](https://github.com/mgiuditta/bubo/issues/212), [#213](https://github.com/mgiuditta/bubo/issues/213).
7. **27 Release e aggiornamenti** (passi 3–8): pipeline firmata, Sparkle, appcast, promemoria, versione minima di `claude`, smoke notturno. Ticket: [#221](https://github.com/mgiuditta/bubo/issues/221), [#222](https://github.com/mgiuditta/bubo/issues/222), [#223](https://github.com/mgiuditta/bubo/issues/223), [#224](https://github.com/mgiuditta/bubo/issues/224), [#225](https://github.com/mgiuditta/bubo/issues/225), [#226](https://github.com/mgiuditta/bubo/issues/226).
8. **Prima della beta** (con una persona davanti): profilazione reale (25), misura dei 60 secondi con 5 persone (26), icona e glifo, audit completo e `v0.1.0-beta.1` (27). Ticket: [#200](https://github.com/mgiuditta/bubo/issues/200), [#205](https://github.com/mgiuditta/bubo/issues/205), [#228](https://github.com/mgiuditta/bubo/issues/228), [#229](https://github.com/mgiuditta/bubo/issues/229).

## Architettura comune (feature 21, 23, 24)

Stesse regole: locale per default, solo canali dell'utente (iCloud, SSH, git/GitHub), nessun server né relay di Bubo, credenziali mai lette né condivise, disclaim ([ADR 0005](../adr/0005-claude-senza-i-permessi-tcc-di-bubo.md)). Pezzi condivisi nuovi:

- `RemoteKit` ([21](21-iphone-compagna.md)): pacchetto condiviso tra l'app Mac e il target iOS `BuboRemote`. Tipi dei record CloudKit, cifratura per coppia Mac–iPhone, firma e verifica dei Verdetti, versione del protocollo. Trasporto scelto nell'[ADR 0007](../adr/0007-telecomando-su-cloudkit-senza-server.md).
- `Remote/` ([21](21-iphone-compagna.md)): `RemoteBridge`, `PairingController`, `PresenceMonitor`, `SleepGuard`. `Permissions/RequestCenter` accetta un Verdetto come risposta, sullo stesso percorso dell'HUD.
- `Machines/` ([23](23-sessioni-remote.md)): **Macchina** del Progetto, `SSHConnection` (un ControlMaster per Macchina), `HostKeyGate` sopra `~/.ssh/known_hosts`, `MachineShell` con `LocalShell` e `SSHShell`. Git, worktree, Terminale, server e Sandbox passano da `MachineShell`: il resto di Bubo non sa se il Progetto è locale.
- `Cloud/TeleportController` ([23](23-sessioni-remote.md)): "Porta in Bubo" in una copia isolata.
- **In arrivo** ([24](24-multiplayer.md)): elenco statico nel bundle in Impostazioni › Aggiornamenti (27), aggiornato a ogni release.

Moduli per feature: `BuboRemote` (target iOS), `RemoteKit`, `Remote/`, `Settings/RemotePane` (21), `Machines/`, `Cloud/`, `Settings/MachinesPane` (23).

## Ordine di implementazione (feature 21, 23, 24)

In fondo alla coda, dopo tutte le altre. Prima la 21, poi la 23; la 24 è in v2. I passi rimandano all'`Ordine di costruzione` di ogni spec.

1. **21 Cancello di latenza** (passo 1), con una persona: CloudKit con Developer ID e 100 push misurate. Serve il lavoro umano sugli account della 27 ([#220](https://github.com/mgiuditta/bubo/issues/220)). Ticket: [#244](https://github.com/mgiuditta/bubo/issues/244).
2. **21 Telecomando** (passi 2–6): accoppiamento, Sessioni e Battito, Richieste, Rispondi/Domanda/Ferma, notifiche passive e stop. Dopo 05, 06, 09, 18 e 19. Ticket: [#245](https://github.com/mgiuditta/bubo/issues/245), [#246](https://github.com/mgiuditta/bubo/issues/246), [#247](https://github.com/mgiuditta/bubo/issues/247), [#248](https://github.com/mgiuditta/bubo/issues/248), [#249](https://github.com/mgiuditta/bubo/issues/249).
3. **23 Cancello SSH** (passo 1), con un host Linux reale. Può partire in parallelo alla 21 appena c'è il ponte. Ticket: [#250](https://github.com/mgiuditta/bubo/issues/250).
4. **23 Macchina, `claude` sull'host, git remoto, caduta** (passi 2–5). Dopo 01, 02, 14 (copia a specchio), 15 (Terminale) e 26. Ticket: [#251](https://github.com/mgiuditta/bubo/issues/251), [#252](https://github.com/mgiuditta/bubo/issues/252), [#253](https://github.com/mgiuditta/bubo/issues/253), [#254](https://github.com/mgiuditta/bubo/issues/254).
5. **23 Terminale, Anteprima, Sandbox, Automazioni remote e Porta in Bubo** (passi 6–8). Dopo 15, 19 e 22. Ticket: [#255](https://github.com/mgiuditta/bubo/issues/255), [#256](https://github.com/mgiuditta/bubo/issues/256), [#257](https://github.com/mgiuditta/bubo/issues/257).
6. **24 In arrivo**: la sezione in Impostazioni › Aggiornamenti, subito dopo Sparkle nell'app ([#222](https://github.com/mgiuditta/bubo/issues/222)); può uscire prima della 21. Ticket: [#258](https://github.com/mgiuditta/bubo/issues/258). La 24 vera è in v2: ordine qui sotto.

## Architettura comune (feature 24, v2)

Stesse regole delle 21 e 23: nessun server né relay di Bubo, solo canali dell'utente, ogni turno con l'account di chi lo manda, credenziali mai lette né condivise. Pezzi condivisi nuovi:

- `DeliveryKit` ([24](24-multiplayer.md)): formato `.bubo` (intestazione in chiaro, HPKE auth P-256 a pezzi), codice di verifica del Biglietto. Scelta nell'[ADR 0008](../adr/0008-consegna-come-file-hpke-verso-una-macchina.md).
- `Deliveries/` ([24](24-multiplayer.md)): `MachineKey` (Secure Enclave), `TicketStore`, `TranscriptCleaner` e `SecretScanner` (codice puro), `BranchBundler`, `DeliveryBuilder`, `DeliveryOpener`. Legge dalla copia a specchio (14) e crea Bozze (17); una Sessione consegnata riparte con `resume` anche su una Macchina remota (23).
- `Team/` ([24](24-multiplayer.md)): `TeamResourceReader` su `.bubo/`, `TrustLedger` con l'hash accettato per voce, sopra `Permissions/TrustGate` (05) e `Automations/` (19). Scelta nell'[ADR 0009](../adr/0009-risorse-di-squadra-con-fiducia-per-voce.md).

Moduli per feature: `BuboQuickLook` (estensione), `Settings/DeliveriesPane`, fogli di Consegna, ricezione, errori e Biglietto, `Team/TeamResourcesSheet`.

## Ordine di implementazione (feature 24, v2)

Dopo la v1, tranne il cancello, che non tocca l'app e può partire subito. Consegna e Risorse di squadra sono indipendenti. I passi rimandano all'`Ordine di costruzione` della spec.

1. **24 Cancello** (passo 1), con una persona: due Mac, due account di organizzazioni diverse, ripresa di una Sessione ripulita e HPKE auth nel Secure Enclave. Ticket: [#274](https://github.com/mgiuditta/bubo/issues/274).
2. **24 Consegna** (passi 2–5): Biglietto e tipo `.bubo`, pulizia e scanner, foglio di Consegna, apertura e Bozza. Dopo 1, 01, 14, 17 e gli entitlement della 27. Ticket: [#275](https://github.com/mgiuditta/bubo/issues/275), [#276](https://github.com/mgiuditta/bubo/issues/276), [#277](https://github.com/mgiuditta/bubo/issues/277), [#278](https://github.com/mgiuditta/bubo/issues/278).
3. **24 Risorse di squadra** (passi 6–7): regole, poi Automazioni. Dopo 05 con la fiducia del repo decisa ([#266](https://github.com/mgiuditta/bubo/issues/266)) e 19. Ticket: [#279](https://github.com/mgiuditta/bubo/issues/279), [#280](https://github.com/mgiuditta/bubo/issues/280).
