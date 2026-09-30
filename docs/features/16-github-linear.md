# 16 — Integrazioni GitHub e Linear: da issue a Sessione e da Sessione a PR

Ticket: [#128](https://github.com/mgiuditta/bubo/issues/128) (ricerca), [#134](https://github.com/mgiuditta/bubo/issues/134) (decisioni), [#132](https://github.com/mgiuditta/bubo/issues/132) (prototipo della Board: le Bozze), [#140](https://github.com/mgiuditta/bubo/issues/140) (scorciatoie e Palette). Mappa: [#125](https://github.com/mgiuditta/bubo/issues/125).
La Board e le Bozze sono della feature 17; il terminale di Bubo è della feature 15.
Ricerca del 2026-09-30 su GitHub CLI **v2.102.0** (ultima release, 2026-09-30) [1] e sulla documentazione pubblica di Linear.

> **Nota sulla ricerca.** È scritta prima delle decisioni e in alcuni punti è superata. Un ingresso esterno (script di Linear, link `bubo://`) non apre mai una Sessione che lavora: crea una **Bozza** ([#134](https://github.com/mgiuditta/bubo/issues/134)). Per Linear resta solo lo script "Open in coding tool": il link personalizzato non passa identificativo, branch né cartella. In v1 non c'è OAuth Linear, e quindi ⌘I mostra solo issue GitHub. Valgono la Mappa e la Specifica qui sotto.

In sintesi: tutti i concorrenti fanno lo stesso giro, **issue → Sessione con il contesto dell'issue → PR**. Quasi nessuno però lo fa in locale: Cursor, Codex, Devin e Copilot lavorano in cloud e chiedono a un admin di installarli nel workspace. I riferimenti sono Conductor per l'ingresso e Claude Desktop per l'uscita. Bubo fa tutti e due i lati con quello che l'utente ha già. Per GitHub usa il `gh` dell'utente: ⌘I sceglie un'issue e ↩ avvia la Sessione; Apri PR, accanto a Fondi, pusha su gesto e crea la PR con `Closes #N`. Per Linear usa lo script "Open in coding tool", che crea una Bozza con il branch che contiene l'identificativo. Il collegamento e lo stato su Linear li muove l'integrazione GitHub del workspace. Niente credenziali nuove, niente push senza gesto, niente richieste a riposo. Tutto il resto (commenti, review, Projects, Actions) passa dagli MCP che l'utente ha già in `~/.claude`.

## Ricerca

### Come si passa da issue a Sessione e da Sessione a PR

| Prodotto | Dove gira | Issue → Sessione | Sessione → PR | Autenticazione |
|---|---|---|---|---|
| **Claude Code Desktop** (scheda Code) | Mac, locale | Nessun selettore di issue. Da CLI `--worktree "#1234"` o URL di una PR crea il worktree dalla PR [19]. Connettori GitHub e Linear per far leggere le issue all'agente [18]. | Diff → "crea PR"; barra CI con **Auto-fix** e **Auto-merge** (squash, serve l'auto-merge attivo sul repo); notifica a fine CI; **auto-archivio** quando la PR è fusa o chiusa [18]. | "PR monitoring requires the GitHub CLI (`gh`) to be installed and authenticated on your machine"; se manca, propone di installarlo alla prima PR [18]. |
| **Conductor** | Mac, locale | "Create from…" (**⌘I**) → issue GitHub o Linear → conferma repo → workspace e branch; l'agente "eredita titolo, descrizione e contesto dell'issue" (0.66.0, 16-06-2026) [20][21]. Deep link `conductor://…&linear_id=` che trova il repo e riapre il workspace già aperto sul branch dell'issue [22]. | **Create PR** (⌘⇧P): "manda il diff e il contesto del repo all'agente, che scrive la PR" [21]. | GitHub App con accesso per repo, oppure solo SSH/HTTPS [23]; Linear con login proprio e pulsante "aggiorna autenticazione Linear" [20]. |
| **Superset** | Mac, locale | Nessun selettore: usa lo **script personalizzato di Linear** che chiama `superset workspaces create` sul branch dell'issue e apre il workspace [24]. | — (non documentato nelle pagine lette) | CLI Superset con login. |
| **Cursor Cloud Agents** | cloud | Delega dell'issue a "Cursor" o `@Cursor` nei commenti; repo da `[repo=owner/repo]`, etichette, default [25]. | PR creata da sola a fine lavoro; stato in tempo reale su Linear [25]. | Admin del workspace Linear, repo collegato, pagamento a consumo [25]. |
| **Codex** (cloud) | cloud | Assegna a Codex o `@Codex`; repo suggerito da Linear, poi l'ambiente più recente [26]. | Riassunto + link alla chat "così puoi creare la PR" (non la apre da solo) [26]. In locale: `codex mcp add linear` [26]. | Integrazione di workspace. |
| **Devin** | cloud | Assegnazione, etichette-playbook (`!plan`, `!implement`), `@Devin`, trigger su cambi di stato [27]. | Link alla PR nel feed dell'issue [27]. | Integrazione di organizzazione. |
| **Copilot cloud agent** | cloud (GitHub Actions) | Assegna l'issue a "Copilot"; anche da Linear, Jira, Slack [28]. | **Una PR per compito**, un solo repo, sessione al massimo **59 minuti** [28]. | Nativo in GitHub. |
| **Linear** (lato suo) | — | "Open in coding tool": Claude Code, Codex, Conductor, Cursor, Copilot, OpenCode, Replit, v0, Zed; ⌘⌥. per l'ultimo usato, `W` poi `O` per scegliere; prompt con "ID, descrizione, commenti, aggiornamenti, riferimenti e immagini"; template del prompt personale [29][30]. | PR collegata dal branch o dal titolo; stato "In Progress" all'apertura e "Done" al merge [31]. | — |

**Cosa ne esce.**

1. **Il giro è sempre lo stesso**: issue → contesto nel prompt → branch → PR che chiude l'issue. Cambia solo dove gira l'agente.
2. **I prodotti locali non chiedono un'installazione di workspace.** Claude Desktop riusa `gh`; Superset riusa lo script di Linear. I prodotti cloud chiedono sempre un admin (Cursor, Devin, Linear agents).
3. **Nessuno mostra l'issue accanto al diff** né controlla, prima della PR, che il lavoro copra l'issue. Conductor passa il diff all'agente per la descrizione, niente di più [21].
4. **Nessuno riapre la stessa Sessione** partendo dalla stessa issue, tranne Conductor col deep link Linear [22].

### Cosa offre `gh`

**Autenticazione già fatta.** `gh auth login` salva il token "nel credential store di sistema"; se non c'è, ripiega su un file in chiaro (`--insecure-storage` lo forza) [2]. Su macOS il credential store è il Portachiavi, scritto e letto tramite `/usr/bin/security` (libreria `zalando/go-keyring`, usata da `gh`) [3]. Scope minimi `repo`, `read:org`, `gist`, non rimovibili [2][4]; `gh` aggiunge `workflow` quando fa da credential helper di git su HTTPS [5]. Precedenza: `GH_TOKEN`/`GITHUB_TOKEN` sopra il token salvato; `GH_ENTERPRISE_TOKEN` e `GH_HOST` per GitHub Enterprise; `GH_PROMPT_DISABLED` toglie ogni domanda interattiva [6].

**Comandi utili a Bubo** (tutti con `--json` e `--jq`):

| Serve a | Comando | Note |
|---|---|---|
| Elenco issue da scegliere | `gh issue list --assignee @me --json number,title,labels,updatedAt,url` | Filtri `--label`, `--search`, `--state`, `--limit` (default 30) [7]. |
| Contesto dell'issue | `gh issue view N --json title,body,comments,labels,subIssues,parent,url` | Anche `blockedBy`, `blocking`, `closedByPullRequestsReferences` [8]. |
| Branch collegato all'issue | `gh issue develop N --name … --base … [--worktree <path>]` | Crea il branch **sul remoto** e lo lega all'issue; ha anche `--worktree` [9]. |
| Aprire la PR | `gh pr create --base … --head … --title … --body-file - [--draft]` | `--dry-run` stampa senza creare; se il branch non è pushato **chiede** dove pusharlo; senza permessi di push **crea un fork** da solo [10]. |
| Stato della PR | `gh pr view --json state,mergedAt,reviewDecision,statusCheckRollup,mergeStateStatus,closingIssuesReferences,url` | [11] |
| CI | `gh pr checks --watch --interval 10 --fail-fast --json …` | Campo `bucket`: pass, fail, pending, skipping, cancel; codice d'uscita **8** = in attesa [12]. |
| Tutto il resto | `gh api` (REST e GraphQL) | Stesso token, stessa autenticazione. |

**Limiti di GitHub** [13]: 5.000 richieste/ora per utente (15.000 per app di organizzazioni Enterprise Cloud); limiti secondari: 100 richieste concorrenti, 900 punti/minuto REST (GET 1 punto, scritture 5), 2.000 punti/minuto GraphQL, **80 creazioni al minuto e 500 all'ora**. Un giro issue → PR usa poche decine di richieste: nessun problema, se Bubo non fa polling stretto.

**Collegare la PR all'issue** [14]: parole chiave `close(s|d)`, `fix(es|ed)`, `resolve(s|d)` nella descrizione della PR. **Valgono solo se la PR punta al branch di default** del repo; altrimenti l'issue non si chiude. In alternativa il pannello "Development" dell'issue (fino a 10 issue per PR).

**Conseguenza per Bubo.** `gh` basta per tutto il giro nativo, senza OAuth di Bubo, senza chiavi nel Portachiavi di Bubo e senza permessi TCC (il Portachiavi non è TCC; `gh` legge il proprio elemento con `security`). Bubo **lancia `gh` come processo** e non estrae mai il token con `gh auth token` [15]: così il token resta dove l'utente l'ha messo, e le richieste restano dell'app "GitHub CLI" a cui l'utente le ha autorizzate.

### Cosa serve per Linear

Tre strade, dalla più leggera alla più pesante.

**1. "Open in coding tool" di Linear (nessuna credenziale).**
- **Link personalizzato**: Linear apre un URL con parametri; l'unico segnaposto oggi è `{{prompt}}`: "Linear non espone ancora variabili separate per titolo o identificativo nell'URL" (Lanes usa `lanes://new?prompt={{prompt}}`) [32][30].
- **Script personalizzato**: Settings → Code & reviews → Configure coding tools → Custom script; comando in `~/.linear/coding-tools.json` con `path` (assoluto, `~` non espanso), `args` con segnaposto `{{…}}` ed `env` come lista di variabili ammesse [33][24]. Variabili: `LINEAR_PROMPT`, `LINEAR_ISSUE_IDENTIFIER`, `LINEAR_ISSUE_BRANCH_NAME`, `LINEAR_WORK_DIR` (cartella scelta dall'utente), `LINEAR_PROJECT_NAME`, `LINEAR_PULL_REQUEST_COMMENT_ID`, `LINEAR_TOOL_COMMAND`; segnaposto per `args`: `prompt`, `issue.identifier`, `issue.branchName`, `project.name`, `pullRequestComment.id`, `workDir`, `tool.command` [33].
- Lo script è quello che usa Superset [24]. La doc non dice se funziona solo nell'app desktop di Linear: lanciando un eseguibile locale, **presumibilmente sì** (da verificare nel prototipo).

**2. PR collegata senza API.** Linear collega la PR se l'**identificativo è nel nome del branch** o nel titolo della PR; `issue.branchName` è il "nome di branch suggerito" (formato del team configurabile, `gitBranchFormat`) [31][34]. Parole magiche nella descrizione: chiudono `close/fix/resolve/complete` e varianti; non chiudono `ref`, `part of`, `contributes to`, `toward(s)`; solo relazione `relates to`, `related to` [31]. Automazioni di default: "In Progress" alla PR aperta, "Done" al merge [31]. **Condizione**: l'integrazione GitHub di Linear deve essere installata nel workspace (da un owner dell'organizzazione GitHub, o da un admin del repo per il singolo repo) [31].

**3. API GraphQL con OAuth (per scegliere e scrivere dentro Bubo).**
- Endpoint `https://linear.app/oauth/authorize` e `https://api.linear.app/oauth/token`; **PKCE supportato, con `client_secret` facoltativo** (`S256` o `plain`); revoca su `/oauth/revoke` [35].
- Scope: `read` (default), `write`, `issues:create`, `comments:create`, `admin`; `actor=app` solo per agenti e account di servizio [35].
- **Token di accesso valido 24 ore**, poi refresh; "tutte le app OAuth sono passate ai refresh token il 1° aprile 2026" [35].
- Bubo deve **registrare una propria app OAuth** in un workspace Linear e renderla **Public** per installarla in altri workspace; si consiglia un workspace dedicato [36]. La doc di Linear **non dice** se accetta redirect su `localhost`/loopback o su schema personalizzato (`bubo://`): da verificare prima della spec.
- Alternativa senza app: **API key personale**, 2.500 richieste/ora contro 5.000 dell'OAuth [37].
- Limiti [37]: OAuth 5.000 richieste/ora e 2.000.000 punti di complessità/ora per utente; una singola query al massimo 10.000 punti; Linear consiglia webhook invece del polling.
- Campi e mutazioni utili (schema GraphQL ufficiale) [34]: `Issue.branchName`; `issueVcsBranchSearch(branchName)` trova l'issue dal branch; `attachmentLinkGitHubPR(issueId, url)` crea l'allegato ricco "usando l'integrazione GitHub del workspace" (quindi serve comunque quella); `attachmentLinkURL` per un link semplice; `team.gitAutomationStates` per gli stati automatici.

**MCP ufficiale di Linear** [38]: `https://mcp.linear.app/mcp` (Streamable HTTP, lettura e scrittura), `…/mcp/readonly` (sola lettura), `…/sse` deprecato. Autenticazione OAuth 2.1 con registrazione dinamica del client, oppure `Authorization: Bearer` con token o API key. In Claude Code: `claude mcp add --transport http linear-server https://mcp.linear.app/mcp`, poi `/mcp`. Strumenti per trovare, creare e aggiornare issue, progetti e commenti.

**MCP ufficiale di GitHub** [16]: remoto `https://api.githubcopilot.com/mcp/` con OAuth (supportato da Claude Code) o `GITHUB_PERSONAL_ACCESS_TOKEN`; locale via Docker o binario; `--read-only`; toolset `issues`, `pull_requests`, `actions`, `projects` e altri.

**Agenti Linear (delega)** [39]: installazione con `actor=app` che "richiede permessi di admin"; l'issue va in `delegate`, non in `assignee`; **webhook `AgentSessionEvent` verso un URL pubblico** e un'attività "thought" entro **10 secondi**. Non si fa senza un server sempre acceso: fuori dai principi di Bubo (locale, niente demone).

### Termini

- **GitHub**: Bubo non tocca il token; lo usa `gh`, autorizzato dall'utente. Nessun termine aggiuntivo oltre a quelli che l'utente ha già accettato per `gh`.
- **Linear**: Linear "può fissare e far rispettare limiti all'uso dell'API" e "sospendere l'accesso o smettere di fornire l'API in qualunque momento" [40]. Con l'app OAuth, chi pubblica Bubo diventa responsabile di un `client_id` pubblico.

## Il meglio da battere

Il riferimento è **Conductor** per l'ingresso: ⌘I, issue GitHub e Linear, e riapre il workspace già aperto [21][22]. Per l'uscita è **Claude Desktop**: PR, CI, Auto-fix e auto-archivio via `gh` [18]. Tutti e due chiedono qualcosa in più di ciò che l'utente ha: Conductor la sua GitHub App e il login a Linear [20][23], Claude Desktop non ha un selettore di issue [18]. I prodotti cloud vogliono un admin e mandano il codice fuori dal Mac [25][26][27][28]. Criteri candidati:

1. **Da issue a Sessione che lavora in ≤ 2 azioni** (⌘I, poi scelta dell'issue), con titolo, branch e contesto già pieni. Conductor chiede ⌘I, l'issue e la conferma di repo e workspace [21].
2. **0 configurazione per GitHub**: se `gh` è autenticato, funziona al primo uso, senza OAuth di Bubo né token salvati da Bubo. Conductor chiede la sua GitHub App [23].
3. **Linear senza OAuth** per il giro base: lo script di Linear più il branch con l'identificativo. Conductor e i prodotti cloud chiedono sempre il login o l'admin.
4. **Stessa issue → stessa Sessione**: riaprire l'issue porta alla Bozza o alla Sessione già esistente, mai a un doppione. Solo Conductor lo fa, e solo per Linear [22].
5. **PR che chiude davvero l'issue**: la parola chiave giusta (`Closes #N`, `Fixes ENG-123`) la mette sempre Bubo. Se la PR non punta al branch di default, Bubo avvisa prima, perché lì le parole chiave di GitHub non valgono [14].
6. **PR in 1 azione, con anteprima**: descrizione proposta dai "perché" dei blocchi (02) e dal riassunto della Sessione, anteprima con `--dry-run`, modificabile.

## Rischi e casi limite

- **`gh` assente o non autenticato**: Claude Desktop propone di installarlo [18]. Bubo lo rileva e spiega, ma non installa nulla da solo. Senza `gh` le funzioni GitHub native spariscono; restano il merge locale (02) e l'MCP.
- **Più account o GitHub Enterprise**: `GH_HOST`, `--hostname`; decide l'host del remoto del Progetto [6].
- **Scope `workflow`**: se l'agente modifica `.github/workflows/` e il token non ha `workflow`, GitHub rifiuta il push con "refusing to allow an OAuth App to create or update workflow" [17]. Il rimedio lo applica l'utente: `gh auth refresh -s workflow` [4]. Bubo deve riconoscere l'errore e dire cosa fare.
- **Push implicito**: se il branch non è pushato, `gh pr create` chiede dove pusharlo; se mancano i permessi, crea un fork [10]. Bubo pusha lui, esplicitamente, con `git push -u`. Poi chiama `gh pr create --head` con `GH_PROMPT_DISABLED=1`: mai domande a metà, mai fork a sorpresa.
- **`gh issue develop` crea il branch sul remoto** [9], contro la regola "mai push automatico" di 02. Meglio un branch locale e `Closes #N` nella PR.
- **Nome del branch**: la regola di 01 è `bubo/<slug>`. Per Linear il branch **deve contenere l'identificativo** (es. `bubo/eng-123-login`), altrimenti non c'è collegamento né stato automatico [31].
- **PR verso un branch che non è quello di default**: le parole chiave di GitHub non chiudono l'issue [14].
- **Integrazione GitHub assente nel workspace Linear**: nessun collegamento automatico [31]. Senza OAuth Bubo non può rimediare; lo dice.
- **Link `bubo://` da qualunque pagina web**: chiunque può costruire un link con un prompt. Un ingresso esterno **non avvia mai l'agente**: crea una Bozza e aspetta un gesto dell'utente.
- **Progetto da scegliere per un'issue Linear**: Linear passa `LINEAR_WORK_DIR` solo con lo script [33], ed è la cartella scelta dall'utente in Linear, che può non essere un Progetto di Bubo.
- **Contenuto delle issue nel prompt**: testo scritto da altri (issue pubbliche) può contenere istruzioni. Si tratta come un Allegato, non come ordine; le Regole di permesso restano quelle del Progetto.
- **Polling**: stato di PR e CI letti a intervalli ampi (`gh pr checks --watch` ha 10 s di default [12]), solo per le Sessioni con PR aperta, mai a riposo. È coerente con "0 processi `git` a riposo" di 02.
- **OAuth Linear, se arriverà**: il redirect per un'app desktop non è documentato [35], il token dura 24 ore e va rinnovato [35], chi pubblica Bubo diventa responsabile di un `client_id` pubblico [36][40]. Per questo è fuori dalla v1.

## Mappa

Architettura comune in [INDEX.md](INDEX.md). Si appoggia sulle Sessioni e sui worktree (01), sulla revisione e su Fondi (02), sull'Attività e sulle Viste (06), sul router (10), sul Riassunto di Sessione (13), sul terminale di Bubo (15) e sulla Board con le Bozze (17). Solo due giri sono nativi: **issue → Sessione** e **Sessione → PR**. Tutto il resto (commenti, creare issue, review, Projects, Actions) passa dagli MCP che l'utente ha in `~/.claude` (04); Bubo non aggiunge server MCP.

### Issue → Sessione (deciso)

Fonte: [#134](https://github.com/mgiuditta/bubo/issues/134), scorciatoie da [#140](https://github.com/mgiuditta/bubo/issues/140).

- **⌘I in Bubo**: foglio con le issue GitHub aperte del repo del Progetto (`gh issue list --json number,title,labels,updatedAt,url`, ricerca con `--search`). Solo GitHub in v1. **↩ = Avvia subito**: la Sessione nasce in Aperta · Lavora. **⌥↩ = salva come Bozza**.
- **⌥⌘N = Nuova Bozza** a mano (17). ⌘I, ⌥⌘N e i comandi di questa feature stanno nel menu e nella Palette (⌘K) con la loro scorciatoia.
- **Ingressi esterni** (script di Linear, link `bubo://`): creano **sempre una Bozza**, mai una Sessione che lavora. Da lì, Avvia (↩ sulla card o trascinamento nella Board, 17).
- **Contesto dell'issue GitHub**: titolo, corpo, commenti, label e URL, letti **ad Avvia** (`gh issue view N --json title,body,comments,labels,url`), non alla creazione della Bozza. Il testo entra come **Allegato** "scritto da altri", mai come istruzione; valgono le Regole di permesso del Progetto. Immagini solo come link.
- **Contesto di un'issue Linear**: senza OAuth Bubo non può rileggerla. Vale il prompt che Linear passa allo script (`LINEAR_PROMPT`: identificativo, descrizione, commenti, riferimenti [29]), salvato nella Bozza e trattato come Allegato "scritto da altri" allo stesso modo.
- **Branch** (eccezione a `bubo/<slug>` di 01): GitHub `bubo/42-<slug>`; Linear `bubo/<branchName di Linear senza prefisso utente>`, es. `bubo/eng-123-fix-login`. Il worktree si prepara come in 01.
- **Titolo della Sessione** = titolo dell'issue. Il riferimento (`#42`, `ENG-123`) è un'etichetta sulla card e nella Sessione.
- **Niente doppioni**, con chiave (Progetto, fonte, id):
  - Bozza esistente → apre la Bozza;
  - Sessione non Archiviata → apre quella;
  - Sessione Archiviata o Fusa → scelta tra "Riprendi" e "Nuova Sessione".

### Linear (deciso)

- **Solo lo script "Open in coding tool"**. Il link personalizzato ha solo `{{prompt}}` [32]: niente identificativo, branch né cartella.
- **"Collega Linear"** nelle Impostazioni aggiunge la voce di Bubo a `~/.linear/coding-tools.json` [33], con conferma e mostrando la riga. Le altre voci del file restano intatte. `path` punta (assoluto) a un eseguibile minimo nel bundle; `env` ammette `LINEAR_PROMPT`, `LINEAR_ISSUE_IDENTIFIER`, `LINEAR_ISSUE_BRANCH_NAME` e `LINEAR_WORK_DIR`. "Scollega Linear" toglie la voce.
- **L'eseguibile** inoltra i quattro valori a Bubo come ingresso esterno (apre Bubo se è chiuso) ed esce. Nasce una Bozza con fonte Linear.
- **Progetto**: il Progetto la cui cartella corrisponde a `LINEAR_WORK_DIR`. Se nessuno corrisponde, Bubo chiede quale Progetto usare e ricorda la risposta per il team (il prefisso dell'identificativo, es. `ENG`).
- **Niente OAuth in v1.** Lo stato su Linear ("In Progress" alla PR aperta, "Done" al merge) lo muove l'integrazione GitHub del workspace, grazie al branch con l'identificativo [31]. Se l'OAuth arriverà, il token andrà nel Portachiavi di Bubo; è fuori dai criteri v1.
- **Delega agli agenti Linear** (`delegate`, `@Bubo`): fuori portata. Serve un webhook verso un URL pubblico con risposta entro 10 s [39], cioè un server sempre acceso.

### Sessione → PR (deciso)

- **Apri PR** accanto a Fondi (02), sulla Sessione Ferma in Aperta. Non serve aver rivisto i blocchi; se ci sono blocchi rifiutati non rimandati all'agente, il foglio avvisa.
- **Sequenza**:
  1. Bubo fa squash del lavoro della Sessione in un commit sul branch;
  2. `git push -u`;
  3. `gh pr create --head <branch> --base <branch di partenza>` con `GH_PROMPT_DISABLED=1`.

  Mai `gh issue develop`, mai fork. Se la base non è il branch di default del repo, avviso nel foglio prima di creare.
- **Testo**: titolo e descrizione li propone il router (10) come testo breve, anche con il Modello locale se l'utente lo preferisce. Il modello riceve il riassunto della Sessione (lo stesso testo di `Memory/SessionSummarizer`, 13, dopo il filtro dei segreti, senza scrivere la nota) e i "perché" dei blocchi. La riga `Closes #42` / `Fixes ENG-123` la aggiunge **Bubo**, non il modello.
- **Foglio**: titolo e descrizione modificabili, anteprima con `gh pr create --dry-run`, interruttore draft spento di default, una sola azione **Crea PR**.
- **Fase**: con la PR creata la Sessione passa a **In revisione**; nella Board va in "PR aperta" (17), con numero e check sulla card.
- **Nuovi commit** dopo la PR: **Aggiorna PR** pusha sul branch, solo su gesto.
- **CI**: check sulla card. Polling (`gh pr view --json state,mergedAt,statusCheckRollup,url`) solo per le Sessioni con PR aperta e solo con Bubo in primo piano, più una lettura al ritorno in primo piano. Un check fallito mostra **Correggi**, che manda il log all'agente come nuovo turno della stessa Sessione. Niente Auto-fix né auto-merge.
- **PR fusa** → Fase **Fusa**, poi come dopo un merge locale (01): worktree rimosso, branch locale cancellato, Fase Archiviata, Riassunto di Sessione (13).
- **PR chiusa senza merge** → **Aperta · Ferma** con una nota nella Sessione.

### `gh` assente o non autenticato (deciso)

- Rilevato solo quando serve (⌘I, Apri PR), mai all'avvio di Bubo.
- Messaggio che spiega cosa manca, più **Apri nel terminale**: lancia `brew install gh` o `gh auth login` nel terminale di Bubo (15). Il terminale di Bubo vive solo nel worktree di una Sessione (15), quindi: da Apri PR, Correggi e Aggiorna PR si apre nel worktree della Sessione; da ⌘I, quando nessuna Sessione esiste ancora, Bubo apre il Terminale di sistema con il comando già scritto (`gh` si installa e si autentica una volta per tutto il Mac).
- Senza `gh`: ⌘I si apre vuoto con la spiegazione, Apri PR è disattivato con il motivo, il merge locale di 02 resta intatto.
- Push rifiutato per lo scope `workflow` [17] → messaggio con `gh auth refresh -s workflow` [4] e lo stesso pulsante.
- Bubo non estrae mai il token (`gh auth token` [15]) e non salva credenziali GitHub: lancia `gh` come processo, e il token resta dove l'utente l'ha messo.

### Moduli

- `Integrations/GitHubCLI`: lancia `gh` con `--json` e `GH_PROMPT_DISABLED=1`, rileva assenza, mancata autenticazione ed errore di scope; l'host viene dal remoto del Progetto.
- `Integrations/IssueSource`: elenco e contesto delle issue GitHub; contesto Linear dalla Bozza. Produce l'Allegato "scritto da altri".
- `Integrations/IssueLink`: chiave (Progetto, fonte, id), nome del branch dall'issue, regola dei doppioni.
- `Integrations/LinearScript`: scrive e toglie la voce in `~/.linear/coding-tools.json`; eseguibile minimo nel bundle che inoltra i valori a Bubo; scelta del Progetto per team.
- `Integrations/PullRequestFlow`: squash, `git push -u`, `gh pr create` (anche `--dry-run`), parola chiave, avviso sulla base, Aggiorna PR.
- `Integrations/PullRequestMonitor`: polling di stato e check solo con PR aperta e Bubo in primo piano; passaggi di Fase (In revisione, Fusa, Aperta · Ferma).
- `HUD/IssuePicker` (⌘I), `HUD/PullRequestSheet` (foglio Apri PR), `HUD/PullRequestBadge` (numero e check sulla card e nella Sessione, con Correggi).
- Usa: `Sessions/` e `Sessions/WorktreeManager` (01), `Git/` (02), le Bozze (17), `Router/` (10), `Memory/SessionSummarizer` e `Memory/SecretFilter` (13), il terminale (15).

### Flusso

1. ⌘I → `IssuePicker` → `gh issue list` → ↩ → `IssueLink` (doppioni, branch) → `gh issue view` → Allegato → worktree (01) → Sessione in Aperta · Lavora.
2. Linear → "Open in Bubo" → eseguibile nel bundle → Bozza (fonte Linear, Progetto da `LINEAR_WORK_DIR`) → Avvia → Sessione.
3. Sessione Ferma → Apri PR → router + `SessionSummarizer` → foglio con `--dry-run` → Crea PR → squash → `git push -u` → `gh pr create` → Fase In revisione.
4. `PullRequestMonitor` (solo in primo piano) → check sulla card → Correggi, oppure PR fusa → Fusa → Archiviata, oppure PR chiusa → Aperta · Ferma.

### Casi limite

- Stessa issue aperta da ⌘I e da Linear, o due volte da Linear: la chiave (Progetto, fonte, id) porta alla Bozza o Sessione esistente. GitHub e Linear sono fonti diverse: una stessa attività tracciata su tutti e due crea due chiavi.
- `LINEAR_WORK_DIR` che non corrisponde a nessun Progetto: Bubo chiede e ricorda per team; se l'utente annulla, nessuna Bozza.
- `~/.linear/coding-tools.json` già presente con altri strumenti: si aggiunge una voce, mai si riscrive il file; JSON non valido → nessuna scrittura, messaggio.
- Branch già esistente con lo stesso nome (issue riaperta dopo Archivia senza merge, che tiene il branch): "Riprendi" lo riusa, "Nuova Sessione" aggiunge un suffisso.
- Branch non ancora pushato, o remoto senza permessi di push: `git push -u` fallisce con un messaggio; nessun fork.
- Base diversa dal branch di default: avviso nel 100% dei casi; la riga `Closes` resta, ma il foglio dice che l'issue non si chiuderà da sola.
- Integrazione GitHub assente nel workspace Linear: la PR nasce comunque; il foglio non può saperlo, lo dice la doc di Linear [31].
- Commit nuovi dopo la PR senza Aggiorna PR: la card mostra che la PR è indietro rispetto alla Sessione.
- Bubo in secondo piano o chiuso quando la PR viene fusa: al ritorno in primo piano una lettura aggiorna la Fase.
- Più PR aperte: una lettura per Sessione per intervallo, lontana dai limiti di GitHub (5.000 richieste/ora [13]).
- Issue di un repo pubblico con istruzioni nel testo: resta un Allegato; le azioni dell'agente passano comunque dalle Regole di permesso (05).
- Link `bubo://` costruito da una pagina web: al massimo una Bozza, 0 Sessioni avviate.

### Test

- `IssueLink` con Swift Testing: nomi di branch da issue GitHub e Linear (prefisso utente tolto, caratteri non validi), chiave dei doppioni sui tre casi (Bozza, Sessione viva, Archiviata o Fusa).
- `GitHubCLI` con un `gh` finto nel `PATH` che registra argomenti e ambiente: 0 chiamate senza `GH_PROMPT_DISABLED=1`, 0 chiamate a `gh issue develop`, `gh auth token` o fork; uscita "non autenticato" e errore di scope `workflow` riconosciuti.
- `PullRequestFlow` su un repo finto con un remoto locale: 0 push senza Crea PR o Aggiorna PR; parola chiave presente nel 100% dei corpi; avviso con base diversa dal branch di default.
- `LinearScript` su un `coding-tools.json` con altre voci: voci altrui intatte dopo Collega e Scollega.
- Monitor di rete e di processi con Bubo a riposo o in secondo piano: 0 richieste a GitHub e Linear, 0 processi `gh`.
- Ingresso esterno (script e link) su 20 casi: 20 Bozze, 0 Sessioni avviate.

### Ordine di costruzione

1. **⌘I → Sessione (GitHub)**: `GitHubCLI`, `IssuePicker` con ↩, contesto come Allegato, branch `bubo/42-<slug>`, doppioni con Sessioni. Senza `gh`, per ora solo il messaggio. Dipende da 01 (worktree, branch) e 06 (Attività, Viste).
2. **Apri PR**: `PullRequestFlow` e foglio con `--dry-run`, parola chiave, avviso sulla base, Fase In revisione. Dipende dal passo 1, da 02 (Fondi, "perché" dei blocchi), 10 (router) e 13 (`SessionSummarizer`, `SecretFilter`).
3. **Dopo la PR**: `PullRequestMonitor`, check sulla card, Correggi, Aggiorna PR, Fusa → Archiviata, chiusa → Aperta · Ferma. Dipende dal passo 2 e da 06; la colonna "PR aperta" arriva con 17.
4. **Bozze da issue e Linear**: ⌥↩ in ⌘I, ingressi esterni come Bozza, Collega Linear con l'eseguibile nel bundle, scelta del Progetto per team. Dipende dal passo 1 e da 17 (Bozza, colonna Da iniziare, Avvia).
5. **`gh` mancante**: Apri nel terminale per `brew install gh`, `gh auth login` e `gh auth refresh -s workflow`. Dipende dal passo 1 e da 15 (terminale di Bubo).

## Specifica "migliore di"

Miglior concorrente per l'ingresso: **Conductor** (⌘I da issue GitHub e Linear, riapre il workspace esistente), che però chiede la sua GitHub App e il login a Linear. Per l'uscita: **Claude Desktop** (PR e CI via `gh`), che però non ha un selettore di issue. I prodotti cloud chiedono un admin e portano il codice fuori dal Mac.
Bubo li supera così:

1. **0 credenziali nuove** per il giro base, su GitHub e su Linear: nessun token salvato da Bubo, nessun OAuth, nessuna installazione di workspace.
2. **≤ 2 azioni** da issue a Sessione che lavora (⌘I + ↩); da Linear 1 clic crea la Bozza, più Avvia.
3. **0 doppioni**: la stessa issue sullo stesso Progetto apre sempre la Bozza o la Sessione esistente.
4. **100% delle PR** con la parola chiave giusta, messa da Bubo; avviso nel **100%** dei casi con base diversa dal branch di default.
5. **1 azione** da Sessione Ferma a PR creata, dopo il foglio con anteprima.
6. **0 push** senza un gesto esplicito (Crea PR, Aggiorna PR).
7. **0 richieste** a GitHub o Linear a riposo; polling della CI solo con PR aperta e Bubo in primo piano.
8. **0 Sessioni avviate** da un ingresso esterno senza un gesto dell'utente.
9. **Scoperta**: ⌘I, ⌥⌘N, Apri PR, Aggiorna PR e Collega Linear sono nel menu e nella Palette nel **100%** dei casi, ciascuno con la sua scorciatoia se ne ha una; **0 scorciatoie globali** nuove.

## Fonti

1. cli/cli, release v2.102.0 — https://github.com/cli/cli/releases
2. GitHub CLI, `gh auth login` — https://cli.github.com/manual/gh_auth_login
3. zalando/go-keyring, `keyring_darwin.go` (`/usr/bin/security`, `add-generic-password`) — https://github.com/zalando/go-keyring/blob/master/keyring_darwin.go ; dipendenza in https://github.com/cli/cli/blob/trunk/go.mod
4. GitHub CLI, `gh auth refresh` — https://cli.github.com/manual/gh_auth_refresh
5. cli/cli, `pkg/cmd/auth/shared/git_credential.go` (scope `workflow`) e `internal/authflow/flow.go` (scope minimi) — https://github.com/cli/cli/blob/trunk/pkg/cmd/auth/shared/git_credential.go
6. GitHub CLI, `gh help environment` — https://cli.github.com/manual/gh_help_environment
7. GitHub CLI, `gh issue list` — https://cli.github.com/manual/gh_issue_list
8. GitHub CLI, `gh issue view` — https://cli.github.com/manual/gh_issue_view
9. GitHub CLI, `gh issue develop` — https://cli.github.com/manual/gh_issue_develop
10. GitHub CLI, `gh pr create` — https://cli.github.com/manual/gh_pr_create
11. GitHub CLI, `gh pr view` — https://cli.github.com/manual/gh_pr_view
12. GitHub CLI, `gh pr checks` — https://cli.github.com/manual/gh_pr_checks
13. GitHub Docs, "Rate limits for the REST API" — https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
14. GitHub Docs, "Linking a pull request to an issue" — https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue
15. GitHub CLI, `gh auth token` — https://cli.github.com/manual/gh_auth_token
16. github/github-mcp-server, README — https://github.com/github/github-mcp-server
17. Errore di push senza scope `workflow` (spiegazione e rimedi) — https://dev.to/jessehouwing/can-t-push-to-github-refusing-to-allow-an-oauth-app-to-create-or-update-workflow-without-workflow-scope-1imc
18. Claude Code, "Desktop application" (PR, CI, Auto-fix, Auto-merge, `gh` richiesto, connettori) — https://code.claude.com/docs/en/desktop
19. Claude Code, "Run parallel sessions with worktrees" — https://code.claude.com/docs/en/worktrees
20. Conductor, changelog 0.66.0 "Create workspace from issue" — https://www.conductor.build/changelog/0.66.0-create-workspace-from-issue
21. Conductor, "Issue to PR" — https://www.conductor.build/docs/guides/issue-to-pr
22. Conductor, "Deep links" — https://www.conductor.build/docs/reference/deep-links
23. Conductor, changelog 0.0.21 "Fine-grained GitHub permissions" — https://www.conductor.build/changelog/0.0.21-fine-grained-github-permissions
24. Superset, "Linear Integration" — https://docs.superset.sh/use-with-linear
25. Cursor, "Linear" (Cloud Agents) — https://cursor.com/docs/integrations/linear
26. OpenAI Codex, "Linear" — https://learn.chatgpt.com/docs/third-party/linear
27. Devin, "Linear" — https://docs.devin.ai/integrations/linear
28. GitHub Docs, "About Copilot cloud agent" — https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-coding-agent
29. Linear, changelog 2026-02-26 "Deeplink to AI coding tools" — https://linear.app/changelog/2026-02-26-deeplink-to-ai-coding-tools
30. Linear Docs, "Code & reviews" e "Assign and delegate issues" — https://linear.app/docs/code-and-reviews ; https://linear.app/docs/assigning-issues
31. Linear Docs, "GitHub" (collegamento, parole magiche, automazioni, installazione) — https://linear.app/docs/github
32. Lanes, "Deep links" (link personalizzato di Linear con `{{prompt}}`) — https://lanes.sh/docs/desktop/deep-links
33. Linear Docs, "Open issues with custom scripts" — https://linear.app/docs/open-issues-with-custom-scripts
34. linear/linear, `packages/sdk/src/schema.graphql` (`Issue.branchName`, `issueVcsBranchSearch`, `attachmentLinkGitHubPR`, `attachmentLinkURL`, `gitBranchFormat`, `gitAutomationStates`) — https://github.com/linear/linear/blob/master/packages/sdk/src/schema.graphql
35. Linear Developers, "OAuth 2.0 authentication" — https://linear.app/developers/oauth-2-0-authentication
36. Nango, "Register your own Linear OAuth app" (interruttore Public, refresh token) — https://nango.dev/docs/api-integrations/linear/how-to-register-your-own-linear-api-oauth-app
37. Linear Developers, "Rate limiting" — https://linear.app/developers/rate-limiting
38. Linear Docs, "MCP server" — https://linear.app/docs/mcp
39. Linear Developers, "Agents" — https://linear.app/developers/agents
40. Linear, "Terms of Service" (API) — https://linear.app/terms

Nota: su questo Mac i comandi `gh` di lettura della configurazione di autenticazione non sono stati eseguiti (bloccati dal classificatore dei permessi dell'agente); il comportamento di `gh` viene dal manuale e dal codice sorgente.
