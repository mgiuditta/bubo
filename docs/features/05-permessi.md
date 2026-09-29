# 05 — Permessi in GUI con regole "consenti sempre" per progetto

Ticket: [#16](https://github.com/mgiuditta/bubo/issues/16) · Mappa: [#11](https://github.com/mgiuditta/bubo/issues/11) · Ricerca del 2026-09-29.

Versioni verificate: `@anthropic-ai/claude-agent-sdk` **0.3.284**, che include Claude Code **2.1.284** (build del 2026-09-28). Le firme sotto vengono da `sdk.d.ts` di quel pacchetto.

## Ricerca

### Claude Code ufficiale: CLI e app desktop (tab Code)

**Come funziona**
- Modalità: Manual (`default`), Accept edits, Plan, Auto, Bypass. `dontAsk` esiste solo nella CLI. Nell'app desktop si cambia dal selettore accanto al tasto invio (`Cmd+Shift+M`). La modalità scelta viene **ricordata per cartella**, tranne Plan [D1].
- Da Claude Code v2.1.283 la modalità di partenza è **auto** nelle sessioni interattive da terminale e in VS Code [D3].
- Il prompt della CLI offre: Sì una volta, "Sì, e non chiedere più", No. Con Tab si aggiunge un commento alla risposta. Con No senza commento il turno si ferma [D2].
- "Non chiedere più" vale per sempre per ogni repository e comando nel caso di Bash, WebFetch e WebSearch. Per le modifiche ai file vale **solo fino a fine sessione** [D2].
- La regola viene salvata in `.claude/settings.local.json` alla radice del repo, anche dai worktree (da v2.1.211) [D2].
- Il prompt offre "non chiedere più" solo se può mostrare tutto ciò che la regola consentirebbe. Altrimenti c'è solo l'approvazione singola [D2].
- Con un comando composto (`git status && npm test`) salva una regola per ogni sottocomando, fino a 5 [D2].
- In auto mode c'è un classificatore. Blocca per default force push, `git reset --hard`, `terraform destroy`, `curl | bash` e altro. Dopo 3 blocchi di fila o 20 in totale torna a chiedere all'utente [D3].

**Cosa piace**
- Regole leggibili e condivise tra CLI, IDE e app desktop: stessi file `settings*.json` [D1].
- Auto mode riduce molto i prompt. Anthropic dichiara che gli utenti approvano il **93%** dei prompt: la maggior parte dei prompt non protegge davvero [B1].

**Cosa lamentano**
- Regole in `settings.local.json` ignorate: il prompt riappare e propone di aggiungere una regola già presente (issue aperta, 42 commenti) [G1].
- Regole di progetto che sembrano "sostituire" quelle globali invece di sommarsi (confusione su user vs local) [G2].
- "Consenti tutte le modifiche" non rispettato durante la sessione [G3].
- Nell'app desktop i prompt di permesso sono stati coperti da un overlay (bug chiuso) [G4].
- Lunga serie di CVE su bypass del prompt: iniezione via `sed`, `find`, `echo`, `rg`, symlink, `cd` [S1]. Una in particolare: un repo malevolo poteva mettere `defaultMode: bypassPermissions` nel suo `.claude/settings.json` e saltare il dialogo di fiducia (CVE-2026-33068) [S2].

**Cosa manca**
- L'app desktop **non ha `/permissions`**: risponde "isn't available in this environment". Per gestire le regole bisogna modificare i file a mano [D1].
- Non esistono in desktop `--allowedTools`/`--disallowedTools` per sessione [D1].
- Nessuna vista "cosa è stato approvato automaticamente e perché" in GUI.

### Conductor

**Come funziona**
- Più agenti (Claude Code, Codex, Cursor, OpenCode) in workspace isolati. Modalità documentate: Plan e Fast [C1].
- L'approvazione degli strumenti è arrivata nella 0.41.0 **solo come impostazione enterprise**, da attivare scrivendo al supporto. Per tutti gli altri gli agenti girano quindi senza prompt [C2].

**Cosa piace**: velocità, zero interruzioni, Plan mode con approvazione del piano e feedback [C2].

**Cosa lamentano / cosa manca**: nessuna regola "consenti sempre" in GUI per l'utente normale. Nessuna evidenza di gestione delle azioni distruttive oltre a quella di Claude Code.

### Nimbalyst (ex Crystal)

**Come funziona**
- Al primo uso in un progetto chiede un livello di autonomia: **Agent-verified** (consigliato, usa il revisore automatico del fornitore), **Allow everything**, **Allow edits only**, **Ask every time** [N1].
- Il prompt in linea offre quattro scelte: **Deny**, **Allow Once**, **Session** (il pattern mostrato fino alla chiusura), **Always** (salva il pattern in `.claude/settings.local.json`) [N1].
- Legge e scrive gli stessi tre file della CLI: `.claude/settings.json`, `.claude/settings.local.json`, `~/.claude/settings.json` [N1].
- `~/.ssh` e `~/.aws` sono sempre bloccati [N1].
- Dalla v0.78.1 le approvazioni "richieste" di Claude sono **Deny per default** e permettono solo l'approvazione singola [N2]. È il campo `defaultToNo`/`suppressAlwaysAllowRule` dell'SDK (vedi sotto).

**Cosa piace**: mostra il pattern che salverà prima di salvarlo. Compatibilità piena con la CLI. Barra menu con lo stato delle sessioni (bloccata, finita) [N2].

**Cosa lamentano**
- Crystal girava con `--dangerously-skip-permissions`. Un utente ha chiesto di poterlo togliere perché "tra `terraform plan` e `terraform apply` la linea è sottile". L'interruttore c'era, ma nascosto nella schermata di creazione del progetto [N3].
- La modalità "Full Access" tornava da sola a "Workspace" [N4].
- Worktree aperti tramite symlink non ereditavano i permessi del progetto: **ogni** chiamata chiedeva di nuovo l'approvazione (corretto in 0.76.3) [N2].

**Cosa manca**: nessun dato pubblico su tempi di decisione.

### opcode (ex Claudia)

**Come funziona**: GUI Tauri. Esiste una pagina "Permissions / Allow Rules", ma le sessioni girano con `--dangerously-skip-permissions` [O1].

**Cosa lamentano**
- "Claudia modifica i file senza chiedere il permesso", mentre la CLI chiede sempre. Un commento: "tutte le sessioni che OpCode avvia usano `--dangerously-skip-permissions`, molto insicuro" [O1].
- Richiesta aperta di una modalità di modifica manuale: le regole di deny impediscono l'azione ma non generano un prompt [O2].

**Cosa manca**: un vero flusso di approvazione.

### Sculptor (Imbue)

**Come funziona**: ogni agente gira in un container Docker. Il repo locale non cambia finché non si fa Pull dal container [I1].

**Cosa piace**: "usare Claude senza compromessi sulla sicurezza e senza fastidiosi prompt di permesso" (autore, Show HN). Un utente: "lascia Claude andare fuori controllo in sicurezza dentro un container" [I2].

**Cosa manca**: nessun controllo per singola azione. La sicurezza viene tutta dall'isolamento.

### Superset

**Come funziona**
- Nel pannello chat gli agenti possono chiedere l'approvazione di uno strumento o la revisione di un piano, in linea [P1].
- Il preset terminale di Claude nel codice attuale è `claude --dangerously-skip-permissions` (anche resume e fork) [P2]. Esiste una migrazione che "ripristina i default YOLO" per chi li aveva prima dei default più sicuri [P3].

**Cosa manca**: nessuna gestione delle regole "consenti sempre" documentata in GUI.

### CodeAgentSwarm, ClaudeGUI, Agentic Stack Desktop

- **CodeAgentSwarm**: esistono solo sito e landing ([repo](https://github.com/arturogj92/codeagentswarm-site)). Il sito ha risposto 429 e non ho trovato documentazione pubblica sui permessi.
- **ClaudeGUI** ([Rostmen/ClaudeGUI](https://github.com/Rostmen/ClaudeGUI)): gestore di sessioni con 2 stelle. Nessuna funzione di permesso documentata.
- **Agentic Stack Desktop**: nessuna fonte primaria trovata.

Nessuno di questi pubblica numeri misurabili (clic, tempi, RAM) sui permessi.

### Sintesi del panorama

| Prodotto | Default | "Consenti sempre" in GUI | Scrive nei file della CLI | Distruttivo evidenziato |
|---|---|---|---|---|
| Claude Code desktop | auto/manual | sì, dal prompt; niente gestione regole | sì | sì (classificatore, percorsi critici) |
| Nimbalyst | scelta al primo uso | sì: Once / Session / Always | sì, `settings.local.json` | revisore del fornitore + blocchi fissi |
| Conductor | senza prompt | no (enterprise) | — | no |
| opcode | skip-permissions | no | — | no |
| Superset | skip nel terminale, prompt in chat | non documentato | — | no |
| Sculptor | container, senza prompt | no | — | isolamento |

Nessuno misura o pubblica il tempo di decisione. Nessuno ha un pannello per vedere, modificare e revocare le regole in GUI con la loro origine. Questo è lo spazio libero.

## API dell'Agent SDK

Tutte le firme vengono da `sdk.d.ts` 0.3.284.

### Callback `canUseTool`

```ts
type CanUseTool = (toolName: string, input: Record<string, unknown>, options: {
  signal: AbortSignal;
  suggestions?: PermissionUpdate[];   // regole pronte per "consenti sempre"
  blockedPath?: string;               // percorso fuori dalle cartelle consentite
  mcpServer?: { name: string; source: string }; // 'sdk' | 'plugin' | 'user' | 'project' | ...
  decisionReason?: string;            // perché si chiede
  title?: string;                     // frase completa, es. "Claude wants to read foo.txt"
  displayName?: string;               // es. "Read file", per pulsanti
  description?: string;               // sottotitolo leggibile
  defaultToNo?: boolean;              // apri su "No", niente scorciatoia a un tasto per approvare
  suppressAlwaysAllowRule?: boolean;  // NON offrire "consenti sempre"
  toolUseID: string;
  agentID?: string;                   // se viene da un subagente
  requestId: string;
  matchedAskRule?: { source: string; toolName: string; ruleContent?: string };
}) => Promise<PermissionResult | null>;
```

- `title`, `displayName` e `description` sono il testo che la CLI mostrerebbe. Vanno usati come testo principale del pannello [T1].
- Il nome del server MCP è testo non fidato: va mostrato con escape. Le decisioni di fiducia vanno prese su `source` [T1].
- La callback può restare in attesa **senza limite**. Per attese lunghe la doc consiglia un hook `PreToolUse` con decisione `defer` [D5].
- Restituire `null` solo se la risposta è già stata inviata per altra via. Altrimenti lo strumento resta bloccato per sempre [T1].

### Risultato

```ts
type PermissionResult =
  | { behavior: 'allow'; updatedInput?: Record<string, unknown>;
      updatedPermissions?: PermissionUpdate[]; toolUseID?: string;
      decisionClassification?: 'user_temporary' | 'user_permanent' | 'user_reject' }
  | { behavior: 'deny'; message: string; interrupt?: boolean; toolUseID?: string;
      decisionClassification?: ... };
```

- `updatedInput` permette di approvare con modifiche. Claude non viene avvisato della modifica [D5].
- Con `deny`, Claude legge `message` e cambia strada. Con `interrupt: true` il turno si ferma.
- `decisionClassification` serve alla telemetria: `user_permanent` per "consenti sempre" [T1].

### Aggiornamenti di permesso e destinazioni

```ts
type PermissionUpdate =
  | { type: 'addRules' | 'replaceRules' | 'removeRules'; rules: PermissionRuleValue[];
      behavior: 'allow' | 'deny' | 'ask'; destination: PermissionUpdateDestination }
  | { type: 'setMode'; mode: PermissionMode; destination: PermissionUpdateDestination }
  | { type: 'addDirectories' | 'removeDirectories'; directories: string[];
      destination: PermissionUpdateDestination };

type PermissionRuleValue = { toolName: string; ruleContent?: string };
type PermissionUpdateDestination =
  'userSettings' | 'projectSettings' | 'localSettings' | 'session' | 'cliArg';
type PermissionMode = 'default' | 'acceptEdits' | 'bypassPermissions' | 'plan' | 'dontAsk' | 'auto';
```

| Destinazione | File | Chi la vede |
|---|---|---|
| `session` | nessuno, in memoria | solo questa sessione |
| `localSettings` | `.claude/settings.local.json` | io, in questo progetto (non va in git) |
| `projectSettings` | `.claude/settings.json` | tutto il team, via git |
| `userSettings` | `~/.claude/settings.json` | io, in tutti i progetti |
| `cliArg` | nessuno | come un flag `--allowedTools` |

- Per "consenti sempre" la doc ufficiale filtra i `suggestions` con `destination === "localSettings"` e li rimanda in `updatedPermissions` [D5].
- Una regola in `localSettings` viene letta anche dalla CLI e dall'app desktop: compatibilità piena.

### Altre leve

- Opzioni di `query()`: `permissionMode`, `allowedTools`, `disallowedTools`, `allowDangerouslySkipPermissions` (obbligatoria per bypass), `permissionPromptToolName`, `permissionPrompts: 'host' | 'none'`, `settingSources` [T1].
- `settingSources` omesso = carica `user`, `project` e `local`, come la CLI. `[]` = isolamento totale [T1].
- `query.setPermissionMode(mode)` cambia modalità a sessione aperta (solo input in streaming) [T1].
- `query.setMcpPermissionModeOverride(server, 'default' | 'auto' | null)` può solo **stringere** i permessi di un server MCP [T1].
- Hook `PermissionRequest` con `permission_suggestions`: utile per inviare notifiche quando una sessione aspetta [T1][D5].
- Richiesta di controllo `list_permission_rules`: restituisce tutte le regole attive con `source`, `rule` testuale, `description` leggibile ed `editability` (`persistent` | `session` | `readonly`). È ciò che mostra `/permissions` [T1]. Nel `.d.ts` 0.3.284 non ho trovato un metodo pubblico di `Query` che la esponga: da verificare.
- Quando `canUseTool` coesiste con `bypassPermissions` o con un `allowedTools` senza specificatore, l'SDK emette l'avviso `CLAUDE_SDK_CAN_USE_TOOL_SHADOWED` [D4].

### Ordine di valutazione

1. Hook `PreToolUse`: un hook può negare. Un "allow" dell'hook **non** salta deny e ask.
2. Regole `deny`: bloccano anche in bypass.
3. Regole `ask`: vanno alla callback anche in bypass.
4. Modalità: bypass approva, `acceptEdits` approva le modifiche ai file, `plan` manda le scritture alla callback.
5. Regole `allow`, più le azioni che uno strumento approva da solo (letture nella cartella di lavoro, comandi Bash di sola lettura).
6. `canUseTool`. In `dontAsk` si nega senza chiamarla [D4].

Precedenza: deny, poi ask, poi allow. Vince la prima corrispondenza. La specificità non conta: `Bash(aws *)` in deny batte `Bash(aws s3 ls)` in allow [D2].

### Sintassi delle regole

- Forma `Tool` o `Tool(specificatore)`. `Bash` e `Bash(*)` sono equivalenti [D2].
- Bash: `*` va dopo il sottocomando. `Bash(git log *)` consente solo `git log`, `Bash(git *)` consente tutto git. `Bash(ls *)` non copre `lsof`, `Bash(ls*)` sì. `Bash(npm run test:*)` equivale a `Bash(npm run test *)`: `:*` è riconosciuto solo alla fine [D2].
- Il prompt salva la forma con lo spazio (`Bash(npm run *)`) [D2].
- Wrapper rimossi prima del confronto: `timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, `noglob`, `xargs` senza flag [D2].
- **Non** sono rimossi: `npx`, `docker exec`, `direnv exec`, `devbox run`, `mise exec`. `Bash(devbox run *)` consente anche `devbox run rm -rf .` [D2].
- Una regola Bash non è un confine di sicurezza: `Bash(rm *)` non ferma `/bin/rm` o `bash -c 'rm ...'` [D2].
- Read/Edit usano la sintassi gitignore: `//percorso` assoluto, `~/percorso` home, `/percorso` relativo al file di impostazioni, `percorso` relativo alla cartella corrente. `Edit(...)` copre anche Write e NotebookEdit. `Write(...)` come regola di percorso non viene mai consultata [D2].
- WebFetch: `WebFetch(domain:example.com)`, `WebFetch(domain:*.example.com)` [D2].
- MCP: `mcp__server`, `mcp__server__*`, `mcp__server__tool`. Le regole allow con glob sono accettate solo dopo `mcp__<server>__` [D2].
- Parametri (solo deny e ask): `Agent(model:opus)`, `Bash(run_in_background:true)` [D2].

### Compatibilità con i file della CLI

- Stessi tre file, stessa sintassi, stessa precedenza. Le regole scritte da Bubo in `localSettings` valgono subito anche nella CLI.
- **Attenzione, fiducia del workspace**: le regole `permissions.allow` e `additionalDirectories` in `.claude/settings.json` di progetto **non vengono usate** in una sessione SDK se la cartella non è mai stata dichiarata fidata. Stampano l'avviso "this workspace has not been trusted". Le regole deny e ask valgono sempre [D2].
- La fiducia si imposta con `projects["<path>"].hasTrustDialogAccepted = true` in `~/.claude.json` [D2].
- `settings.local.json` non tracciato in git viene applicato anche in SDK senza dialogo di fiducia [D2].
- **Worktree**: la CLI legge e scrive `settings.local.json` alla radice del repo principale. Le sessioni SDK lo leggono dalla **cartella di lavoro**, in tutte le versioni [D2]. Una regola salvata in un worktree di Bubo potrebbe quindi non valere negli altri. Da provare con un prototipo (vedi Rischi).

## Azioni distruttive

### Cosa Claude Code tratta già come speciale

- **Percorsi critici** (`rm`/`rmdir`): radice, cartelle di primo livello (`/usr`, `/etc`), home, cartella di lavoro e i suoi genitori, glob sotto cartelle aggiuntive, `rm -rf "$DIR"/*` senza guardia, `rm -rf "$(pwd)"`. **Nessuna regola allow e nessun hook allow li approva mai**. In SDK con `auto` vengono negati senza chiedere. Nelle altre modalità arrivano alla callback [D3].
- **Percorsi protetti** (scrittura): `.git`, `.claude` (tranne `.claude/worktrees`), `.vscode`, `.idea`, `.husky`, `.devcontainer`, `.gitconfig`, `.zshrc`, `.bashrc`, `.npmrc`, `.mcp.json`, `.claude.json` e altri. Le regole allow non li pre-approvano. In `default` e `acceptEdits` chiedono sempre [D3].
- **Classificatore auto mode**, bloccati per default: download ed esecuzione (`curl | bash`), invio di dati sensibili fuori, deploy e migrazioni in produzione, cancellazioni di massa su cloud, force push, `git reset --hard`, `git checkout -- .`, `git clean -fd`, `git stash drop`, `git commit --amend` su commit non creati in sessione, `terraform destroy`, merge di PR non approvate, scrittura di credenziali nel transcript, `rm -rf` su variabile non risolta [D3].
- L'SDK segnala all'host quando non va offerto "consenti sempre" (`suppressAlwaysAllowRule`) e quando il prompt deve aprirsi su "No" (`defaultToNo`) [T1].

### Classi proposte per Bubo

Da affinare nella specifica. Sono cinque livelli, ognuno con un trattamento visivo:

1. **Lettura**: nessun prompt (già così nell'SDK).
2. **Modifica reversibile** (edit di file tracciati in git, `npm test`): prompt compatto, "consenti sempre" disponibile.
3. **Rete / esterno** (WebFetch nuovo dominio, `git push`, MCP con `source` non `sdk`): prompt con dominio o destinazione in evidenza.
4. **Distruttivo locale** (cancellazioni, `git reset --hard`, `git clean`, scrittura su percorsi protetti, file non tracciati): colore d'allarme, focus su "No", niente "consenti sempre", conteggio di file e righe toccate.
5. **Irreversibile esterno** (force push, `terraform destroy`, invio di messaggi, modifiche massive al vault Obsidian, dal brief): come il livello 4, più una conferma esplicita (es. tenere premuto o scrivere il nome).

Il brief lo chiede in modo esplicito: "Nessuna azione distruttiva (cancellare file, inviare messaggi, modifiche massive al vault) senza conferma esplicita."

### Come evidenziarla

- Bash: mostrare il comando intero con evidenziazione della sintassi, il sottocomando pericoloso in rosso e la cartella in cui gira.
- Edit/Write: mostrare il diff, non solo il percorso. Collegamento con la feature 02 (revisione del diff).
- Cancellazioni: elencare i file che verrebbero rimossi (anteprima con `git status` o lista del glob) e se sono tracciati in git.
- Mostrare **sempre** la regola esatta che "consenti sempre" salverebbe e dove (file). Nimbalyst lo fa, la CLI lo fa, nessuna GUI lo mostra con la destinazione.

## Il meglio da battere

Il riferimento migliore oggi è **Nimbalyst**: quattro scelte (Deny, Once, Session, Always), pattern visibile prima di salvarlo, scrittura in `.claude/settings.local.json` compatibile con la CLI, Deny di default sulle approvazioni "richieste". Claude Code desktop ha il motore migliore (percorsi critici, classificatore), ma nessuna gestione delle regole in GUI.

Criteri misurabili candidati:
- **Clic per decidere**: 1 clic o 1 tasto per Once, Always e Deny su un'azione normale. 0 scorciatoie a un tasto per approvare un'azione di livello 4–5.
- **Tempo dal prompt alla decisione**: mediana misurata in-app sotto i 3 s per azioni di livello 1–3. Obiettivo sul tasso di prompt: sotto 1 prompt ogni 10 chiamate a strumenti dopo la prima settimana su un progetto.
- **Gestione delle regole**: vedere, modificare e revocare ogni regola con la sua origine (user/project/local/session) in ≤ 2 clic dal pannello. Oggi l'app desktop non lo permette.
- **Compatibilità**: il 100% delle regole scritte da Bubo viene rispettato dalla CLI, e il 100% di quelle scritte dalla CLI da Bubo. Test automatico su `settings*.json`.
- **Sessioni parallele**: con N sessioni in attesa, badge e notifica per ciascuna. 0 approvazioni perse o associate alla sessione sbagliata.

## Rischi e casi limite

- **Fiducia del workspace in SDK**: le regole allow di `.claude/settings.json` non valgono se la cartella non è fidata. Bubo deve mostrare un suo dialogo di fiducia che elenca queste regole, e decidere se scrivere `hasTrustDialogAccepted` in `~/.claude.json`, un file di Claude Code che Bubo non possiede. Le CVE sul dialogo di fiducia (CVE-2026-33068, CVE-2026-40068) mostrano che è un punto d'attacco reale [S1][S2].
- **Worktree**: in SDK `settings.local.json` si legge dalla cartella di lavoro, non dalla radice del repo. Con la feature 01 (sessioni in worktree), "consenti sempre" potrebbe valere solo in un worktree. Nimbalyst ha avuto lo stesso bug [N2]. Serve un prototipo: salvare in un worktree e verificare in un altro. Possibile soluzione: scrivere la regola nella radice principale oppure passare `cwd` alla radice.
- **Regole troppo larghe**: un "consenti sempre" su `Bash(npx *)` o `Bash(docker exec *)` apre qualsiasi comando [D2]. Bubo dovrebbe usare i `suggestions` dell'SDK così come arrivano e rifiutare di generare pattern più larghi.
- **Regole come falsa sicurezza**: deny su `Bash(rm *)` non ferma `/bin/rm` [D2]. Per garanzie vere servono hook `PreToolUse` o la sandbox (feature 22).
- **Callback che non risponde mai**: nessun timeout. Se l'utente chiude il pannello o l'app, la sessione resta bloccata [T1][D5]. Serve uno stato "in attesa" persistente e una notifica (feature 06).
- **Subagenti**: `agentID` distingue le richieste dei subagenti. Il pannello deve dire quale agente chiede.
- **MCP non fidati**: il nome del server è testo controllato da terzi (possibile spoofing). Usare `mcpServer.source` per la fiducia [T1].
- **Modalità bypass**: `allowedTools` non limita bypass [D4]. In bypass i subagenti ereditano tutto. Bubo dovrebbe rendere bypass difficile da attivare e ben visibile (colore dell'Orb?).
- **Auto mode in SDK**: le rimozioni di percorsi critici vengono negate senza chiedere [D3]. Il classificatore ha costi e latenza. Anthropic pubblica un tasso di falsi negativi del 17% sulle azioni "troppo zelanti" reali [B1].
- **Classificatore e confini detti a voce**: i limiti espressi in conversazione ("non fare push") possono perdersi con la compattazione del contesto [D3]. Con la voce (feature 08) è un rischio in più.
- **Approvazione vocale**: se Bubo accetta "sì" a voce, un falso positivo della wake word potrebbe approvare. Per i livelli 4–5 niente approvazione solo vocale.
- **File scritti a mano con errori**: se un `settings*.json` non si legge, le sue regole vengono saltate. `list_permission_rules` riporta `errors` [T1]. Bubo deve mostrarli.
- **Managed settings**: con `allowManagedPermissionRulesOnly` le regole utente sono ignorate (`notInEffect`) [T1]. Il pannello deve mostrarle come inattive.

## Mappa

_da definire_

## Specifica "migliore di"

_da definire_

## Fonti

**Documentazione Anthropic**
- [D1] Claude Code, Desktop application: https://code.claude.com/docs/en/desktop
- [D2] Claude Code, Configure permissions: https://code.claude.com/docs/en/permissions
- [D3] Claude Code, Choose a permission mode: https://code.claude.com/docs/en/permission-modes
- [D4] Agent SDK, Configure permissions: https://code.claude.com/docs/en/agent-sdk/permissions
- [D5] Agent SDK, Handle approvals and user input: https://code.claude.com/docs/en/agent-sdk/user-input
- [T1] Tipi del pacchetto npm `@anthropic-ai/claude-agent-sdk@0.3.284`, file `sdk.d.ts` (CanUseTool, PermissionResult, PermissionUpdate, SDKPermissionRuleEntry, Options): https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk
- [B1] Anthropic Engineering, How we built Claude Code auto mode: https://www.anthropic.com/engineering/claude-code-auto-mode

**Sicurezza**
- [S1] Advisory di sicurezza di Claude Code: https://github.com/anthropics/claude-code/security/advisories
- [S2] CVE-2026-33068, Workspace Trust Dialog Bypass via Repo-Controlled Settings File: https://github.com/advisories/GHSA-mmgp-wc2j-qcv7

**Issue di Claude Code**
- [G1] #6850 settings.local.json allow not working: https://github.com/anthropics/claude-code/issues/6850
- [G2] #17017 Project-level permissions replace global: https://github.com/anthropics/claude-code/issues/17017
- [G3] #9348 "Allow all edits" not respected: https://github.com/anthropics/claude-code/issues/9348
- [G4] #58496 Desktop overlay covers permission prompts: https://github.com/anthropics/claude-code/issues/58496

**Concorrenti**
- [C1] Conductor, Agent modes: https://www.conductor.build/docs/concepts/agent-modes
- [C2] Conductor, changelog 0.41.0 "Tool Approval": https://www.conductor.build/changelog/0.41.0-tool-approval-codex-plan-mode-beta
- [N1] Nimbalyst, Permissions and Safety: https://docs.nimbalyst.com/open-safe-private-secure/permissions-and-safety
- [N2] Nimbalyst, release notes (v0.76.3, v0.78.1, v0.78.5): https://github.com/nimbalyst/nimbalyst/releases
- [N3] Crystal #178 Allow running without skip permissions: https://github.com/stravu/crystal/issues/178
- [N4] Crystal #221 "Full Access" switches back to "Workspace": https://github.com/stravu/crystal/issues/221
- [O1] opcode #292 claudia changing files without asking: https://github.com/winfunc/opcode/issues/292
- [O2] opcode #340 Manual edit mode: https://github.com/winfunc/opcode/issues/340
- [I1] Sculptor: https://imbue.com/sculptor/
- [I2] Show HN: Sculptor: https://news.ycombinator.com/item?id=45427697
- [P1] Superset, Agent integration: https://docs.superset.sh/agent-integration
- [P2] Superset, `builtin-terminal-agents.ts`: https://github.com/superset-sh/superset/blob/main/packages/shared/src/builtin-terminal-agents.ts
- [P3] Superset, `agent-permissions-migration.ts`: https://github.com/superset-sh/superset/blob/main/packages/shared/src/agent-permissions-migration.ts
