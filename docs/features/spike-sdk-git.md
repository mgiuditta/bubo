# Spike: verifiche sull'Agent SDK e su git

Ticket: [#24](https://github.com/mgiuditta/bubo/issues/24) · Mappa: [#11](https://github.com/mgiuditta/bubo/issues/11) · Misure del 2026-09-29.

Ambiente: `@anthropic-ai/claude-agent-sdk` **0.3.284** con il CLI incluso **2.1.284**, Node 24.18, git 2.50.1 (Apple), macOS 26 su APFS. Login dell'utente già presente, usato solo avviando il CLI tramite l'SDK. Nessun file di credenziali, token o voce del Portachiavi letto. Nessun file scritto in `~/.claude` o `~/.claude.json`. Repo finti nello scratchpad. Chiamate al modello: 2 turni con `haiku`, `maxTurns: 1`. Tutte le altre prove girano **senza turno di modello** (prompt in streaming mai inviato, solo richieste di controllo).

Script in [`spike/`](spike/). Si lanciano con `npm i` e `node <script>` in quella cartella.

## Risposte in breve

| # | Domanda | Risposta |
|---|---|---|
| 1 | `session_state_changed` senza variabili? | **No.** Serve `CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS=1` nell'`env` del processo figlio. |
| 2 | `projectConfigRoot` in un worktree | **Sì, funziona.** Skill, agent, hook e regole `localSettings` arrivano dal checkout principale; gli hook girano con cartella = checkout principale. Anche senza l'opzione il CLI ripiega sul checkout principale, ma solo per le parti che mancano nel worktree. |
| 3 | Cartella non fidata | **Vero, in parte.** Ignorate: `allow` e `additionalDirectories` di `.claude/settings.json` (versionato). Valgono comunque: `settings.local.json` ignorato da git, hook, skill, agent. La fiducia di un worktree è quella del checkout principale. Senza scrivere file: Bubo mostra un suo dialogo e passa le regole con le opzioni `settings` / `allowedTools` / `additionalDirectories`. |
| 4 | Quota senza Sessione attiva | **Sì.** `usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET({ skipBehaviors: true })` su un `query()` senza prompt: 5 ore e settimanale con reset, in 1,2 s, costo 0. `claude auth status` non ha la quota. API sperimentale. |
| 5 | Tempo `git worktree add` + clonefile, 1 GB | `worktree add` **0,10–0,13 s**. `cp -Rc` (clonefile per file) **14,6–15,3 s**. `clonefile(2)` sull'intera cartella **1,06–1,28 s**. Usare la chiamata unica. |

## 1. `session_state_changed`

Script: [`probe-state.mjs`](spike/probe-state.mjs). Un turno "Rispondi solo: ok", due volte.

Senza variabile (estratto):

```
1006ms system:init
1461ms rate_limit_event status=allowed type=five_hour
2513ms assistant
2542ms result:success
```

Nessun `session_state_changed`.

Con `CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS=1`:

```
 847ms session_state_changed:running
 991ms system:init
1477ms rate_limit_event status=allowed type=five_hour
2338ms assistant
2371ms rate_limit_event status=allowed type=five_hour
2384ms result:success
2384ms session_state_changed:idle
```

Perché, dal codice del pacchetto:

- L'SDK imposta da solo `CLAUDE_CODE_SDK_READS_SESSION_STATE=1` (`sdk.mjs`).
- Con quella variabile il CLI emette l'evento con `sdk_host_only: true`. L'SDK lo usa per sapere quando il turno è finito, poi lo **scarta** (`if("sdk_host_only"in e&&e.sdk_host_only===!0)continue`).
- Con `CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS` il CLI emette l'evento senza quel flag, e l'SDK lo passa all'host.

Per Bubo: impostare la variabile nell'`env` passato a `query()`. `idle` arriva nello stesso millisecondo di `result`; `running` arriva prima di `init`. `requires_action` non è stato provato (serve un permesso in attesa). La variabile non è documentata: se sparisce, ripiegare su `result` come già previsto in [06](06-stato-sessioni.md).

## 2. `projectConfigRoot` nei worktree

Script: [`setup-repos.sh`](spike/setup-repos.sh), [`probe-config.mjs`](spike/probe-config.mjs). Nessun turno di modello.

Repo finto `main` con `.claude/` ignorato da git. Dentro: una skill, un agent, `settings.local.json` con una regola `allow` e un hook `SessionStart` che crea un file col nome della cartella corrente. Poi `git worktree add wt`.

| Caso | Skill | Agent | Regola `localSettings` | Hook eseguito in |
|---|---|---|---|---|
| `cwd = main` | sì | sì | sì | `main` |
| `cwd = wt`, senza opzione | sì (da `main`) | sì | sì | `wt` |
| `cwd = wt`, `projectConfigRoot = main` | sì | sì | sì | `main` |
| `cwd = wt` con una sua `.claude/skills/`, senza opzione | **solo quella del worktree** | sì (da `main`) | sì | `wt` |
| stesso, con `projectConfigRoot = main` | solo quella di `main` | sì | sì | `main` |

Cosa vuol dire:

- Il CLI 2.1.284 già ripiega sul checkout principale per le cartelle che mancano nel worktree. Ma se il branch porta una sua `.claude/skills/`, vince quella del branch, cartella per cartella.
- Con `projectConfigRoot` tutto viene dal checkout principale, qualunque cosa ci sia nel branch. È ciò che serve a Bubo: la config del Progetto non cambia con il branch della Sessione.
- Gli hook ricevono come cartella di lavoro il checkout principale (`CLAUDE_PROJECT_DIR`). Un hook che lavora sui file del worktree deve usare il `cwd` dell'input dell'hook, non la cartella corrente.
- Il CLI vieta sessioni in background e il salvataggio di workflow di progetto con `--project-config-root` (messaggi nel binario). Per Bubo non è un problema: ogni Sessione è un processo in primo piano.
- Hook e regole si leggono senza turno: `hook-ran-*` compare già all'avvio; le regole con `listPermissionRules()`.

Nota: `listPermissionRules()` esiste a runtime (`sdk.mjs`) ma non in `sdk.d.ts` 0.3.284. Idem `getHooksListing()` e `getSettings()`. Utili per la vista "cosa è caricato" di [04](04-settaggi-claude.md) e [05](05-permessi.md), ma non sono API pubbliche.

## 3. Cartella non fidata

Script: [`setup-trust-repo.sh`](spike/setup-trust-repo.sh), [`probe-trust.mjs`](spike/probe-trust.mjs). Nessun turno di modello. `~/.claude.json` **non** è stato letto né scritto: il comportamento viene dalle prove e dal codice del CLI.

Repo finto mai aperto prima, con `allow` e `additionalDirectories` in `.claude/settings.json` (versionato) e un `allow` in `.claude/settings.local.json` (ignorato da git).

Risultato di `listPermissionRules()`:

- attiva solo `Bash(echo spike-local:*)` da `localSettings`;
- `allow` e `additionalDirectories` di `settings.json` **assenti**;
- su stderr: `Ignoring 1 permissions.allow entry from .claude/settings.json: this workspace has not been trusted. Run Claude Code interactively here once and accept the trust dialog, or set projects["<path>"].hasTrustDialogAccepted: true in ~/.claude.json.`

Altri fatti misurati:

- **Hook versionati girano lo stesso.** Un hook `SessionStart` in `.claude/settings.json` di un repo mai fidato è stato eseguito all'avvio dell'SDK. Nel codice: in modalità non interattiva il CLI accetta la fiducia per la sessione (`if(Ce()){... h0(!0)`). Il filtro vale solo per `allow` e `additionalDirectories`.
- **`settings.local.json` vale** se è ignorato da git. Il codice lo filtra solo quando è versionato (`localSettingsSeenGitTracked`).
- **Worktree = checkout principale.** In un worktree di `/Users/matteo/dev/bubo` l'avviso chiede `projects["/Users/matteo/dev/bubo"]`: la chiave di fiducia è il checkout principale, non la cartella del worktree. Fidato il Progetto, sono fidate tutte le sue Sessioni.
- Dal codice (non provato): la fiducia si eredita dalle cartelle padre, ma dentro un repo git solo fino alla radice del repo.
- `CLAUDE_CODE_SANDBOXED=1` **non** toglie il filtro sulle regole `allow` (provato).

Come rendere fidata una cartella senza scrivere file dell'utente a sua insaputa:

1. **Consigliato: dialogo di Bubo + opzioni dell'SDK.** Bubo legge `.claude/settings.json` (o usa `resolveSettings()`), mostra le regole `allow`, le directory aggiuntive **e gli hook**, e chiede. Se l'utente accetta, Bubo passa le regole con `settings: { permissions: { allow: [...] } }` (provato: la regola compare con `source: flagSettings`), oppure `allowedTools`, e le directory con `additionalDirectories`. Niente scritture in `~/.claude.json`. La scelta si salva nei dati di Bubo, legata al Progetto.
2. **Terminale.** Bubo apre `claude` nella cartella del Progetto; l'utente accetta il dialogo del CLI, che scrive lui stesso `~/.claude.json`. Serve anche alla CLI fuori da Bubo.
3. **Scrittura in `~/.claude.json`** (`hasTrustDialogAccepted: true`), solo con consenso esplicito e dicendo quale file si tocca. È un file di Claude Code che Bubo non possiede: ultima scelta.

Per la sicurezza ([05](05-permessi.md)): visto che gli hook versionati girano già all'avvio, il dialogo di fiducia di Bubo va mostrato **prima** di avviare la prima Sessione su un Progetto nuovo, non solo prima di applicare le regole `allow`.

## 4. Quota senza Sessione attiva

Script: [`probe-usage.mjs`](spike/probe-usage.mjs). Nessun prompt inviato, `persistSession: false`.

`query()` con un prompt in streaming che non produce messaggi, poi `usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET({ skipBehaviors: true })`:

- risposta in **1,24 s** dall'avvio del processo, `total_cost_usd: 0`;
- `subscription_type: "max"`, `rate_limits_available: true`;
- `rate_limits.five_hour` e `seven_day` con `utilization` (0–100) e `resets_at` (ISO 8601), valori reali;
- in più: `limits[]` (kind `session`, `weekly_all`, `weekly_scoped` per modello, con `severity` e `is_active`), `model_scoped[]`, `extra_usage` (crediti extra), `spend`, `seven_day_breakdown` (quota per superficie: Claude Code, chat, …). Diversi campi hanno nomi in codice non documentati.

Da dove arriva: è il CLI a chiamare l'endpoint d'uso di claude.ai con il proprio login. Bubo non legge token né chiama endpoint da sé. È la stessa fonte di `/usage`, quindi rientra in ADR [0003](../adr/0003-login-con-la-cli-claude-dell-utente.md).

Altre fonti provate:

- `claude auth status --json`: campi `loggedIn`, `authMethod`, `apiProvider`, `subscriptionType`, `email`, `orgId`, `orgName`, `configDirectory`, `projectsDirectory`, `analyticsDisabled`. **Nessuna quota.**
- `rate_limit_event` durante un turno: `status` e `rateLimitType: "five_hour"`, ma `utilization` assente nelle prove (quota non vicina al limite).

Rischi: il nome del metodo dice che l'API è instabile e cambierà nome. Bubo deve isolarla in un adattatore e ricadere su `rate_limit_event` se il metodo sparisce. Ogni lettura avvia un processo CLI (~1 s): meglio riusare il processo di una Sessione aperta, o un processo `prewarm()` di riserva, e leggere al massimo ogni qualche minuto.

## 5. `git worktree add` + clonefile con 1 GB di dipendenze

Script: [`bench-worktree.sh`](spike/bench-worktree.sh), [`clonefile.py`](spike/clonefile.py).

Repo finto: i 573 file versionati di un repo reale dell'utente (`git archive HEAD`, sola lettura) più il suo `node_modules` copiato con `cp -Rc`: **1,0 GB, 89.001 file, 106.383 voci**, ignorato da git. Stesso volume APFS. Tre ripetizioni:

| Run | `git worktree add -b` | `cp -Rc node_modules` | `clonefile(2)` su `node_modules` |
|---|---|---|---|
| 1 | 0,10 s | 14,57 s | 1,06 s |
| 2 | 0,12 s | 15,04 s | 1,09 s |
| 3 | 0,13 s | 15,34 s | 1,28 s |

- Spazio libero invariato dopo 6 copie da 1 GB (191 GiB prima e dopo): copy-on-write.
- `cp -Rc` chiama clonefile **file per file**: 15 s, troppo per "clic → Sessione pronta". `clonefile(2)` su una cartella la clona con **una sola chiamata**: ~1,1 s. Coerente con gli 1,37 s misurati in [01](01-sessioni-worktree.md).
- Tempo totale per una Sessione con 1 GB di dipendenze: **~1,2–1,4 s** (worktree + clonefile della cartella).
- Rimozione: `git worktree remove --force` di 3 worktree con 2 GB clonati ciascuno ha preso **36,5 s** (~12 s l'uno, per cancellare ~200.000 voci). L'archiviazione deve cancellare in background.

Per Bubo: clonare le cartelle ignorate intere con `clonefile(2)` (o `copyfile(3)` con `COPYFILE_CLONE` sulla cartella), non con `cp -Rc` né file per file. `clonefile(2)` fallisce se la destinazione esiste e funziona solo sullo stesso volume: serve un ripiego (copia normale) se il Progetto è su un altro disco.

## Fonti

- `node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts` e `sdk.mjs` 0.3.284 (opzioni `projectConfigRoot`, `settings`, metodi `usage_EXPERIMENTAL_…`, `accountInfo`, `listPermissionRules`, tipo `SDKSessionStateChangedMessage`).
- Binario CLI 2.1.284 in `@anthropic-ai/claude-agent-sdk-darwin-arm64`: stringhe e codice attorno a `CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS`, `hasTrustDialogAccepted`, `this workspace has not been trusted`.
- Misure: script in [`spike/`](spike/), eseguiti su questo Mac il 2026-09-29.
