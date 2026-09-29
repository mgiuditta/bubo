# Feature di Bubo: stato

Obiettivo: per ogni feature, battere il miglior concorrente con criteri misurabili. Ogni feature ha un file `NN-nome.md` con ricerca, mappa e specifica "migliore di".

Mappa wayfinder delle feature 1–6: [Bubo — feature 1–6: base competitiva](https://github.com/mgiuditta/bubo/issues/11). Si costruisce sopra [Bubo — fase 1 e 2: fondamenta e Orb](https://github.com/mgiuditta/bubo/issues/1).

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
| 08 | Voce: wake word, dettatura in streaming, risposta parlata, interruzione | da fare | |
| 09 | Integrazione Finder e sistema | da fare | |
| 10 | Router multi-modello con scelta spiegata e override | da fare | |
| 11 | Galassia 3D del repo con agenti e diff in vetro | da fare | |
| 12 | Secondo cervello su Obsidian | da fare | |
| 13 | Memoria per progetto e riassunto di fine sessione | da fare | |
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
1. **Ponte agente minimo**: una Conversazione in una cartella, streaming nell'HUD. Serve a 1, 3, 4, 5, 6.
2. **03 Account e uso** e **04 configurazione `~/.claude`**: poco codice, sbloccano l'uso reale.
3. **01 Sessioni in worktree**.
4. **06 Attività, notifiche e badge** (Vista Colonna per prima).
5. **05 Permessi**.
6. **02 Revisione e merge**.
