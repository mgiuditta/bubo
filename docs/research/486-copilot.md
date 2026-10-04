# 486 — Bubo con GitHub Copilot

Ticket: [#486](https://github.com/mgiuditta/bubo/issues/486). Collegati: [10 — Router](../features/10-router.md), [ADR 0003](../adr/0003-login-con-la-cli-claude-dell-utente.md).
Ricerca del 2026-10-02, su Copilot CLI **v1.0.91** (rilascio del 2026-10-01) e Copilot SDK GA.

In sintesi: **GitHub Models non esiste più** (ritirato il 30/07/2026, API di inferenza compresa) [1][2], quindi la strada "fornitore nel router via GitHub Models" è chiusa. L'endpoint che usano Zed e opencode (`api.githubcopilot.com`) **non è documentato**: GitHub lo apre a quei client con una "formal partnership" annunciata nel changelog [3][4]. Un client che lo chiama senza accordo, o con il client id OAuth di un altro, sta fuori dalla documentazione. La strada **documentata e consentita** è il binario **`copilot` (Copilot CLI) con il login fatto dall'utente**. Si pilota in due modi: con il **Copilot SDK** (GA dal 2 giugno 2026; Node, Python, Go, .NET, Java, Rust, niente Swift) [5][6], oppure con il **server ACP** (`copilot --acp --stdio`, ancora in public preview) [7]. La doc dell'SDK indica il login dell'utente come metodo "per le applicazioni desktop in cui gli utenti interagiscono direttamente" [8]. La licenza della CLI ne permette anche la ridistribuzione non modificata dentro un'app [9]. È lo stesso schema di ADR 0003, applicato a un altro binario. Ogni prompt consuma **GitHub AI Credits** dell'utente (1 credito = $0,01, prezzi a listino per token) [10][11].

## Ricerca

### Cosa offre GitHub oggi, e con quale stato

| Via | Cos'è | Stato al 2026-10-02 | Autenticazione | Fonte |
|---|---|---|---|---|
| **GitHub Models** (`models.github.ai`, inferenza REST) | Catalogo di modelli con API OpenAI-compatibile | **Ritirato il 30/07/2026**: "playground, catalogo, API di inferenza e BYOK non sono più disponibili per nessun cliente". Era "un servizio separato da GitHub Copilot". In alternativa GitHub indica Microsoft Foundry oppure Copilot | — | [1][2] |
| **Copilot SDK** (`@github/copilot-sdk` e altri) | Libreria che lancia il runtime di Copilot CLI e gli parla in JSON-RPC: sessioni, tool, permessi, MCP, streaming | **GA** (2026-06-02). Licenza MIT. Lingue: Node/TS, Python, Go, .NET, Java, Rust. **Niente Swift** | Utente già loggato (token nel Portachiavi), token OAuth `gho_`/`ghu_`, PAT fine-grained `github_pat_` con permesso "Copilot Requests", variabili d'ambiente, BYOK. I PAT classici `ghp_` non sono accettati | [5][6][8][12] |
| **Copilot CLI** (`copilot`) | Agente da terminale. Modalità programmatica `-p`, `--output-format json` (JSONL), `--model`, `--effort`, `--allow-tool`, `--no-ask-user`, `--resume` | GA. Licenza proprietaria che **permette la ridistribuzione** non modificata come parte di un'applicazione con "funzionalità sostanziale oltre al Software" | `copilot login` (browser o device flow), token nel Portachiavi macOS con servizio `copilot-cli`; variabili d'ambiente; ripiego su `gh auth token` | [9][13][14][15] |
| **Server ACP** della CLI (`copilot --acp --stdio`) | Agent Client Protocol: NDJSON su stdio, `session/new` con `cwd`, streaming `agent_message_chunk`, `requestPermission`, slash command | **Public preview**, "soggetto a cambiamenti". Tool e sforzo si fissano all'avvio del server e valgono per tutte le sessioni. Comandi interattivi come `/diff`, `/resume` e `/login` non sono disponibili | Quella della CLI | [7] |
| **Copilot cloud agent** (agent tasks API) | Task asincrono su GitHub che apre branch e PR: `POST /agents/repos/{owner}/{repo}/tasks` con `prompt`, `base_ref`, `model` | **Public preview** | Solo token user-to-server (PAT, OAuth app, GitHub App user) | [16] |
| **Copilot Extensions** (GitHub App) | Vecchio modo di estendere Copilot Chat | **Spente il 10/11/2025**, sostituite da MCP | — | [17] |
| **`api.githubcopilot.com`** (Copilot Chat API) | Endpoint stile OpenAI/Anthropic che usano gli IDE | **Non documentato** in docs.github.com. Lo usano Zed e opencode con un accordo con GitHub ("formal partnership") [3][4]. Nessuna pagina pubblica dice come ottenere l'accesso | Token OAuth del client registrato | [3][4][18][19] |
| REST API "Copilot" | Solo gestione: metriche, utenti, esclusioni, impostazioni del cloud agent | GA, ma **non fa inferenza** | — | [20] |

**Conseguenza.** Un utente Copilot può dare a Bubo i suoi modelli solo attraverso il **runtime di Copilot**, cioè `copilot` guidato dall'SDK o da ACP. Non esiste più un endpoint OpenAI-compatibile documentato da aggiungere a `OpenAICompatibleEndpoint.known`.

### Modelli e costi per l'utente

Dal 1° giugno 2026 tutti i piani pagano in **GitHub AI Credits**: si contano i token in ingresso, in uscita e in cache ai prezzi di listino di ciascun modello, e **1 credito = $0,01** [10][11][21]. Consumano crediti Chat, **Copilot CLI**, cloud agent, Spaces, Spark e gli agenti di terzi. Completamenti e Next Edit restano esclusi [10]. L'SDK conta "ogni prompt" sul consumo dell'utente Copilot [22].

| Piano | Prezzo | Crediti al mese (base + flex) | Modelli |
|---|---|---|---|
| Copilot Free | gratis | "un'allotment" non quantificata | **solo selezione automatica** |
| Copilot Student | gratis | idem | solo selezione automatica |
| Copilot Pro | $10 | 1.000 + 500 = **1.500** | una selezione di modelli |
| Copilot Pro+ | $39 | 3.900 + 3.100 = **7.000** | modelli premium |
| Copilot Max | $100 | 10.000 + 10.000 = **20.000** | priorità sui premium |
| Business / Enterprise | $19 / $39 a posto | 1.900 / 3.900 per utente, in pool | modelli premium |

Fonti: [10][23]. I crediti non si accumulano da un mese all'altro e si azzerano il 1° del mese alle 00:00 UTC. Finiti quelli inclusi, l'utente passa al piano superiore pagando la differenza, oppure fissa un **budget in dollari** per l'uso aggiuntivo [10]. In modalità automatica sui piani a pagamento c'è il 10% di sconto [10].

Prezzi per milione di token (estratto di [11]):

| Modello | Ingresso | In cache | Uscita |
|---|---|---|---|
| Claude Haiku 4.5 | $1,00 | $0,10 | $5,00 |
| Claude Sonnet 5.5 | $2,00 | $0,20 | $10,00 |
| Claude Opus 5.5 | $4,00 | $0,20 | $20,00 |
| Claude Fable 5.1 | $10,00 | $0,25 | $50,00 |
| GPT-5.4 mini | $0,75 | $0,075 | $4,50 |
| GPT-6 Sol | $2,00 | $0,20 | $10,00 |
| Gemini 3.8 Flash (promo) | $0,75 | $0,075 | $3,75 |
| Grok 4.7 | $2,00 | $0,50 | $6,00 |

**Stima (nostra).** Un turno di Sessione con 200k token in ingresso non in cache e 5k in uscita su Sonnet 5.5 costa circa $0,45, cioè 45 crediti. Con Pro (1.500 crediti) fanno circa 33 turni del genere al mese. Con la cache i costi scendono di molto: l'ingresso in cache costa un decimo. Per un uso da agente, Copilot Pro **non sostituisce un abbonamento Claude Max**. Conviene a chi Copilot lo paga già.

**Accesso ai piani.** Ad aprile 2026 GitHub ha sospeso le nuove iscrizioni ai piani individuali e le ha riaperte a metà giugno. Business ed Enterprise hanno riaperto a settembre [24][25]. Il prezzo e la struttura sono cambiati tre volte nel 2026: è un fornitore instabile.

### Termini d'uso e dati

- **Termini applicabili.** Per i piani individuali vale la Sezione J (AI Features) dei Termini di servizio GitHub. Per Business ed Enterprise acquistati da GitHub valgono i GitHub Generative AI Services Terms [26][27].
- **Addestramento.** Sui piani individuali GitHub può usare Input e Output per addestrare i suoi modelli, **salvo opt-out** nelle impostazioni dell'account. Non li cede ai fornitori di modelli terzi per il loro addestramento [27]. Questo cozza con la regola di Bubo "contenuti del Progetto solo a Claude e ai modelli sul Mac" (spec 10, Privacy).
- **App di terzi con il login dell'utente.** Nessuna clausola la vieta. La doc dell'SDK la descrive come caso d'uso tipico ("Desktop applications where users interact directly") [8], e la licenza della CLI permette di includerla [9]. Per un'app open source come Bubo c'è un vincolo: l'OAuth App "propria" richiede un client secret [12], che non si può distribuire in modo sicuro dentro un'app desktop open source. Il login fatto dalla CLI evita il problema.
- **Uso automatico eccessivo.** Le Acceptable Use Policies vietano "attività automatica eccessiva in blocco" e il "carico indebito" sui server [28]. Il progetto non ufficiale `copilot-api`, un proxy fatto per reverse engineering, riporta avvisi di GitHub Security e sospensioni dell'accesso a Copilot per gli account che lo usano in modo intensivo [29]. Per Bubo vuol dire: niente richieste in background, né batch, né classificazioni su Copilot.

### Come lo fanno gli altri client

| Client | Come usa Copilot | Ufficiale? | Fonte |
|---|---|---|---|
| **Zed** | Provider "GitHub Copilot Chat": chiama `api.githubcopilot.com` direttamente, con header `Editor-Version: Zed/…`, `X-Initiator`, `OpenAI-Intent` e token OAuth nel suo gestore di credenziali. Gli agenti esterni (CLI, ACP) "li gestisce il loro harness" | **Sì, per partnership**: "GitHub Copilot now fully supports authentication with Zed through a formal partnership", solo per i piani a pagamento | [3][30][31] |
| **opencode** | `/connect` → device flow con il **proprio** client id OAuth (`Ov23li8tweQw6odWQebz`), poi `api.githubcopilot.com` con `User-Agent: opencode/…` | **Sì, per partnership** (2026-01-16). Prima era "unofficial" | [4][19] |
| **Kilo Code** | Fork di opencode: **stesso file e stesso client id di opencode** | **Non documentato**: l'annuncio di GitHub nomina opencode, non Kilo | [32] |
| **Cline** | "VS Code LM API": usa i modelli che l'estensione Copilot espone in VS Code tramite `vscode.lm`. Nel nuovo SDK elenca anche `api.githubcopilot.com` (da models.dev) | API di VS Code sì (marcata "sperimentale"). La chiamata diretta fuori da VS Code non risulta concordata | [33][34] |
| **Continue** | Nessun provider Copilot trovato nel repo (ricerca di `githubcopilot` vuota): usa chiavi proprie | — | [35] |
| **Xcode 26** | Copilot arriva come **estensione separata di GitHub** ("GitHub Copilot for Xcode", con agent mode e MCP), non come fornitore di Coding Intelligence. Xcode 26.3 integra Claude Agent e Codex, ed espone MCP per altri agenti; Copilot non compare | Estensione di GitHub, ufficiale | [36][37][38] |
| Decine di altri progetti | Riusano il client id di opencode o quello storico dell'estensione Copilot di VS Code (`Iv1.b507a08c87ecfe98`) per chiamare `api.githubcopilot.com` | **No**: ci si presenta come un altro client | ricerca di codice su GitHub [39] |

**Lettura.** Chi ha l'accesso diretto all'API ha un accordo con GitHub. Chi non ce l'ha usa il runtime ufficiale (CLI, SDK, ACP), passa da VS Code, oppure si fa passare per un altro client. Per Bubo, che con ADR 0003 ha scelto "binario intatto, login dell'utente, nessun token intermediato", l'unica forma coerente è la prima.

### Come entrerebbe in Bubo

Bubo ha già un **bridge Node** (`bridge/`, `@anthropic-ai/claude-agent-sdk` 0.3.286) che pilota `claude`, e un solo client OpenAI-compatibile per le Domande (`Router/OpenAICompatibleClient`, `OpenAICompatibleEndpoint.Kind`).

| Uso | Come | Corrispondenze con Bubo | Cosa manca |
|---|---|---|---|
| **Domanda** ("Rifai con… Copilot", preferenza per Tipo) | Sessione SDK senza tool (`availableTools: []`), `model` scelto, streaming del testo | Non è un `OpenAICompatibleEndpoint`: serve un tipo di risposta in più nel router, che passa dal bridge, accanto a Claude e Apple FM. `listModels()` fa da catalogo, come `supportedModels()` per la Scala [12] | La **Tinta** va decisa: è quella di "Copilot" o quella del vendor del modello? Il **costo** si stima dai token sul listino [11]; manca un'API documentata per i crediti residui (l'SDK non la elenca; la CLI ha `/usage`) |
| **Sessione** (motore alternativo a `claude`) | Copilot SDK nel bridge: `createSession({ workingDirectory, model, reasoningEffort, onPermissionRequest })`, `resumeSession`, `setModel`, `abort`, eventi in streaming [12] | Il **worktree** lo crea Bubo, e a Copilot basta la cartella. Le **Richieste di permesso** passano da `onPermissionRequest` (o da `requestPermission` in ACP). Ripresa e fork con `resumeSession`. Lo sforzo ha gli stessi livelli (`low`…`max`) | Tutta la parte di Claude da rifare su un secondo motore: Attività, Quota, Cronologia CLI (`~/.copilot`), Sandbox (ADR 0005), hook, Memoria. È il pezzo grosso |
| **Delega al cloud agent** | `POST /agents/repos/{o}/{r}/tasks` con il token di `gh` (Bubo usa già `gh`, `Integrations/GitHubCLI.swift`) | Si appoggia a Board e Bozze: "Avvia su Copilot" crea una PR | Public preview. Non è una Sessione locale |

**SDK o ACP.** L'SDK è GA ed è già in Node, dove sta il bridge. Dà `listModels`, sforzo per sessione, permessi per sessione e ripresa. ACP evita Node, perché Swift legge NDJSON da solo, ed è uno standard aperto che vale anche per altri agenti (Gemini CLI, Codex…). Però è in preview, tool e sforzo valgono per tutto il server, e `/resume` non c'è [7]. Oggi conviene l'SDK. ACP va tenuto d'occhio come strada generica a "più agenti".

**Binario dell'utente o incluso.** Per coerenza con ADR 0003: l'utente installa `copilot` (`brew install copilot-cli` [15]) e fa `copilot login`, e Bubo lancia quel binario tramite `RuntimeConnection.forStdio({ path })` o `COPILOT_CLI_PATH`, senza leggere, salvare o copiare token. Lo stato dell'account si legge solo dalla CLI. L'alternativa, cioè incluso nell'app, è ammessa dalla licenza [9], ma lascia a Bubo il peso del binario e dei suoi aggiornamenti, che escono quasi ogni giorno [13]. Attenzione a un dettaglio: la CLI dà precedenza a `GH_TOKEN`/`GITHUB_TOKEN` sul login salvato [14]. Il bridge deve togliere queste variabili dall'ambiente del figlio (`ChildEnvironment` costruisce già da zero l'ambiente di `claude`), altrimenti si usa senza volerlo il token di `gh`.

## Rischi e casi limite

- **Endpoint non documentati.** `api.githubcopilot.com` con un client id preso in prestito equivale a presentarsi come VS Code o opencode. Non c'è un divieto scritto e pubblico, ma nemmeno un permesso, e c'è il rischio concreto di sospensione per abuso [28][29]. **Da evitare.**
- **Preview.** ACP e agent tasks API sono in preview [7][16]. L'SDK è GA, ma cambia in fretta (CLI alla 1.0.91, aggiornata ogni giorno [13]).
- **Privacy.** Sui piani individuali i contenuti del Progetto mandati a Copilot possono finire nell'addestramento, salvo opt-out [27]. Servono il consenso per fornitore già previsto dalla spec 10 e un avviso sull'opt-out.
- **Copilot Free**: solo selezione automatica del modello [10]. Il router non può scegliere né il modello né la Scala. Zed e opencode supportano solo i piani a pagamento [3][4].
- **Variabili d'ambiente** che scavalcano il login [14].
- **Costi**: i crediti non dicono "quanto resta" su un'API documentata. Il Budget di Bubo (spec 18) può solo stimare dai token.
- **Prezzi instabili**: tre cambi di piano nel 2026 [21][24][25].
- **Uso in background**: niente classificazione, Jev o Varianti su Copilot. Solo richieste esplicite dell'utente.

## Domande per il fondatore

1. La spec 10 dice "le Sessioni restano sempre Claude". Accettiamo un **secondo motore di Sessione** (Copilot via SDK)? Se sì serve un ADR: è una scelta difficile da tornare indietro.
2. **Privacy**: Copilot entra tra i cloud che possono ricevere contenuti del Progetto, con consenso per fornitore e avviso sull'opt-out dall'addestramento?
3. `copilot` **installato dall'utente** (come `claude`, ADR 0003) o **incluso** nell'app (permesso dalla licenza)?
4. **SDK nel bridge Node** (GA) o **ACP da Swift** (preview, ma generico per altri agenti)?
5. **Copilot Free** supportato (solo modello automatico) o solo i piani a pagamento, come Zed e opencode?
6. Vale la pena chiedere a GitHub una **partnership** come Zed e opencode, per l'accesso diretto all'API? Servirebbe solo per Domande più leggere: la via ufficiale funziona anche senza.
7. La **delega al cloud agent** da Board/Bozza è nel perimetro, o resta fuori?
8. **Tinta**: Copilot ha una sua Tinta, o vale quella del vendor del modello (Claude via Copilot = Tinta Anthropic)?

## Fonti

1. GitHub Docs, "GitHub Models" (pagina di ritiro) — https://docs.github.com/en/github-models
2. GitHub Changelog, "GitHub Models is being fully retired on July 30, 2026" (2026-07-01) — https://github.blog/changelog/2026-07-01-github-models-is-being-fully-retired-on-july-30-2026/ ; "GitHub Models is now retired" (2026-07-30) — https://github.blog/changelog/2026-07-30-github-models-is-now-retired/
3. GitHub Changelog, "GitHub Copilot support in Zed generally available" (2026-02-19) — https://github.blog/changelog/2026-02-19-github-copilot-support-in-zed-generally-available/
4. GitHub Changelog, "GitHub Copilot now supports OpenCode" (2026-01-16) — https://github.blog/changelog/2026-01-16-github-copilot-now-supports-opencode/
5. GitHub Changelog, "Copilot SDK is now generally available" (2026-06-02) — https://github.blog/changelog/2026-06-02-copilot-sdk-is-now-generally-available/
6. github/copilot-sdk (README, licenza MIT) — https://github.com/github/copilot-sdk
7. GitHub Docs, "Copilot CLI ACP server" — https://docs.github.com/en/copilot/reference/copilot-cli-reference/acp-server
8. GitHub Docs, "Authentication" (Copilot SDK) — https://docs.github.com/en/copilot/how-tos/copilot-sdk/auth/authenticate
9. github/copilot-cli, "GitHub Copilot CLI License" — https://github.com/github/copilot-cli/blob/main/LICENSE.md
10. GitHub Docs, "Usage-based billing for individuals" — https://docs.github.com/en/copilot/concepts/billing-and-usage/individuals/billing
11. GitHub Docs, "Models and pricing for GitHub Copilot" — https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing
12. GitHub Docs, "GitHub OAuth setup" (Copilot SDK) — https://docs.github.com/en/copilot/how-tos/copilot-sdk/setup/github-oauth ; README Node dell'SDK (opzioni `RuntimeConnection`, `useLoggedInUser`, `reasoningEffort`, `onPermissionRequest`, `resumeSession`, `listModels`) — https://github.com/github/copilot-sdk/blob/main/nodejs/README.md
13. GitHub Docs, "Running GitHub Copilot CLI programmatically" — https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/run-cli-programmatically ; "Copilot CLI programmatic reference" — https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-programmatic-reference ; release v1.0.91 — https://github.com/github/copilot-cli/releases
14. GitHub Docs, "Authenticating GitHub Copilot CLI" — https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli
15. github/copilot-cli, README (installazione) — https://github.com/github/copilot-cli
16. GitHub Docs, "Using Copilot cloud agent via the API" — https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent/use-cloud-agent-via-the-api
17. GitHub Changelog, "Sunset notice: GitHub App-based Copilot Extensions" (2025-09-24) — https://github.blog/changelog/2025-09-24-deprecate-github-copilot-extensions-github-apps/
18. Zed, `crates/copilot_chat/src/copilot_chat.rs` — https://github.com/zed-industries/zed/blob/main/crates/copilot_chat/src/copilot_chat.rs
19. opencode, `packages/opencode/src/plugin/github-copilot/copilot.ts` — https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/plugin/github-copilot/copilot.ts
20. GitHub Docs, "REST API endpoints for Copilot" — https://docs.github.com/en/rest/copilot
21. GitHub Changelog, "Updates to GitHub Copilot billing and plans" (2026-06-01) — https://github.blog/changelog/2026-06-01-updates-to-github-copilot-billing-and-plans/ ; GitHub Blog, "GitHub Copilot is moving to usage-based billing" — https://github.blog/news-insights/product-news/github-copilot-is-moving-to-usage-based-billing/
22. GitHub Changelog, "Copilot SDK in public preview" (2026-04-02) — https://github.blog/changelog/2026-04-02-copilot-sdk-in-public-preview/
23. GitHub Docs, "Plans for GitHub Copilot" — https://docs.github.com/en/copilot/get-started/plans
24. GitHub Changelog, "Copilot individual plan sign-ups are reopening" (2026-06-17) — https://github.blog/changelog/2026-06-17-copilot-individual-plan-sign-ups-are-reopening/
25. GitHub Changelog, "Upcoming changes to GitHub Copilot policies and billing" (2026-08-28) — https://github.blog/changelog/2026-08-28-upcoming-changes-to-github-copilot-policies-and-billing/
26. GitHub Docs, "GitHub Terms for Additional Products and Features" (sezione GitHub Copilot) — https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features
27. GitHub Docs, "GitHub Terms of Service", Sezione J — https://docs.github.com/en/site-policy/github-terms/github-terms-of-service#j-ai-features-training-and-your-data
28. GitHub Docs, "GitHub Acceptable Use Policies", §4 — https://docs.github.com/en/site-policy/acceptable-use-policies/github-acceptable-use-policies
29. ericc-ch/copilot-api, README (avvisi "reverse-engineered" e "GitHub Security Notice") — https://github.com/ericc-ch/copilot-api
30. Zed Docs, "Use an Existing Subscription" — https://zed.dev/docs/ai/use-an-existing-subscription
31. Zed Blog, "What GitHub Copilot's Usage-Based Billing Means for Zed Users" — https://zed.dev/blog/github-copilot-usage-based-billing
32. Kilo Code, `packages/opencode/src/plugin/github-copilot/copilot.ts` — https://github.com/Kilo-Org/kilocode
33. Cline Docs, "VS Code Language Model API" — https://docs.cline.bot/provider-config/vscode-language-model-api
34. Cline, `sdk/packages/llms/src/providers/providers.generated.ts` — https://github.com/cline/cline
35. continuedev/continue (ricerca di `githubcopilot` nel codice, nessun risultato) — https://github.com/continuedev/continue
36. Apple Newsroom, "Xcode 26.3 unlocks the power of agentic coding" (2026-02-03) — https://www.apple.com/newsroom/2026/02/xcode-26-point-3-unlocks-the-power-of-agentic-coding/
37. GitHub Changelog, "Agent mode and MCP support for Copilot in JetBrains, Eclipse, and Xcode now in public preview" (2025-05-19) — https://github.blog/changelog/2025-05-19-agent-mode-and-mcp-support-for-copilot-in-jetbrains-eclipse-and-xcode-now-in-public-preview/
38. github/CopilotForXcode — https://github.com/github/CopilotForXcode
39. Ricerca di codice su GitHub di `Ov23li8tweQw6odWQebz` e `Iv1.b507a08c87ecfe98` (2026-10-02) — https://github.com/search?q=Iv1.b507a08c87ecfe98&type=code
