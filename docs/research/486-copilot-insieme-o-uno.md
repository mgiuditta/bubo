# 486 — Claude e Copilot: insieme o uno solo?

Ticket: [#486](https://github.com/mgiuditta/bubo/issues/486). Segue [486 — Bubo con GitHub Copilot](486-copilot.md). Collegati: [10 — Router](../features/10-router.md), [ADR 0003](../adr/0003-login-con-la-cli-claude-dell-utente.md), [ADR 0005](../adr/0005-claude-senza-i-permessi-tcc-di-bubo.md), [ADR 0006](../adr/0006-bubo-conserva-le-conversazioni.md). Bozza di decisione: [ADR 0011](../adr/0011-copilot-solo-per-le-domande.md).
Ricerca del 2026-10-03, su Copilot CLI **v1.0.91** (stabile, 2026-10-01), Copilot SDK **v1.0.16** (stabile, 2026-09-30) e sul codice di Bubo a `56b9d64`.

In sintesi: **Claude resta l'unico motore delle Sessioni. Copilot entra solo come fornitore delle Domande** (opzione a), in 1.1 e non in 1.0. Il motivo principale è il codice. Il valore di Bubo sta nelle parti che parlano con Claude Code: Quota, Cronologia CLI, Memoria di Progetto, Plugin, Agenti, Regole di permesso, Sandbox e copia delle conversazioni. Sono circa 13.000 righe di Swift su 55.000, più tutto il bridge (4.400 righe). Un secondo motore di Sessione (b) le dovrebbe rifare una per una oppure lasciarle vuote. Un motore unico a scelta (c) costa quanto (b) e in più spezza Bubo in due prodotti. Ci sono anche ragioni esterne. Da giugno 2026 GitHub ha un'app desktop sua, la **GitHub Copilot app**, gratuita su tutti i piani da luglio, con Sessioni parallele su worktree, MCP e automazioni [1][2]. A chi usa solo Copilot, una Bubo "anche Copilot" darebbe poco più dell'Orb. Il sandbox locale di Copilot è ancora in public preview [3], ACP pure [4], e il listino è cambiato tre volte nel 2026 ([486-copilot.md](486-copilot.md)). Sul fronte Anthropic, invece, il rischio che giustificava una "copertura" è più basso di quanto si pensasse. La pagina Legal di Claude Code ammette in modo esplicito che l'utente entri col proprio abbonamento nel binario `claude` non modificato, anche quando a ospitarlo è un'altra piattaforma [5]: è proprio lo schema di ADR 0003.

## Le tre opzioni

| | (a) Claude per le Sessioni, Copilot per le Domande | (b) Copilot anche secondo motore di Sessione | (c) Un solo motore, scelto all'onboarding |
|---|---|---|---|
| **Cosa vede l'utente** | "Rifai con… GPT-6 Sol (Copilot)", "Usa sempre per «Scrittura»", ripiego quando la Quota di Claude finisce | Un selettore del motore per Progetto o per Sessione. Quota, Memoria, Plugin, Cronologia CLI cambiano o spariscono secondo il motore | All'onboarding: "Claude" oppure "Copilot". Poi l'app si comporta in modo diverso secondo la scelta |
| **Regola della spec 10** | Invariata: "Le Sessioni restano sempre Claude" | Da riscrivere, insieme a CONTEXT ("le Sessioni sono tutte Claude", Galassia, Macchina "con il suo `claude`") | Da riscrivere, e cambiano ADR 0003 e 0006 |
| **Costo sul codice** (stima, § Costo) | **Piccolo**: ~1.500–2.500 righe con i test, 5–6 ticket | **Grande**: ~10.000–15.000 righe toccate, ogni spec da 01 a 24 con un ramo "e con Copilot?", test raddoppiati | **Grande come (b)**, più due onboarding e due set di Impostazioni |
| **Esperienza** | Coerente: un solo agente, gli altri modelli come "seconda opinione" | Due agenti con poteri diversi nella stessa finestra, per esempio una Sessione Copilot senza Quota né Memoria | Metà degli utenti ha una Bubo ridotta, e non lo sa finché non lo scopre |
| **Costo per l'utente** | Chi ha Copilot spende crediti solo su richiesta: ~1 credito a Domanda | Una Sessione costa 300–1.300 crediti: con Pro (1.500) ne fa da 1 a 5 al mese | Come (b) per chi sceglie Copilot |
| **Privacy** | Il contenuto del Progetto va a GitHub solo con il consenso per fornitore, come già prevede la spec 10 | Tutto il codice e i diff delle Sessioni Copilot vanno a GitHub. Su Free, Pro e Pro+ servono anche all'addestramento, salvo opt-out [6] | Come (b) |
| **Rischio preview** | SDK GA. Solo sessioni senza tool, cioè la parte più stabile | Sandbox locale e ACP in preview, SDK con rilasci settimanali [3][4][7] | Come (b), ma senza un motore di ripiego |
| **Concorrenza** | Nessuno fa "Rifai con…" spiegato | Zed e Xcode sono già multi-motore. Contro la Copilot app si perde | Contro la Copilot app (gratis) e Claude Desktop si perde |

## Costo sul codice

Ho censito il codice per capire quanto è legato a Claude. "Legato" significa che legge `~/.claude`, usa tipi e messaggi dell'Agent SDK oppure nomi di tool di Claude Code (`Bash`, `Edit`, `Write`…).

| Area | Dove | Righe | Legame con Claude | Con Copilot servirebbe |
|---|---|---|---|---|
| **Bridge** | `bridge/src/` (26 moduli) | 4.419 (+1.675 di test) | Totale: `@anthropic-ai/claude-agent-sdk` 0.3.286, `query()`, `canUseTool`, hook `PreToolUse`/`PostToolUse`, `rate_limit_event`, `supportedModels()`, `sessionStore`, `reloadPlugins`, `prewarm` | Un secondo modulo `copilot.ts` con `@github/copilot-sdk`: sessione, eventi, `onPermissionRequest`, hook `onPreToolUse` [7] |
| **Protocollo Swift↔bridge** | `Agent/BridgeMessage.swift` | — | **È la giuntura buona**: `text`, `done`, `progress`, `permission`, `question`, `usage`, `answeredBy` sono neutri. `quota`, `limit`, `configuration`, `history`, `transcript`, `kept`, `sandboxRules`, `pluginsReloaded`, `claude(version:)` sono di Claude | Per le Domande bastano i messaggi neutri. Per le Sessioni servono equivalenti di quasi tutti gli altri |
| **Attività** | `Sessions/Session+Activity.swift`, `AgentProgress` | ~200 | Medio: si basa su `progress` dal bridge | Mappare gli eventi `tool.*`/`session.idle` dell'SDK sugli stessi `AgentProgress`. Fattibile |
| **Account e Quota** | `Account/` (ClaudeCLI, ClaudeLocator, Quota) | 609 | Totale: `claude auth status`, finestre di 5 ore e settimanale | Un `CopilotLocator` e lo stato del login. **La Quota non esiste**: nessuna API documentata dà i crediti residui ([486-copilot.md](486-copilot.md)) |
| **Costi e Budget** | `Costs/` (AnthropicPriceTable, CLIHistoryReader…) | 1.970 | Alto: listino Anthropic, JSONL di `~/.claude/projects` | Listino GitHub in crediti: diventa **Spesa** stimata dai token (1 credito = $0,01). Il Budget funziona già sulla Spesa |
| **Cronologia CLI** | `History/`, `bridge/src/history.ts` | 1.083 | Totale: conversazioni di `claude`, fork con `resume` | `listSessions()` / `resumeSession()` su `~/.copilot/session-state` [7]. Formato e lettore da rifare |
| **Conservazione** (ADR 0006) | `bridge/src/store.ts`, `ConversationStore` | ~300 | Totale: `sessionStore` dell'SDK di Claude (alpha) | Una copia a specchio fatta a mano |
| **Memoria di Progetto** | `Memory/`, `bridge/src/memory.ts` | 913 | Totale: memoria automatica in `~/.claude/projects/<repo>/memory/`, "la stessa che vede la riga di comando" (CONTEXT) | Copilot ha una sua memoria diversa: **non è più "la stessa"**. Oppure una Memoria vuota |
| **Plugin e Marketplace** | `Plugins/` | 4.768 | Totale: plugin di Claude Code (CONTEXT: "un pacchetto di Claude Code") | Non ha senso portarli. Per Copilot, Impostazioni vuote |
| **Agenti** | `Agents/` | 924 | Totale: file `.claude/agents` | `customAgents` dell'SDK, con un altro formato [7] |
| **Permessi e Livello di rischio** | `Permissions/` (RiskClassifier, RuleStore, RequestCenter) | 2.134 | Alto: regole nel formato di Claude Code e nomi dei tool (`Bash`, `Edit`, `Write`, `MultiEdit`…) | Una tabella dei tool di Copilot e regole tradotte. È uno dei punti più delicati, perché il Livello di rischio decide cosa si approva da solo |
| **Sandbox** (spec 22) | `Sandbox/`, `bridge/src/sandbox*.ts` | 444 + 43 | Totale: `Options.sandbox` di Claude Code con `failIfUnavailable` | Il sandbox locale di Copilot (Seatbelt, configurato in `~/.copilot/config`) è in **public preview** dal 2026-06-02 [3][8]. Va tradotta `SandboxPolicy` e serve garantire "mai senza sandbox quando Bubo dice accesa" |
| **Disclaim TCC** (ADR 0005) | `ProcessSpawner` | — | Neutro: il bridge parte già con il disclaim e i suoi figli, `copilot` compreso, non ereditano i permessi di Bubo | Niente |
| **Router e Domande** | `Router/`, `Question/` | 2.461 + 1.772 | Basso: `ModelRouter`, `RetryAlternative`, consensi e Tinta sono già multi-fornitore | Un tipo di risposta in più, "via bridge Copilot", accanto a Claude, Apple FM e OpenAI-compatibile |
| **Macchine e Telecomando** | `Machines/`, `Remote/` | 1.771 | Medio: la Macchina ha "il suo `claude` e il suo login" | Un `copilot` anche sulla Macchina remota |

**Stima (a).** Bridge: `copilot.ts` con sessione senza tool, `listModels`, streaming e conteggio dei token (~250 righe + test). Swift: rilevamento e login di `copilot` (~300), nuovo instradamento nel router con catalogo e Scala dei modelli Copilot (~400), riga del costo in crediti/Spesa (~200), consenso e avviso sull'opt-out (~150), Impostazioni "Collega Copilot" (~300). Totale **~1.500–2.500 righe con i test**. Nessuna area della tabella sopra cambia, tranne Router e Costi.

**Stima (b).** Tutto (a), più una colonna in ogni riga della tabella: ~10.000–15.000 righe toccate tra Swift e bridge. Inoltre ogni spec da 01 a 24 chiede "e con Copilot?". Quattro aree (Quota, Memoria, Plugin, Agenti) non hanno un vero equivalente: diventerebbero "non disponibile con Copilot".

**Stima (c).** Il motore Copilot costa come in (b). Un risparmio c'è (niente selettore per Sessione), ma si aggiungono due onboarding e un'app che cambia comportamento. Poiché chi sceglie Claude esiste comunque, le due strade di codice restano tutte e due.

**ACP come terza via.** In teoria un client ACP in Swift renderebbe Bubo agnostica: Claude passerebbe dall'adattatore ACP, come in Zed, e Copilot da `copilot --acp`. Ma ACP porta il minimo comune denominatore. Non ha `sessionStore`, `rate_limit_event`, `supportedModels`, `reloadPlugins` né hook. Lato Copilot è in preview e non supporta `/resume` [4]. Per Bubo vorrebbe dire perdere proprio le cose che la distinguono. Va tenuto d'occhio, ma non adottato ora.

## Costi per l'utente

Abbonamento Claude: Pro $20/mese, Max da $100/mese (5× o 20× l'uso di Pro). Claude Code è incluso, con limiti a finestre di 5 ore [9]. Copilot: Pro $10 → 1.500 crediti, Pro+ $39 → 7.000, Max $100 → 20.000. Free e Student solo con selezione automatica del modello [10]. Un credito vale $0,01, a listino per token ([486-copilot.md](486-copilot.md)).

Stime nostre, sul listino GitHub:

| Uso | Token | Sonnet 5.5 via Copilot | GPT-5.4 mini via Copilot | Con Copilot Pro (1.500) |
|---|---|---|---|---|
| **Domanda** tipica | 2k in, 500 out | ~0,9 crediti | ~0,4 crediti | ~1.500–3.500 Domande al mese |
| **Turno di Sessione**, cache al 90% | 200k in, 5k out | ~9 crediti | — | — |
| **Turno di Sessione**, senza cache | 200k in, 5k out | ~45 crediti | — | — |
| **Sessione** da 30 turni | — | ~270–1.350 crediti | — | **1–5 Sessioni al mese** |

**Lettura.** Per le Domande Copilot conviene ed è una buona "seconda opinione". Dà GPT, Gemini e Grok con un solo login, senza chiavi OpenAI o Google. Per le Sessioni il conto a token di Copilot Pro finisce in pochi giorni, mentre un abbonamento Claude ha una Quota che si rinnova ogni 5 ore. Chi lavora in Sessioni ha comunque bisogno di Claude, o di Copilot Pro+/Max. E a quel punto ha già la Copilot app [1][2].

## Privacy

| | Claude (Free, Pro, Max) | Copilot Free, Pro, Pro+ | Copilot Business, Enterprise |
|---|---|---|---|
| Addestramento | **Scelta dell'utente**, revocabile. Se attivo, conservazione per 5 anni, altrimenti 30 giorni [11] | **Attivo per default dal 2026-04-24**, salvo opt-out in Impostazioni › Privacy. Condiviso con le affiliate (Microsoft), non con i fornitori dei modelli [6] | Escluso [6] |
| Cosa riceve in (a) | Tutto, come oggi | Solo la Domanda e i suoi Allegati, **con consenso per fornitore** (spec 10) | idem |
| Cosa riceve in (b)/(c) | Tutto | **Codice, diff, output dei comandi** di ogni Sessione Copilot | idem |

La regola della spec 10, "Contenuti del Progetto solo a Claude e ai modelli sul Mac", **regge solo con (a)**. Con (b) va riscritta, e su un piano individuale il default di GitHub manda il codice in addestramento a meno che l'utente non abbia cambiato un'impostazione che Bubo non può leggere.

## Rischio di API in preview

| Pezzo | Stato al 2026-10-03 | Serve per |
|---|---|---|
| Copilot SDK | GA dal 2026-06-02. Rilasci quasi giornalieri: v1.0.16 il 30/09, tre preview v1.0.17 il 02/10 [7][12] | (a), (b), (c) |
| Copilot CLI | v1.0.91 stabile il 01/10, pre-release v1.0.92 il 02/10 [13] | (a), (b), (c) |
| Server ACP della CLI | **Public preview**, "soggetto a cambiamenti"; `/resume`, `/diff`, `/login` non disponibili [4] | (b), (c) via ACP |
| Sandbox locale Copilot | **Public preview** dal 2026-06-02 [3] | (b), (c): senza, salta la promessa della spec 22 |
| API del cloud agent | Public preview ([486-copilot.md](486-copilot.md)) | Fuori perimetro |
| Listino e piani | Tre cambi nel 2026, iscrizioni individuali sospese da aprile a giugno ([486-copilot.md](486-copilot.md)) | Tutte |

Con (a) Bubo usa solo la superficie più stabile: una sessione SDK senza tool, cioè un prompt con risposta in streaming. Se l'SDK cambia, si rompe "Rifai con… Copilot", non una Sessione con un worktree a metà.

## Cosa fanno gli altri client nel 2026

| Client | Modello | Copilot | Claude | Fonte |
|---|---|---|---|---|
| **GitHub Copilot app** | App desktop di GitHub (macOS, Windows, Linux). GA il 2026-06-17, su tutti i piani dal 2026-07-07. Sessioni parallele su branch e worktree, review, MCP, automazioni nel cloud | Motore unico, quello di GitHub | Solo come modello dentro Copilot | [1][2] |
| **Zed** (1.0 dal 29/04/2026) | Agente nativo multi-fornitore, più "External Agents" via ACP: Claude Agent, Codex, Copilot, OpenCode, Cursor, Gemini CLI. Più motori, ma gli esterni hanno meno integrazione ("Zed Agent profiles do not apply") | Sia come modelli nell'agente nativo (partnership) sia come agente esterno | Agente esterno, con il login dell'abbonamento | [14][15] |
| **opencode** | Un solo harness con molti fornitori | Abbonamento Copilot supportato (partnership) | Login Pro/Max **tolto dalla 1.3.0**: "Anthropic explicitly prohibits this". Resta l'API key | [16] |
| **Cline** | Harness proprio | Modelli Copilot tramite la VS Code LM API | API key o fornitori | [486-copilot.md](486-copilot.md) |
| **Xcode 26.3** | Due motori di agente del vendor (Claude Agent SDK e Codex), MCP per gli altri | Estensione separata di GitHub | Claude Agent SDK integrato, con subagenti e plugin | [17] |
| **App macOS ACP** (Poolside Desktop, Capsule…) | "Agent agnostic", worktree, su ACP | Via ACP | Via ACP | [18] |

**Lettura.** Chi è multi-motore (Zed, Xcode, le app ACP) tratta il secondo motore come ospite, con meno funzioni. Chi punta su un'integrazione profonda (Copilot app, Claude Desktop, opencode) ha un solo motore. Bubo ha scelto l'integrazione profonda con Claude Code: Quota, Memoria che è "la stessa della riga di comando", Plugin, Cronologia CLI. Un secondo motore ospite la porterebbe sul terreno di Zed e delle app ACP, dove la Copilot app e Zed sono già più avanti. Il punto in cui Bubo non ha rivali, cioè il router che spiega la scelta e "Rifai con…", guadagna da Copilot proprio con (a).

**Il rischio Anthropic, rivisto.** Dopo il blocco degli harness di terzi (gennaio-aprile 2026) era ragionevole voler Copilot come motore di riserva. La pagina Legal di Claude Code, però, oggi separa i due casi. Vieta di "offrire il login claude.ai" nelle proprie app e di "raccogliere, conservare o intermediare credenziali". Ammette che un utente entri "nel binario Claude Code non modificato con il proprio abbonamento, anche dove una piattaforma ospita Claude Code" [5]. ADR 0003 sta dentro questo perimetro. Il ripiego resta quello già scritto lì: l'API key, che cambia l'onboarding ma non l'architettura. Copilot non serve come assicurazione.

## Raccomandazione

**(a)**: Claude resta l'unico motore delle Sessioni. Copilot diventa un fornitore delle Domande, tramite il Copilot SDK nel bridge e il binario `copilot` dell'utente, con il login fatto da lui (lo schema di ADR 0003).

- **1.0: niente Copilot nel codice.** Si chiude la coda attuale. Si accetta l'ADR 0011 e la spec 10 riceve una riga ("Copilot: fornitore delle Domande dalla 1.1").
- **1.1: Copilot per le Domande.** Cinque o sei ticket:
  1. rilevamento di `copilot` e stato del login, con guida a `brew install copilot-cli` e `copilot login` nel Terminale, come per `claude`, e `GH_TOKEN`/`GITHUB_TOKEN` tolti dall'ambiente del figlio;
  2. `copilot.ts` nel bridge: sessione senza tool, `listModels`, streaming, token per la riga del costo;
  3. il router: "Rifai con…" e "Usa sempre per «Tipo»" sui modelli Copilot, la Scala da `listModels`, mai scelte automatiche né lavoro in background su Copilot (Acceptable Use);
  4. costo come **Spesa** stimata (crediti × $0,01) e Budget per fornitore;
  5. consenso per fornitore e avviso sull'opt-out dall'addestramento sui piani individuali;
  6. Impostazioni "Collega Copilot" e "Scollega".
- **Dopo, solo se succede qualcosa.** Si riapre (b) se si verifica almeno una di queste condizioni: Anthropic chiude il login dell'abbonamento nel binario intatto; ACP v2 e il sandbox di Copilot diventano GA; gli utenti chiedono Sessioni Copilot in modo misurabile (issue, Telecomando, sondaggio). (c) è da scartare.

## Domande per il fondatore

1. **Chi usa solo Copilot è un utente di Bubo?** Con (a) non può aprire Sessioni senza Claude o una API key Anthropic. Accettiamo di perderlo, visto che ha la Copilot app gratis?
2. **Tinta delle Domande via Copilot.** Propongo quella del vendor del modello: GPT via Copilot ha la Tinta OpenAI, Claude via Copilot quella Anthropic. "via Copilot" va nella riga del motivo. CONTEXT dice "una Tinta per fornitore di modelli", e Copilot è un canale, non un fornitore di modelli. D'accordo?
3. **Claude via Copilot nelle Domande.** Se l'utente ha Copilot e chiede "Rifai con Sonnet", si usa la Quota di Claude o i crediti Copilot? Propongo: Claude sempre via `claude`, e Copilot solo per i modelli non Anthropic, salvo una scelta esplicita.
4. **Copilot Free.** Lo supportiamo, con il solo modello automatico, quindi senza Scala né scelta del modello, oppure solo i piani a pagamento come Zed e opencode?
5. **1.1 o "In arrivo"?** CONTEXT riserva "In arrivo" alla v2. Copilot per le Domande lo mettiamo nelle Impostazioni › Aggiornamenti già in 1.0, o lo teniamo fuori finché non c'è?
6. **Partnership con GitHub.** Vale la pena chiederla come Zed e opencode? Per (a) non serve, ma darebbe Domande più leggere senza il processo `copilot`.

## Fonti

1. GitHub Changelog, "GitHub Copilot app generally available" (2026-06-17) — https://github.blog/changelog/2026-06-17-github-copilot-app-generally-available/
2. GitHub Changelog, "GitHub Copilot app available to all" (2026-07-07) — https://github.blog/changelog/2026-07-07-github-copilot-app-available-to-all/
3. GitHub Changelog, "Cloud and local sandboxes for GitHub Copilot now in public preview" (2026-06-02) — https://github.blog/changelog/2026-06-02-cloud-and-local-sandboxes-for-github-copilot-now-in-public-preview/ ; "Local sandboxing in the GitHub Copilot app" (2026-09-23) — https://github.blog/changelog/2026-09-23-local-sandboxing-in-the-github-copilot-app/
4. GitHub Docs, "Copilot CLI ACP server" (consultata il 2026-10-03: "public preview and subject to change") — https://docs.github.com/en/copilot/reference/copilot-cli-reference/acp-server
5. Claude Code Docs, "Legal and compliance" (sezioni "Can customers offer Claude Code in their products?" e "Authentication and credential use", consultata il 2026-10-03) — https://code.claude.com/docs/en/legal-and-compliance ; "Agent SDK overview" (nota sul login claude.ai) — https://code.claude.com/docs/en/agent-sdk/overview
6. GitHub Blog, "Updates to GitHub Copilot interaction data usage policy" (marzo 2026, in vigore dal 2026-04-24) — https://github.blog/news-insights/company-news/updates-to-github-copilot-interaction-data-usage-policy/ ; GitHub Changelog, "Updates to our Privacy Statement and Terms of Service" (2026-03-25) — https://github.blog/changelog/2026-03-25-updates-to-our-privacy-statement-and-terms-of-service-how-we-use-your-data/
7. github/copilot-sdk, README Node (hook `onPreToolUse`/`onPostToolUse`/…, `listSessions`, `resumeSession`, `infiniteSessions` in `~/.copilot/session-state`, `onPermissionRequest`, `reasoningEffort`) — https://github.com/github/copilot-sdk/blob/main/nodejs/README.md
8. GitHub Docs, "Configuring local sandbox settings" — https://docs.github.com/en/copilot/how-tos/cloud-and-local-sandboxes/configuring-local-sandbox-settings ; "Understanding filesystem policies for local sandboxing in GitHub Copilot CLI" — https://docs.github.com/en/copilot/concepts/agents/copilot-cli/understanding-local-sandboxing
9. Claude, "Pricing" (consultata il 2026-10-03) — https://claude.com/pricing
10. GitHub Docs, "Plans for GitHub Copilot" (consultata il 2026-10-03) — https://docs.github.com/en/copilot/get-started/plans
11. Anthropic, "Updates to Consumer Terms and Privacy Policy" — https://www.anthropic.com/news/updates-to-our-consumer-terms ; Privacy Center, "Is my data used for model training?" — https://privacy.claude.com/en/articles/7996868-is-my-data-used-for-model-training
12. github/copilot-sdk, Releases (v1.0.16 del 2026-09-30, v1.0.17-preview.1–3 del 2026-10-02) — https://github.com/github/copilot-sdk/releases
13. github/copilot-cli, Releases (v1.0.91 del 2026-10-01, v1.0.92-1…3 del 2026-10-02) — https://github.com/github/copilot-cli/releases
14. Zed Docs, "External Agents" (consultata il 2026-10-03) — https://zed.dev/docs/ai/external-agents
15. Zed Docs, "Use an Existing Subscription" — https://zed.dev/docs/ai/use-an-existing-subscription ; GitHub Changelog, "GitHub Copilot support in Zed generally available" (2026-02-19) — https://github.blog/changelog/2026-02-19-github-copilot-support-in-zed-generally-available/
16. opencode Docs, "Providers" (sezioni Anthropic e GitHub Copilot, consultata il 2026-10-03) — https://opencode.ai/docs/providers/
17. Apple Newsroom, "Xcode 26.3 unlocks the power of agentic coding" (2026-02-03) — https://www.apple.com/newsroom/2026/02/xcode-26-point-3-unlocks-the-power-of-agentic-coding/
18. Agent Client Protocol, "Clients" — https://agentclientprotocol.com/get-started/clients ; "Agents" — https://agentclientprotocol.com/get-started/agents
