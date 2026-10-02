# 20 — Marketplace di plugin e Server MCP

Ticket: [#179](https://github.com/mgiuditta/bubo/issues/179) (ricerca), [#184](https://github.com/mgiuditta/bubo/issues/184) (decisioni v1), [#190](https://github.com/mgiuditta/bubo/issues/190) (prototipo finestra Plugin), [#185](https://github.com/mgiuditta/bubo/issues/185) (Sandbox), [#186](https://github.com/mgiuditta/bubo/issues/186) (soglie di prestazioni). Mappa: [#178](https://github.com/mgiuditta/bubo/issues/178).
Ricerca del 2026-09-30 su CLI `claude` **2.1.285** (help, file in `~/.claude/plugins` e binario letti in locale), Agent SDK TS **0.3.282** (`sdk.d.ts` letto in locale), documentazione Claude Code, MCP Registry **v1.8.1** (API `v0.1`) e documentazione dei concorrenti alla stessa data. Testo completo sul branch `research/20-marketplace` (`docs/features/research/20-marketplace.md`).

> **Nota sulla ricerca.** Riporta solo fatti ed è scritta prima delle decisioni. In alcuni punti le decisioni la superano. Bubo **non scrive mai** `enabledPlugins` né `extraKnownMarketplaces`, anche se la ricerca lo elenca come via possibile: scrive solo la CLI ([#184](https://github.com/mgiuditta/bubo/issues/184)). Il marketplace ufficiale non aspetta la prima sessione interattiva del terminale: Bubo lo registra al primo accesso, **con un clic esplicito**. Le sorgenti `command` non si confermano mai con `-y`, solo con `--accept-command <sha256>`. Gli aggiornamenti non restano "automatici solo per gli ufficiali": Bubo controlla **tutti** i Marketplace ogni giorno. Il registro MCP ufficiale letto direttamente è **fuori dalla v1**: i Server MCP sfusi arrivano dal sotto-registro di Anthropic, e questo corregge il confine fissato quando è nata la mappa. Il titolo in [INDEX.md](INDEX.md) ("Marketplace di skill, MCP e agenti") diventa "Marketplace di plugin e Server MCP": skill e agenti arrivano dentro i Plugin. Valgono la Mappa e la Specifica qui sotto.

In sintesi: Claude Code ha già tutto ciò che serve, ma solo nel terminale. Il pannello `/plugin` sfoglia, installa, attiva e aggiorna; i comandi `claude plugin …` fanno le stesse cose senza terminale interattivo, quasi tutti con `--json`. Bubo diventa l'**interfaccia grafica dei Marketplace e dei Plugin di Claude Code**, più i **Server MCP** sfusi. Non ha un catalogo né un server propri, e non scrive mai i file di configurazione a mano: ogni modifica passa dalla CLI, sempre dal checkout principale del Progetto. Batte il pannello `/plugin` e Claude Desktop in tre punti. Mostra cosa installa un Plugin prima di installarlo, anche fuori dal marketplace ufficiale, quando è possibile. Segnala gli aggiornamenti di tutti i Marketplace, con una nuova conferma se arriva codice eseguibile nuovo. Rende visibile ogni errore, ogni accesso mancante e ogni Plugin di Progetto non installato, con un'azione a 1 clic. La finestra Plugin ha tre colonne, come Impostazioni di Sistema e Mail.

## Ricerca

### Plugin di Claude Code: cosa sono

Un Plugin è una cartella con un manifest facoltativo `.claude-plugin/plugin.json` e componenti in posizioni standard [4]. Può contenere codice che gira sul Mac con i privilegi dell'utente [7].

| Componente | Posizione | Esegue codice? |
|---|---|---|
| Skill, comandi, agenti | `skills/`, `commands/`, `agents/` | No: istruzioni nel contesto |
| Hook | `hooks/hooks.json` | **Sì**, comandi shell fuori dalla sandbox [7] |
| Server MCP | `.mcp.json`, bundle `.mcpb`, URL | **Sì** per stdio, fuori dalla sandbox [7] |
| Server LSP | `.lsp.json` | **Sì** |
| Monitor | `monitors/monitors.json` | **Sì**, in background, solo in sessioni interattive [4] |
| Eseguibili | `bin/` | Aggiunti al `PATH` di Bash; le chiamate passano dalle Regole di permesso [7] |
| Output style, temi, workflow, `settings.json` | cartelle omonime | No |

- **`plugin.json`** [4]: obbligatorio solo `name`. Tra i facoltativi: `displayName`, `version`, `description`, `author`, `dependencies`, `defaultEnabled`, `userConfig`.
- **`userConfig`** [4]: valori chiesti all'attivazione. Tipi `string`, `number`, `boolean`, `directory`, `file`; `options` crea un selettore. I valori `sensitive: true` vanno nel Portachiavi, gli altri in `pluginConfigs` dei settings.
- **Variabili** [4]: `${CLAUDE_PLUGIN_ROOT}` cambia a ogni aggiornamento; `${CLAUDE_PLUGIN_DATA}` (`~/.claude/plugins/data/<id>/`) sopravvive e si cancella con l'ultima disinstallazione.
- **Validazione** [4][6]: `claude plugin validate <percorso> --json`, uscita 0/1/2.

### Marketplace: formato e numeri

Un Marketplace è una cartella o un repository con `.claude-plugin/marketplace.json` [2][3]. Obbligatori `name`, `owner`, `plugins`; ogni voce è validata da sola. Prima dell'installazione Claude Code legge il `plugin.json` **solo** per le voci con sorgente relativa [3].

| Sorgente | Note [3] |
|---|---|
| Relativa `./…` | Dentro il repository del marketplace |
| `github`, `url`, `git-subdir` | `sha` di 40 caratteri blocca il commit |
| `npm` | Nessuno script di installazione |
| `archive` | Zip HTTPS, con `sha256` verificato |
| `command` | Comando eseguito sul Mac che stampa la cartella del plugin; **mostrato e confermato** prima di girare |

- **Ufficiale** (`claude-plugins-official`) [11]: 314 voci (164 `url`, 98 `git-subdir`, 52 relative); `version` solo in 14. **Community** (`claude-community`): 2.282 voci, quasi tutte fissate a uno SHA [7].
- **Nomi riservati** [3][7]: i nomi ufficiali e community sono accettati solo da `github.com/anthropics/`.

### Comandi `claude plugin …` e `claude mcp …`

| Comando | `--json` | Nota [6][11] |
|---|---|---|
| `marketplace add <sorgente> [--scope]` | **No** | GitHub `owner/repo`, URL git, URL di `marketplace.json`, cartella |
| `marketplace list` | Sì | — |
| `marketplace update [nome]` | **No** | Riscarica uno o tutti |
| `marketplace remove <nome>` | **No** | **Disinstalla tutti i suoi plugin** |
| `install <plugin>[@mkt] -s … [--config k=v] [--accept-command sha]` | Sì | Senza TTY rifiuta le sorgenti `command`/`headersHelper` senza conferma |
| `uninstall <plugin> -s … [--keep-data] [--prune -y]` | Sì | — |
| `enable` / `disable <plugin> -s …` | Sì | Scrivono `true`/`false` in `enabledPlugins` |
| `update <plugin> -s …` | Sì | Poi serve `/reload-plugins` o una sessione nuova |
| `list [--available]` | Sì | `available`: nome, descrizione, sorgente, `installCount`; **niente componenti né costo** |
| `details <nome>` | **No** | Solo testo, solo plugin già caricati |
| `configure <plugin> [--values-stdin]` | Sì | Opzioni `userConfig` da un JSON su stdin |

- **Formato `--json`** [6]: l'ultima riga di stdout è un oggetto con `command`, `outcome` (`ok`/`failed`), `message`, e quando servono `pluginId`, `scope`, `failureCode`. Per una sorgente `command` il `failed` porta `shownCommand` con il suo `sha256`; `--accept-command` accetta solo quel comando, per quel plugin e quel catalogo.
- **Dati prima dell'installazione** [1][7][11]: "Will install" e "Context cost" esistono **solo per l'ufficiale**, in `~/.claude/plugins/plugin-catalog-cache.json` (non documentato: 297 plugin con componenti e token). Per gli altri: "Components will be discovered at installation".
- **Server MCP sfusi** [12]: `claude mcp add [--transport] [--scope local|project|user] [-e K=V] [--header …] <nome> <url|comando>`, `add-json`, `get`, `list`, `remove`, `login`/`logout` (OAuth). Scope: `local` (predefinito, `~/.claude.json` sotto il progetto), `project` (`.mcp.json`), `user` (`~/.claude.json`). Con l'Agent SDK i server di `.mcp.json` si caricano senza chiedere [12].

### Dove scrive e come si attiva

| Scope | File con `enabledPlugins` [1][5] |
|---|---|
| `user` | `~/.claude/settings.json` |
| `project` | `.claude/settings.json` (da committare) |
| `local` | `.claude/settings.local.json` |
| `managed` | Impostazioni gestite, non modificabili |

- Precedenza: user < project < local < flag < managed. Per spegnere solo sul proprio Mac un plugin attivato dal progetto serve `false` nel `local` [5].
- **Stato** sotto `~/.claude/plugins` [5][11]: `known_marketplaces.json`, `installed_plugins.json` (per id: `scope`, `projectPath`, `installPath`, `version`, `gitCommitSha`), `marketplaces/<nome>/` (clone), `cache/<mkt>/<plugin>/<versione>/`, `data/<id>/`.
- **Tre stadi** [5]: dichiarato nei settings → scaricato → caricato nella sessione. All'avvio si carica dalla cache, senza rete. Le modifiche arrivano alla sessione solo con `/reload-plugins` (anche nell'SDK: `reloadPlugins()`) o con una sessione nuova [6][10].
- **Plugin attivato solo dal progetto** [5]: non si scarica sugli altri Mac. Errore "enabled in project settings but isn't installed here"; ognuno lancia `claude plugin install … --scope project`.
- **Dipendenze** [1]: stesso scope; restano fino a `prune`.

### Aggiornamenti

- **Versione** [5]: `version` di `plugin.json`, poi della voce, poi la sorgente (SHA di 12 caratteri per git). Una `version` fissata **blocca gli utenti su quella copia** finché l'autore non la cambia: è la causa di #14061, #17361 e #45810 [28][29][30].
- **Automatici** [1][5] solo nelle sessioni interattive, solo per i marketplace ufficiali e di claude.ai; **spenti** per community e terze parti. La sessione aperta tiene la versione caricata. Le versioni vecchie si cancellano dopo 14 giorni.
- `install nome@mkt` riscarica prima il catalogo; `install nome` senza `@` no [5].

### Fiducia e sicurezza

- **Un solo avviso generico** per tutti i marketplace [7]. I livelli ufficiale, community e terze parti dicono chi pubblica il catalogo, **non** cosa fa ogni plugin.
- **Hook, MCP stdio, LSP e monitor girano fuori dalla sandbox** con i permessi dell'utente [7].
- **Gli aggiornamenti cambiano i file già esaminati** [7].
- **Allowlist e blocklist** solo con le impostazioni gestite (`strictKnownMarketplaces`, `blockedMarketplaces`, `disableCommandPluginSources`) [7][10].

### Agent SDK

- `Options.plugins` accetta solo cartelle locali (`type: 'local'`); con `settingSources` predefinito valgono anche i plugin di `enabledPlugins` [9][10]. **Nessuna API** per installare, sfogliare o aggiornare.
- `query.reloadPlugins()` → `commands`, `agents`, `plugins`, `mcpServers`, `held`, `cache_impact`: se il ricaricamento invalida la cache del prompt, `held: true` [10].
- `system/init` riporta `plugins` e `plugin_errors`; `McpServerStatus.source` vale `plugin` per i server dei plugin [10].

### Registro MCP

- **Ufficiale** [13][15][17]: anteprima, API `v0.1` congelata, sola lettura senza autenticazione. Solo metadati (`server.json`). **Almeno 30.000** server, nessuna scansione di sicurezza, nessun segnale di qualità. "The MCP Registry is not intended to be directly consumed by host applications": le app devono usare un sotto-registro.
- **Sotto-registro di Anthropic** [18]: `GET https://api.anthropic.com/mcp-registry/v0/servers?visibility=commercial&version=latest`, **non documentato** (il parametro `visibility` è ricavato per tentativi). Il 2026-09-30: **327 server, tutti remoti**, con `_meta["com.anthropic.api/mcp-registry"]`: `displayName`, `oneLiner`, `iconUrl`, `isAuthless`, `toolNames`, `permissions`, `directoryUrl`, e `claudeCodeCopyText` in 205 voci (per esempio `claude mcp add --transport http tickettailor https://mcp.tickettailor.ai/mcp`).

### Concorrenti

| Prodotto | Catalogo | Fiducia | Aggiornamenti |
|---|---|---|---|
| **Claude Code, terminale** `/plugin` [1] | Marketplace git + sincronizzazione da claude.ai | Avviso generico; "Will install" e costo solo per l'ufficiale | Automatici solo per gli ufficiali |
| **Claude Desktop, scheda Code** [1] | Browser dei marketplace dell'utente | Come il terminale | Come il terminale |
| **Estensione VS Code di Claude Code** [1] | Scheda Marketplaces | — | Senza riavvio |
| **Claude Desktop, estensioni `.mcpb`** [19][20] | Directory in Impostazioni | Firma `mcpb sign`; segreti nel Portachiavi | Automatici dalla directory, manuali per i privati |
| **VS Code** [21][22][23] | Galleria `@mcp`; Agent Plugins 1.0, legge anche `.claude-plugin` | MCP dei plugin **fidati dall'installazione** | Ogni 24 h |
| **Cursor** [24][25] | Marketplace con **revisione manuale** di ogni plugin e aggiornamento | Approvazione delle chiamate MCP | Rivisti prima della pubblicazione |
| **Zed, Conductor** [26][27] | Nessuna interfaccia per i plugin di Claude Code | — | — |

### Dove falliscono (anthropics/claude-code)

- **Aggiornamenti che non aggiornano**: #14061 (25 commenti), #17361, #45810, tutte aperte [28][29][30].
- **Worktree**: installare lo stesso plugin da più worktree duplica le voci in `installed_plugins.json`; `uninstall`/`disable` danno errori contraddittori (#85278) [31].
- **Marketplace privati**: il clone HTTPS fallisce (#13798), Cowork non li accetta (#28125, 39 commenti). Claude Code non chiede mai credenziali [1][32][33].
- **Componenti non caricati**: hook da `hooks.json` esterno (#16288), `lspServers` nel `marketplace.json` (#15148) [34][35].

## Il meglio da battere

Il riferimento è il **pannello `/plugin`** di Claude Code, che Claude Desktop (scheda Code) riprende quasi uguale. Fa tutto, ma nel terminale, con un avviso di fiducia generico e con gli aggiornamenti automatici solo per gli ufficiali. Criteri candidati usciti dalla ricerca (quelli decisi sono nella Specifica):

1. **Parità con la CLI**: stesso stato in Bubo, in `claude plugin list --json` e in `/plugin`; nessun file scritto fuori dalla CLI (contro opcode #287, feature 04).
2. **Inventario prima di installare** dove esiste un modo onesto di saperlo: cache dell'ufficiale e sorgenti relative. Altrimenti un'etichetta chiara "componenti sconosciuti".
3. **Aggiornamenti per tutti i Marketplace**, con una nuova conferma quando arriva codice eseguibile nuovo e la spiegazione della `version` fissata.
4. **Veloce e breve**: finestra pronta dalla cache senza rete; da un Plugin ufficiale a disponibile in pochi clic.
5. **Worktree sicuri**: 0 voci duplicate (contro #85278).
6. **0 degradi silenziosi**: ogni `plugin_errors`, ogni `needs-auth`, ogni Plugin di Progetto mancante visibile con un'azione.

## Rischi e casi limite

- **Sotto-registro non documentato** [18]: può sparire o cambiare formato. Senza ripiego, la sezione Server MCP resterebbe vuota o in errore.
- **`plugin-catalog-cache.json` non documentato** [11]: può cambiare formato o sparire. Non deve mai produrre un errore.
- **`marketplace add/remove/update` senza `--json`**: resta solo il codice di uscita; l'esito si verifica rileggendo `marketplace list --json`.
- **Worktree** (#85278 [31]): un comando lanciato dalla cartella di un worktree duplica le installazioni `project`/`local`, legate al `projectPath`.
- **Sessioni in worktree e scope `local`**: l'installazione è legata al checkout principale; la Sessione lavora nel worktree con `projectConfigRoot` sul checkout principale (architettura comune). Va verificato che Claude Code carichi i plugin `local` anche lì.
- **Codice eseguibile nascosto**: per le sorgenti non relative e fuori dall'ufficiale, i componenti si conoscono solo dopo l'installazione. Gli hook partono alla prima Sessione.
- **Aggiornamenti fatti da Claude Code**, non da Bubo: per gli ufficiali l'aggiornamento automatico può portare codice eseguibile nuovo senza passare dalla conferma di Bubo.
- **`version` fissata** [5]: "aggiorna" non cambia niente e l'utente pensa a un guasto.
- **Segreti**: i valori `userConfig` sensibili e le credenziali non devono finire in argomenti di processo, log o settings.
- **Repository privati**: `git` può chiedere credenziali su un terminale che non c'è e restare appeso.
- **`marketplace remove` disinstalla tutti i plugin** del marketplace [6]: un clic sbagliato toglie molte cose.
- **Scritture concorrenti** su `~/.claude.json` e sui settings: in passato l'hanno corrotto (feature 04). Due comandi di Bubo insieme, o Bubo più il terminale, possono ripeterlo.
- **Ricaricare i plugin** in una Sessione aperta può invalidare la cache del prompt (`held`, `cache_impact`) [10]: costa token.
- **App aperta dal Finder**: niente `PATH` della shell, quindi `claude` va trovato per percorso assoluto (feature 26, [#187](https://github.com/mgiuditta/bubo/issues/187)).
- **Plugin gestiti dall'organizzazione** (scope `managed`) e policy (`strictKnownMarketplaces`, `blockedMarketplaces`): la CLI rifiuta; Bubo non deve proporre azioni impossibili.
- **Sandbox** ([#185](https://github.com/mgiuditta/bubo/issues/185)): con la Sandbox accesa la Modalità autonoma non approva da sola gli strumenti dei Server MCP stdio. Un'Automazione (Sandbox accesa di default) che usa un Plugin con MCP locale vede dei dinieghi.

## Mappa

Architettura comune in [INDEX.md](INDEX.md). Si appoggia sul ponte agente e su `Agent/ProcessSpawner` con disclaim ([ADR 0005](../adr/0005-claude-senza-i-permessi-tcc-di-bubo.md)), sul pannello della configurazione (04), sulle Sessioni in worktree (01), sulla Palette (14), sulla finestra Agenti (19, stesso modello di finestra) e sulla Sandbox (22, [#185](https://github.com/mgiuditta/bubo/issues/185)).

### Sorgenti (deciso)

Fonte: [#184](https://github.com/mgiuditta/bubo/issues/184).

- **Marketplace**: si parte da quelli già registrati in `~/.claude` (`known_marketplaces.json`, `marketplace list --json`).
  - **Ufficiale** (`anthropics/claude-plugins-official`): se manca, si registra al primo accesso **solo con un clic esplicito**.
  - **Community** (`claude-community`): solo se l'utente lo chiede ("+ Community").
  - **Aggiungi marketplace…**: `owner/repo`, URL git o cartella locale. I repository privati usano le credenziali git che l'utente ha già; Bubo non ne chiede.
- **Server MCP sfusi**: dal **sotto-registro di Anthropic** (327 server remoti curati, con `claudeCodeCopyText`), con **ripiego silenzioso** se sparisce, più l'aggiunta a mano (URL o comando).
- **Registro MCP ufficiale letto direttamente: fuori dalla v1.** Si riconsidera quando esiste un sotto-registro documentato.
- **Nessun catalogo né server di Bubo.**

### Scrittura (deciso)

- **Scrive solo la CLI**: `claude plugin …` e `claude mcp …`. `--json` dove esiste. Per `marketplace add/remove/update`: codice di uscita, poi `marketplace list --json` per verificare. Bubo **non scrive mai** `enabledPlugins`, `extraKnownMarketplaces`, `.mcp.json` né `~/.claude.json`.
- **Cartella di lavoro** di ogni comando: il **checkout principale del Progetto**, mai un worktree (#85278 [31]).
- Bubo legge i file (settings, `installed_plugins.json`, `known_marketplaces.json`, i cloni dei marketplace) ma non li modifica.

### Scope (deciso)

- Tre scelte, stesse parole ovunque:
  - **Per me** (`user`), predefinito.
  - **Per questo Progetto** (`project`), con l'avviso "gli altri lo installano dal proprio Mac".
  - **Solo io in questo Progetto** (`local`); nei fogli corti "Solo io qui".
- **Plugin di Progetto mancante** ("enabled in project settings but isn't installed here"): installazione con **1 clic** (`claude plugin install <id> --scope project`).

### Fiducia (deciso)

- **Prima dell'installazione**, l'inventario dei componenti quando è noto:
  - dalla cache dell'ufficiale (`plugin-catalog-cache.json`), facoltativa: se manca o cambia formato si passa a "sconosciuti" senza errori;
  - da una sorgente relativa, letta dal clone del marketplace.
  - Altrimenti l'etichetta **"Componenti sconosciuti: può eseguire codice sul Mac"**.
- **Sorgente `command`**: si mostrano il comando e la sua impronta sha256; si conferma con `--accept-command <sha256>`. Mai `-y`.
- **Dopo l'installazione**: l'elenco effettivo di hook, Server MCP, LSP, `bin/` e monitor. Ogni Plugin con codice eseguibile porta il segno **"gira fuori dalla sandbox"**.
- **Sandbox** ([#185](https://github.com/mgiuditta/bubo/issues/185)): Plugin, MCP e hook restano tutti attivi anche con la Sandbox accesa. Con la Sandbox accesa la Modalità autonoma non approva da sola gli strumenti dei Server MCP stdio: serve una Regola di permesso esplicita, altrimenti diniego (nel resoconto, se è un'Esecuzione).

### Aggiornamenti (deciso)

- Restano i default di Claude Code (automatici per gli ufficiali).
- In più Bubo fa un **controllo giornaliero** (`marketplace update`) e mostra "aggiornamento disponibile" per **tutti** i Marketplace, con aggiornamento in 1 clic.
- Se cambiano i componenti eseguibili serve una **nuova conferma**.
- La `version` fissata si spiega con "l'autore non ha cambiato versione".

### Sessioni aperte (deciso)

- Ogni modifica vale subito per le **Sessioni nuove**.
- Sulle Sessioni aperte compare **"Ricarica plugin"**, una per Sessione (`reloadPlugins()`), perché ricaricare può invalidare la cache del prompt.

### Configurazione, accesso, rimozione (deciso)

- **`userConfig`**: un modulo generato dai campi, salvato con `claude plugin configure <id> --values-stdin`. I segreti passano **solo da stdin**: mai nei log, mai nei settings, mai negli argomenti.
- **`needs-auth`**: "Accedi" lancia `claude mcp login <nome>`; se fallisce, compare il comando da copiare. Lo stato si vede nella finestra Plugin e nel pannello della configurazione (04).
- **Disattiva** è l'azione primaria. **Disinstalla** è secondaria, con conferma, la casella "Tieni i dati del plugin" (spenta di default) e il `prune` delle dipendenze orfane nella stessa conferma.

### Finestra Plugin (deciso)

Fonte: [#190](https://github.com/mgiuditta/bubo/issues/190), variante A (tre colonne) con un pezzo di B e uno di C. Il design visivo si rifà in costruzione, nella direzione Notte ([ADR 0004](../adr/0004-contenitore-acromatico.md)).

- **Dove**: menu Finestra e Palette, senza scorciatoia, come la finestra Agenti della 19. Il pannello della 04 ci porta dagli errori.
- **Barra degli strumenti**: una sola ricerca su Plugin di tutti i Marketplace e Server MCP. Con una ricerca attiva l'elenco mostra i risultati di tutte le sorgenti, raggruppati per sorgente. ⌘F porta alla ricerca.
- **Barra laterale**:
  - **Installati** · **Da sistemare** (contatore: errori, `needs-auth`, `userConfig` mancante, Plugin di Progetto mancante) · **Aggiornamenti** (contatore).
  - **Marketplace**: uno per voce, con un punto se ha versioni nuove; "+ Community" (se non c'è già) e "+ Aggiungi marketplace…".
  - **Server MCP**.
  - All'apertura si seleziona Da sistemare se non è vuoto, altrimenti Installati.
- **Elenco**: punto di stato, nome, descrizione. Le voci non installate hanno un'etichetta di fiducia (da C): "solo testo", "esegue codice" o "componenti sconosciuti", e il pulsante "Installa…" nella riga. Da un Plugin ufficiale a installato: 3 clic (Marketplace, Installa…, Installa).
- **Dettaglio**:
  1. Nome, Marketplace, versione; etichette di stato (scope, "fuori dalla sandbox", aggiornamento).
  2. Riquadri d'azione in ordine di gravità, ciascuno con un solo pulsante: Plugin mancante → Installa; errore → azione suggerita; `needs-auth` → Accedi, con accanto il comando `claude mcp login`; impostazioni mancanti → Configura…; aggiornamento → Aggiorna.
  3. Inventario: "Cosa installa" prima dell'installazione, "Componenti installati" dopo, con il segno sui componenti eseguibili.
  4. In fondo: Attiva/Disattiva (primaria), Impostazioni…, Disinstalla… (in rosso, secondaria).
- **Fogli** (modali sulla finestra):
  - **Installa**: scope (Per me predefinito · Per questo Progetto · Solo io qui) e inventario. Componenti sconosciuti → riquadro "Componenti sconosciuti: può eseguire codice sul Mac". Sorgente `command` → comando, impronta sha256 e casella "Ho letto il comando e mi fido": Installa resta spento finché la casella non è spuntata. Server MCP remoto → "non esegue codice sul Mac".
  - **Aggiorna** con nuovo codice eseguibile: elenca solo i componenti nuovi. Senza codice nuovo nessun foglio: 1 clic.
  - **Disinstalla**: "per spegnerlo e basta, usa Disattiva", casella "Tieni i dati del plugin" (spenta), nota sulle dipendenze orfane.
  - **Impostazioni** (`userConfig`): un campo per chiave; i segreti in un campo password, solo via stdin.
- **Ricarica plugin**: banner sotto la barra degli strumenti, solo se ci sono Sessioni aperte con plugin vecchi. "N Sessioni aperte usano i plugin di prima" + "Ricaricare può invalidare la cache del prompt". Un pulsante per Sessione e "Ricarica tutte" (da B). Lo stesso stato sulla riga della Sessione nell'HUD.
- **Accessibilità**: barra laterale ed elenco sono `List` con selezione, navigabili da tastiera. Il punto di stato ha sempre un'etichetta testuale per VoiceOver. I fogli hanno Invio come azione primaria (tranne Disinstalla) ed Esc per annullare.

### Scelte di dettaglio (prese scrivendo la spec)

Non vengono dalle issue. Sono facili da cambiare.

- **Colori** (corretti in [#206](https://github.com/mgiuditta/bubo/issues/206), allineati al design system): niente Lume nella finestra, che resta a «Attende te» e alle Richieste di permesso. I contatori di Da sistemare e di Aggiornamenti sono numeri in `textPrimary` semibold, senza tinta; la voce scelta della barra laterale è in `accent` con testo `ink`. Le etichette di fiducia e "gira fuori dalla sandbox" sono testo e simbolo in `textSecondary`. Il punto di stato è acromatico (attivo `textPrimary`, disattivato `textFaint`), `danger` solo per l'errore. Disinstalla usa `Palette.danger`, mai i colori di sistema.
- **Progetto della finestra**: in cima alla barra laterale c'è il Progetto scelto, come nella finestra Agenti. Predefinito: il Progetto della Sessione in primo piano nell'HUD, altrimenti il più recente. Serve agli scope Progetto e locale e alla cartella di lavoro dei comandi. Senza Progetto, solo lo scope Per me.
- **Esecuzione dei comandi**: una **coda seriale** di comandi di scrittura (mai due insieme, contro la corruzione di `~/.claude.json`). Le letture (`list --json`) possono girare in parallelo. `claude` per percorso assoluto, lo stesso della 03/26, avviato con disclaim da `Agent/ProcessSpawner`. Ambiente con `GIT_TERMINAL_PROMPT=0` e `GIT_ASKPASS` vuoto, così un repository privato fallisce subito invece di restare appeso. Tempo massimo: 120 s per installa e aggiorna (la CLI ha già 60 s per `npm ci`), 60 s per gli altri, 5 min per `mcp login`. Ogni comando è annullabile.
- **Primo disegno senza CLI**: la finestra si disegna leggendo direttamente `known_marketplaces.json`, i `marketplace.json` dei cloni, `installed_plugins.json` e la copia salvata del sotto-registro. `claude plugin list --json --available` aggiorna subito dopo, in background. Così il criterio dei 300 ms non dipende dall'avvio di `claude`.
- **Aggiornamento disponibile**: dopo `marketplace update` si confronta la versione installata (`version` o `gitCommitSha` di `installed_plugins.json`) con la versione che Claude Code calcolerebbe dalla voce ([5]: `plugin.json` per le relative, poi `version` della voce, poi `sha`). Per le voci git senza `sha` né `version` si legge la punta del `ref` con `git ls-remote` (solo lettura, credenziali dell'utente). Per le relative senza `version` vale il commit del clone, letto dai file di `.git`. Il `version` del `plugin.json` nuovo vince anche per le sorgenti git, ma Bubo non lo vede senza scaricare: per `github`/`url`/`git-subdir` senza `version` nella voce il segno è "possibile aggiornamento", e senza la cache dell'ufficiale i componenti nuovi sono sconosciuti, quindi foglio. `npm`, `archive` e `command` non si prevedono. `claude plugin update` non risponde `already_in_goal_state` (preflight #211): se esce con `ok` e la versione in `installed_plugins.json` resta la stessa, o dice "already at the latest version", il segno sparisce finché il Marketplace non offre un'altra versione e compare la spiegazione della `version` fissata.
- **Componenti della nuova versione sconosciuti**: contano come "possibile codice nuovo", quindi foglio di conferma.
- **Aggiornamenti fatti da Claude Code** senza Bubo: dopo, Bubo confronta l'inventario nuovo con l'ultimo visto. Se è comparso codice eseguibile, il Plugin va in Da sistemare con "Nuovo codice eseguibile dall'ultimo aggiornamento" e i pulsanti [Ho visto] e [Disattiva].
- **Costo di contesto**: i token "ogni turno" e "quando invocato" si mostrano nell'inventario solo quando la cache dell'ufficiale li ha.
- **Ricerca**: filtro locale su nome, nome visibile, descrizione, categoria e tag di tutte le voci in memoria, entro 100 ms (come la Palette, 14).
- **Sotto-registro**: letto all'apertura della finestra se la copia ha più di 24 ore e nel controllo giornaliero. Copia in `Application Support`. Ripiego silenzioso: se la risposta fallisce o non ha il formato atteso, si tiene la copia precedente; senza copia, la sezione mostra solo i Server MCP già configurati e "Aggiungi a mano". Nessun errore nella finestra, solo una riga nel log.
- **Installare un Server MCP dal sotto-registro**: `claudeCodeCopyText` non si esegue mai come stringa di shell. Si scompone in argomenti e si accetta solo se è `claude mcp add` con opzioni note (`--transport`, `--scope`, `--header`, `-e`) e un URL `https`. Altrimenti si costruisce il comando da `remotes[0]` (`--transport http|sse <nome> <url>`).
- **Scope dei Server MCP**: stesse tre parole dei Plugin, con **Per me** (`user`) predefinito, anche se la CLI ha `local` come predefinito.
- **Aggiunta a mano**: URL remoto (con "Accedi" dopo, se serve OAuth) oppure comando stdio con variabili d'ambiente. Il foglio dice che Claude Code salva le variabili in chiaro in `~/.claude.json` (scope Per me e Solo io qui) o in `.mcp.json` (Per questo Progetto, finisce in git): per lo scope Progetto un valore che sembra una credenziale (`*_KEY`, `TOKEN`, `SECRET`) blocca il pulsante e lo spiega.
- **Stato `needs-auth`**: da `mcpServerStatus()` delle Sessioni aperte (04). Senza Sessioni aperte vale l'ultimo stato visto, più un pulsante "Controlla" che lancia `claude mcp get <nome>`. Dopo un "Accedi" riuscito, le Sessioni aperte ricevono `reconnectMcpServer(nome)`.
- **Plugin di Progetto mancante** si riconosce da due fonti: `plugin_errors` nel `system/init` delle Sessioni e il confronto tra `enabledPlugins` di `.claude/settings.json` e `installed_plugins.json`, esclusi i Plugin a sorgente relativa di un Marketplace già presente (si caricano dal Marketplace senza installazione) e le origini riservate `@skills-dir`, `@inline`, `@synced` ([#209](https://github.com/mgiuditta/bubo/issues/209)). Se manca anche il marketplace dichiarato dal Progetto, lo stesso clic lo aggiunge prima (`marketplace add <sorgente dichiarata>`, scope Per me).
- **Plugin attivato dal Progetto** che l'utente vuole spegnere solo per sé: Disattiva scrive nel `local` (`disable -s local`), e il dettaglio dice "spento solo per te in questo Progetto".
- **Rimuovi marketplace**: nel menu contestuale del Marketplace, con conferma che elenca i Plugin che verranno disinstallati (`marketplace remove` li toglie tutti).
- **Plugin e Marketplace gestiti** (scope `managed`, policy dell'organizzazione): etichetta "gestito dall'organizzazione", nessuna azione di scrittura.
- **Plugin vecchi nelle Sessioni**: Bubo tiene un numero di **generazione** della configurazione dei Plugin, che cresce a ogni comando di scrittura riuscito e a ogni modifica esterna vista via FSEvents su `installed_plugins.json` e sui tre settings. Una Sessione è "con plugin di prima" se la sua generazione è più vecchia. Le Sessioni sospese (feature 25, [#186](https://github.com/mgiuditta/bubo/issues/186)) riprendono con i plugin nuovi e non contano.
- **Server MCP sfusi e ricarica**: dopo una modifica agli MCP sfusi il banner usa lo stesso `reloadPlugins()`, che restituisce `mcpServers`. Se il server nuovo non compare, il pulsante della Sessione diventa "Riavvia la Conversazione" (chiude e riprende con `resume`). Da verificare in costruzione.
- **Palette**: "Apri Plugin" e "Cerca plugin: testo", che apre la finestra con la ricerca già scritta.

### Moduli

Architettura comune in [INDEX.md](INDEX.md). Moduli nuovi in `Plugins/`:

- `Plugins/ClaudeCLI`: esegue `claude plugin …` e `claude mcp …` per percorso assoluto, con disclaim (`Agent/ProcessSpawner`), cartella di lavoro sul checkout principale, coda seriale per le scritture, tempo massimo, annullamento, stdin per i segreti. Legge l'ultima riga JSON (`outcome`, `failureCode`, `shownCommand`) o il codice di uscita. Nessun segreto nei log.
- `Plugins/PluginCatalog`: stato unico per la finestra. Lettura diretta di `known_marketplaces.json`, dei `marketplace.json` nei cloni, di `installed_plugins.json` e dei tre settings; poi `list --json --available` e `marketplace list --json`. FSEvents sui file di `~/.claude/plugins` e sui settings; numero di generazione.
- `Plugins/PluginInventory`: componenti di un Plugin, da tre fonti in ordine: cartella installata (`installPath`), sorgente relativa nel clone, `plugin-catalog-cache.json` (facoltativa, tollerante). Distingue componenti testuali ed eseguibili (hook, MCP stdio, LSP, `bin/`, monitor), MCP remoti, e il confronto tra due inventari per gli aggiornamenti.
- `Plugins/UpdateChecker`: controllo giornaliero con `NSBackgroundActivityScheduler` (differibile, come la manutenzione della 19) e all'apertura della finestra se l'ultimo ha più di 24 ore; `marketplace update`, calcolo della versione attesa, `git ls-remote` dove serve, codice nuovo sì/no.
- `Plugins/MCPRegistryClient`: sotto-registro di Anthropic, copia locale, ripiego silenzioso, lettura di `claudeCodeCopyText` in argomenti sicuri.
- `Plugins/PluginsWindow`: finestra a tre colonne (SwiftUI `NavigationSplitView`), ricerca, dettaglio con riquadri d'azione.
- `Plugins/InstallSheet`, `Plugins/UpdateSheet`, `Plugins/UninstallSheet`, `Plugins/UserConfigForm`, `Plugins/AddMarketplaceSheet`, `Plugins/AddMCPServerSheet`.
- `Plugins/PluginReloader`: Sessioni con generazione vecchia, `reloadPlugins()` per Sessione con `held` e `cache_impact`, "Ricarica tutte", `reconnectMcpServer()` dopo un accesso. Mostra lo stato anche sulla riga della Sessione (`HUD/`).
- Riuso: `Agent/AgentBridge` (`reloadPlugins`, `mcpServerStatus`, `reconnectMcpServer`, `plugin_errors`), `Agent/ProcessSpawner`, `Config/ConfigInspector` e `HUD/ConfigPanel` (04), `Sessions/` (01), `Palette/CommandCatalog` (14), il modello della finestra Agenti (19).

### Flusso

1. Apertura: menu Finestra o Palette → `PluginCatalog` disegna dai file e dalla copia del sotto-registro → selezione Da sistemare o Installati → `list --json --available` in background.
2. Primo accesso senza ufficiale: riga "Marketplace ufficiale di Anthropic" con [Aggiungi] → `marketplace add anthropics/claude-plugins-official` → `marketplace list --json`.
3. Installazione: riga "Installa…" → `InstallSheet` (scope, inventario o "sconosciuti", `command` con impronta e casella) → `install <id>@<mkt> -s <scope> --json [--accept-command sha]` → inventario reale e segno "fuori dalla sandbox" → generazione +1 → banner "Ricarica plugin" se ci sono Sessioni aperte.
4. Da sistemare: errore, `needs-auth`, `userConfig`, Plugin di Progetto mancante → un riquadro, un pulsante, un comando.
5. Ogni giorno: `marketplace update` → versioni attese → Aggiornamenti → Aggiorna (1 clic, o foglio se c'è codice nuovo) → `update --json` → ricarica.
6. Server MCP: sotto-registro o a mano → `mcp add` → Accedi se serve → ricarica.
7. Disattiva / Disinstalla / Rimuovi marketplace → CLI → verifica con `list --json` → ricarica.

### Casi limite

- **Sotto-registro sparito o cambiato**: resta la copia; nessun errore nella finestra.
- **Cache dell'ufficiale assente o in formato nuovo**: "Componenti sconosciuti" per le voci non relative, nessun errore.
- **Sorgente `command` cambiata** tra il foglio e l'installazione: `--accept-command` non vale più, la CLI risponde `failed` con il nuovo `shownCommand`; il foglio si riapre con il comando nuovo e la casella spenta.
- **Repository privato senza credenziali**: il comando fallisce subito (`GIT_TERMINAL_PROMPT=0`) e la riga dice "Accesso al repository negato: configura una chiave SSH o un credential helper di git".
- **Due finestre, due azioni**: la coda seriale le mette in fila; l'elenco mostra "in attesa".
- **Terminale che modifica i plugin a finestra aperta**: FSEvents → rilettura, generazione +1, banner se serve.
- **`version` fissata**: Aggiorna → `ok` con versione invariata → "L'autore non ha cambiato versione: questa è già l'ultima che pubblica".
- **Plugin richiesto da un altro**: `disable` rifiuta [1]; il riquadro dice quale Plugin ne ha bisogno.
- **Progetto non git**: scope Per questo Progetto e Solo io qui funzionano lo stesso (cartella del Progetto come cartella di lavoro).
- **Progetto in un worktree aperto nell'HUD**: i comandi girano comunque sul checkout principale.
- **Plugin gestito o marketplace bloccato dalla policy**: nessuna azione di scrittura; il messaggio della CLI in una riga.
- **Ricarica con `held: true`**: la Sessione resta con i plugin di prima e il pulsante dice "Ricarica comunque (cache del prompt persa)".
- **`mcp login` che non torna**: dopo 5 minuti si annulla e compare il comando da copiare.
- **Automazione con un Plugin che ha MCP stdio** e Sandbox accesa: gli strumenti MCP sono negati senza una Regola dell'Automazione (19, 22); il resoconto lo dice.

### Test

- `ClaudeCLI` con una CLI finta (script nel bundle di test): lettura dell'ultima riga JSON, codici di uscita, `shownCommand`, tempo massimo, annullamento, coda seriale; nessun segreto negli argomenti né nei log (ricerca del valore nel log e in `ps`).
- `PluginInventory`: tabella di cartelle di Plugin (solo testo, hook, MCP stdio, MCP remoto, LSP, `bin/`, monitor, `plugin.json` con percorsi personalizzati) → componenti ed etichetta attesa; cache dell'ufficiale valida, assente e con formato cambiato → nessun errore.
- `UpdateChecker`: tabella di voci (con `version`, con `sha`, relative, git senza `sha`) × installati → aggiornamento sì/no; confronto di inventari → codice nuovo sì/no.
- `MCPRegistryClient`: risposte registrate (valida, vuota, 500, formato cambiato) → copia tenuta; `claudeCodeCopyText` validi e malevoli (`;`, `&&`, `$(…)`, URL `http`) → argomenti sicuri o ripiego su `remotes`.
- **Parità** end-to-end con `HOME` temporanea e la CLI vera: dopo ogni azione, stato di Bubo = `claude plugin list --json` = `claude mcp list`; `fs_usage` filtrato sul processo di Bubo: **0 scritture** in `~/.claude`, `~/.claude.json` o `.claude/`.
- **Worktree**: tre Sessioni in tre worktree dello stesso Progetto, installazione `project` e `local` da ognuna → **0 voci duplicate** in `installed_plugins.json`.
- **Prestazioni** (XCTest + signpost, [#186](https://github.com/mgiuditta/bubo/issues/186)): finestra con i Marketplace in cache, rete spenta, **< 300 ms** al primo disegno; ricerca su ~2.600 voci **≤ 100 ms**; **0 hang > 100 ms** durante install, update e `marketplace update`.
- **Clic**: UI test da Plugin ufficiale a disponibile in una Sessione nuova in **≤ 3 clic**; Plugin di Progetto mancante installato con **1 clic**.
- **Errori**: set di Plugin rotti (manifest non valido, MCP che non parte, `needs-auth`, `userConfig` mancante, Plugin di Progetto mancante) → **100%** in Da sistemare con testo e azione.
- **Ricarica**: Sessione aperta, installazione → banner; Ricarica → il plugin compare in `supportedCommands()`; `held: true` simulato → testo corretto.
- Accessibilità: audit SwiftUI e AppKit della finestra e dei fogli, navigazione solo da tastiera.

### Ordine di costruzione

1. **Finestra Plugin in sola lettura**: `PluginCatalog`, `PluginInventory`, `PluginsWindow`. Tre colonne con Installati, Marketplace e ricerca; dettaglio con inventario ed etichette di fiducia; segno "fuori dalla sandbox"; Progetto in cima; voci nel menu Finestra e nella Palette. Nessuna scrittura. Dipende da ponte agente ([#66](https://github.com/mgiuditta/bubo/issues/66)), 04 ([#73](https://github.com/mgiuditta/bubo/issues/73)), Palette ([#160](https://github.com/mgiuditta/bubo/issues/160)); stesso modello di finestra di [#173](https://github.com/mgiuditta/bubo/issues/173).
2. **Installa, attiva, disattiva, disinstalla**: `ClaudeCLI` con coda seriale e checkout principale, `InstallSheet` (scope, sconosciuti, `command` con impronta e casella), `UninstallSheet`, test di parità e di worktree. Dipende da 1 e da 01 ([#69](https://github.com/mgiuditta/bubo/issues/69)).
3. **Marketplace**: ufficiale con un clic, "+ Community", "Aggiungi marketplace…", Rimuovi con conferma, repository privati che falliscono subito. Dipende da 2.
4. **Da sistemare**: `plugin_errors` dalle Sessioni e dalla CLI, Plugin di Progetto mancante con 1 clic (anche il marketplace mancante), riquadri d'azione, contatore, link dal pannello della 04. Dipende da 2.
5. **Impostazioni e accesso**: `UserConfigForm` con `configure --values-stdin`, "Accedi" con `mcp login`, stato `needs-auth` e "Controlla", `reconnectMcpServer()`. Dipende da 4.
6. **Aggiornamenti**: `UpdateChecker` giornaliero, sezione Aggiornamenti, punto sui Marketplace, 1 clic o `UpdateSheet` con i componenti nuovi, `version` fissata spiegata, codice nuovo arrivato da Claude Code in Da sistemare. Dipende da 3 e 4.
7. **Ricarica plugin**: `PluginReloader`, generazione, banner con un pulsante per Sessione e "Ricarica tutte", `held` e `cache_impact`, stato sulla riga della Sessione nell'HUD. Dipende da 2 e dal ciclo di vita delle Sessioni ([#71](https://github.com/mgiuditta/bubo/issues/71)).
8. **Server MCP sfusi**: `MCPRegistryClient` con copia e ripiego, sezione Server MCP, installazione dal sotto-registro con argomenti sicuri, `AddMCPServerSheet` (URL o comando), scope, rimozione, Accedi riusato. Dipende da 2 e 5.

## Specifica "migliore di"

Miglior concorrente: il **pannello `/plugin`** di Claude Code e la sua copia in Claude Desktop (scheda Code): stesso motore, ma inventario e costo solo per l'ufficiale, un avviso di fiducia generico, aggiornamenti automatici solo per gli ufficiali, stato corrotto con più worktree (#85278). VS Code fida gli MCP dei plugin già dall'installazione; Zed e Conductor non hanno interfaccia per i plugin di Claude Code.
Bubo li supera così:

1. **Parità con la CLI**: dopo ogni azione, Bubo, `claude plugin list --json` e `/plugin` mostrano **lo stesso stato**; **0 file** di `~/.claude`, `~/.claude.json` o `.claude/` scritti fuori dalla CLI.
2. **Inventario**: componenti mostrati per il **100%** dei Plugin installati; prima dell'installazione per il **100%** delle voci ufficiali e con sorgente relativa (la CLI oggi: solo l'ufficiale).
3. **Aggiornamenti per tutti**: avviso di aggiornamento per il **100%** dei Marketplace (la CLI: solo gli ufficiali); **0 aggiornamenti** con codice eseguibile nuovo senza una nuova conferma in Bubo.
4. **Veloce e breve**: finestra con i Marketplace in cache in **< 300 ms** senza rete; da un Plugin ufficiale a disponibile in una Sessione nuova in **≤ 3 clic**.
5. **Progetti e worktree**: Plugin di Progetto assente sul Mac installato con **1 clic**; **0 voci duplicate** in `installed_plugins.json` con Sessioni in più worktree.
6. **0 degradi silenziosi**: il **100%** di `plugin_errors` e dei `needs-auth` visibile con testo e azione suggerita.
7. **Codice sotto gli occhi**: **0 installazioni** di sorgenti `command` senza la casella spuntata e `--accept-command` con l'impronta mostrata (mai `-y`); **100%** dei Plugin con codice eseguibile marcati "gira fuori dalla sandbox".
8. **Segreti al sicuro**: **0 valori** `sensitive` di `userConfig` in argomenti di processo, log o settings.
9. **Reattiva**: ricerca su tutti i Marketplace e i Server MCP in **≤ 100 ms**; **0 hang > 100 ms** durante i comandi della CLI (soglia di [#186](https://github.com/mgiuditta/bubo/issues/186)).

Le soglie dei criteri 4 e 9 entrano nella tabella dei budget della feature 25 ([#186](https://github.com/mgiuditta/bubo/issues/186)).

## Fonti

1. Claude Code, "Install and manage plugins" — https://code.claude.com/docs/en/plugins/install (da https://code.claude.com/docs/en/discover-plugins)
2. Claude Code, "Create a marketplace" — https://code.claude.com/docs/en/plugins/create-marketplace (da https://code.claude.com/docs/en/plugin-marketplaces)
3. Claude Code, "Marketplace reference" — https://code.claude.com/docs/en/plugins/marketplace-reference
4. Claude Code, "Plugin manifest reference" — https://code.claude.com/docs/en/plugins/manifest-reference (da https://code.claude.com/docs/en/plugins-reference)
5. Claude Code, "Plugin loading reference" — https://code.claude.com/docs/en/plugins/loading
6. Claude Code, "Plugin commands reference" — https://code.claude.com/docs/en/plugins/cli-reference
7. Claude Code, "Plugin security and trust" — https://code.claude.com/docs/en/plugins/security
8. Claude Code, "Anthropic's marketplaces" — https://code.claude.com/docs/en/plugins/anthropic-marketplaces
9. Agent SDK, "Plugins in the SDK" — https://code.claude.com/docs/en/agent-sdk/plugins
10. `@anthropic-ai/claude-agent-sdk` 0.3.282, `sdk.d.ts` (`Options.plugins`, `SdkPluginConfig`, `pluginDelivery`, `reloadPlugins()`, `SDKControlReloadPluginsResponse`, `SDKPluginInstallMessage`, `McpServerStatus.source`, `Settings.enabledPlugins`, `extraKnownMarketplaces`, `strictKnownMarketplaces`) — https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk
11. Lettura locale del 2026-09-30: `claude --version` = 2.1.285; `claude plugin [sotto-comando] --help`; `claude plugin list --json --available`; `claude plugin marketplace list --json`; `claude plugin details swift-lsp@claude-plugins-official`; `~/.claude/plugins/{known_marketplaces,installed_plugins,plugin-catalog-cache,blocklist}.json`; `~/.claude/plugins/marketplaces/claude-plugins-official/.claude-plugin/marketplace.json`
12. Claude Code, "Connect Claude Code to tools via MCP" — https://code.claude.com/docs/en/mcp
13. MCP, "The MCP Registry" — https://modelcontextprotocol.io/registry/about
14. MCP, "MCP Registry Supported Package Types" — https://modelcontextprotocol.io/registry/package-types
15. MCP, "MCP Registry Aggregators" — https://modelcontextprotocol.io/registry/registry-aggregators
16. modelcontextprotocol/registry (README; release v1.8.1 del 2026-08-06) — https://github.com/modelcontextprotocol/registry ; OpenAPI — https://github.com/modelcontextprotocol/registry/blob/main/docs/reference/api/openapi.yaml
17. API del registro, lette il 2026-09-30 — https://registry.modelcontextprotocol.io/v0.1/servers?version=latest&limit=100 ; https://registry.modelcontextprotocol.io/v0.1/version
18. Sotto-registro Anthropic, non documentato, letto il 2026-09-30 — https://api.anthropic.com/mcp-registry/v0/servers?visibility=commercial&version=latest ; stringhe `/mcp-registry/v0/servers?` e `[mcp-registry] Loaded … official MCP URLs` nel binario `~/.local/share/claude/versions/2.1.285`
19. modelcontextprotocol/mcpb (release v2.1.2 del 2025-12-04) — https://github.com/modelcontextprotocol/mcpb
20. Claude Help Center, "Getting started with local MCP servers on Claude Desktop" — https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop
21. VS Code, "Use MCP servers in VS Code" (aggiornata il 2026-09-16) — https://code.visualstudio.com/docs/copilot/customization/mcp-servers
22. VS Code, "Agent plugins" — https://code.visualstudio.com/docs/copilot/customization/agent-plugins
23. GitHub Changelog, "Agent Plugins 1.0 in VS Code, Copilot CLI, and the Copilot app" (2026-08-12) — https://github.blog/changelog/2026-08-12-agent-plugins-1-0-in-vs-code-copilot-cli-and-the-copilot-app/ ; specifica — https://github.com/agentplugins/agent-plugins-spec/blob/main/spec/1.0.0.md
24. Cursor, "Model Context Protocol" — https://cursor.com/docs/context/mcp
25. Cursor, "Plugins" — https://cursor.com/docs/plugins
26. Zed, "Model Context Protocol" — https://zed.dev/docs/ai/mcp
27. Conductor, "MCP" — https://www.conductor.build/docs/reference/mcp ; "Claude Code" — https://www.conductor.build/docs/reference/harnesses/claude-code
28. anthropics/claude-code #14061, "/plugin update does not invalidate plugin cache" — https://github.com/anthropics/claude-code/issues/14061
29. anthropics/claude-code #17361, "Plugin cache never refreshes - autoUpdate doesn't update what Claude reads" — https://github.com/anthropics/claude-code/issues/17361
30. anthropics/claude-code #45810, "Marketplace update button is disabled/not pressable even when version is outdated" — https://github.com/anthropics/claude-code/issues/45810
31. anthropics/claude-code #85278, "Plugin install/uninstall state gets corrupted across git worktrees" — https://github.com/anthropics/claude-code/issues/85278
32. anthropics/claude-code #13798, "Private marketplace clone fails with HTTPS authentication error" — https://github.com/anthropics/claude-code/issues/13798
33. anthropics/claude-code #28125, "Cowork Can't add private GitHub marketplace" — https://github.com/anthropics/claude-code/issues/28125
34. anthropics/claude-code #16288, "Plugin hooks not loaded from external hooks.json file" — https://github.com/anthropics/claude-code/issues/16288
35. anthropics/claude-code #15148, "LSP plugin lspServers config not being processed from marketplace.json" — https://github.com/anthropics/claude-code/issues/15148
