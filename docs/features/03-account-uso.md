# 03 — Account, login e uso visibile

Feature: login con l'abbonamento Claude dalla CLI, API key, fallback, uso visibile.
Ricerca per l'issue #14 (mappa #11). Data: 2026-09-29. Base: la ricerca dell'issue #2 ([abbonamento-claude.md](https://github.com/mgiuditta/bubo/blob/research/abbonamento-claude/docs/research/abbonamento-claude.md)).
Le citazioni restano in inglese come nell'originale. Dove una fonte non è primaria lo dico.

## Ricerca

### Quadro comune

Quasi tutti i concorrenti fanno la stessa cosa: **non gestiscono il login**. Avviano il binario `claude` ufficiale, che usa il login già salvato nel Portachiavi. L'API key entra con `ANTHROPIC_API_KEY`. Nessuno di loro fa un vero fallback automatico abbonamento → API key.

Sull'uso le strade sono tre:

1. **Endpoint non documentato** `https://api.anthropic.com/api/oauth/usage`. L'app legge il token OAuth di Claude Code dal Portachiavi (o da `~/.claude/.credentials.json`) e lo interroga. Lo fanno Nimbalyst, Superset e CodexBar.
2. **Log locali** in `~/.claude/projects/*.jsonl`, con prezzi API. Lo fanno opcode, ClaudeGUI (markes76), T3 Code, ccusage. Danno token e costi stimati, non la quota residua.
3. **Dati del binario stesso** (`/usage`, `rate_limit_event`, status line). Lo fanno l'app ufficiale e, come ripiego, CodexBar.

### App desktop ufficiale (Claude Desktop, scheda Code)

- **Login.** Si entra nell'app con l'account Claude, con il flusso Anthropic. Bedrock, Agent Platform e Foundry sono configurazioni enterprise a parte ([desktop](https://code.claude.com/docs/en/desktop)).
- **Uso.** Un "usage ring" accanto al selettore del modello. Con un clic mostra il contesto della sessione e l'uso del piano nel periodo. L'uso del piano è condiviso fra tutte le superfici Claude Code ([desktop#check-usage](https://code.claude.com/docs/en/desktop#check-usage)).
- **Limite raggiunto.** Compare una card. Per il limite di sessione c'è la casella **Auto-continue when limits reset**, che ripete il turno dopo il reset. Per il limite settimanale la casella non c'è ([errors#usage-limits](https://code.claude.com/docs/en/errors#usage-limits)). I crediti extra si attivano con un consenso esplicito (`/usage-credits`).
- **Cosa piace.** È l'unico con i dati "veri", senza trucchi. Il ring è sempre a portata.
- **Cosa manca.** Serve un clic per leggere i numeri. Niente API key come ripiego: la scheda Code in modalità API key richiede la configurazione "Claude Desktop on 3P". Nessun avviso proattivo documentato oltre i messaggi a soglia (`You've used 85% of your session limit`).
- **Termini.** Nessun problema: è l'app nativa di Anthropic.

### Conductor

- **Login.** "By default, Conductor uses the auth tokens already saved on your machine. If you're logged into Claude Code with an API key, Conductor uses that; if you're logged in with Claude Pro or Max, Conductor uses that." Si può forzare la modalità API key in Settings → Harnesses. Per accedere si esegue `claude /login` ([docs Conductor, llms-full](https://www.conductor.build/llms-full.txt), [providers](https://www.conductor.build/docs/guides/providers)). Claude Code è incluso nell'app.
- **Avviso sui costi.** La doc avverte che con `ANTHROPIC_API_KEY` nell'ambiente "Claude Code may use that API key instead of Claude subscription usage. That can result in API charges" ([harness Claude Code](https://www.conductor.build/docs/reference/harnesses/claude-code)).
- **Uso.** Dalla 0.86.0 (16/09/2026): "The context usage popover shows Claude account limits and reset times, matching Codex" ([changelog](https://www.conductor.build/changelog)). Prima rimandava a `/status`.
- **Cloud.** Conductor Cloud chiede "a personal subscription token or API key", e dalla 0.85.0 si sceglie per organizzazione se Claude Code usa API key o abbonamento. Quindi il token di abbonamento lo custodisce Conductor. È proprio il caso che la pagina legale vieta ("collect, store, or intermediate"), salvo accordi che non conosciamo.
- **Termini.** Conductor è stato citato fra le app toccate dal piano di maggio sui crediti Agent SDK (VentureBeat, fonte secondaria). Non ho trovato blocchi né comunicazioni ufficiali su Conductor.
- **Cosa manca.** Nessun fallback automatico, nessun avviso proattivo documentato.

### Nimbalyst (ex Crystal)

- **Login.** Usa le CLI già autenticate: "authenticates both providers through their existing CLIs" ([developersdigest](https://www.developersdigest.tech/blog/nimbalyst-visual-workspace-codex-claude-code), secondaria). In Settings → Claude Code i pulsanti Login e Logout aprono il Terminale con `osascript`. Su macOS 26 falliscono in silenzio per un entitlement mancante ([#57](https://github.com/nimbalyst/nimbalyst/issues/57)). L'app ha anche un suo login (Stytch).
- **Uso.** Un anello di 32×32 pt nella barra laterale con la finestra di 5 ore, più un pannello. Il servizio `ClaudeUsageService.ts` legge il token OAuth dal Portachiavi e chiama `api.anthropic.com/api/oauth/usage` **ogni 30 minuti**, solo quando c'è attività ([codice](https://github.com/nimbalyst/nimbalyst/blob/ac40c06e21950c0b7548c34ab38294a989b56595/packages/electron/src/main/services/ClaudeUsageService.ts)).
- **Cosa lamentano.**
  - A limite raggiunto la sessione "just quietly stops/fails without a clear message" ([#788](https://github.com/nimbalyst/nimbalyst/issues/788)).
  - Chiedono di riprendere da soli dopo il reset ([#650](https://github.com/nimbalyst/nimbalyst/issues/650)) e di programmare un prompt "when the usage limit resets" ([#1497](https://github.com/nimbalyst/nimbalyst/issues/1497)).
  - Il widget non trova le credenziali perché legge il file e ignora il Portachiavi ([#1470](https://github.com/nimbalyst/nimbalyst/issues/1470)).
  - L'anello mostra solo la finestra di 5 ore; chiedono anelli annidati per la settimanale ([#1509](https://github.com/nimbalyst/nimbalyst/issues/1509)).
  - Chiedono l'uso della CLI accanto a quello dell'app ([#865](https://github.com/nimbalyst/nimbalyst/issues/865)), più account ([#573](https://github.com/nimbalyst/nimbalyst/issues/573)) e il passaggio da abbonamento a Foundry per sessione ([#1490](https://github.com/nimbalyst/nimbalyst/issues/1490)).
  - "extremely token-greedy" ([#889](https://github.com/nimbalyst/nimbalyst/issues/889)).
- **Termini.** Legge e usa il token OAuth di Claude Code fuori dal binario. È in contrasto con "may not collect, store, or intermediate Claude.ai credentials or session tokens". Non ho trovato blocchi pubblici.

### opcode (ex Claudia)

- **Login.** Usa la CLI `claude` installata e il suo login.
- **Uso.** "Usage Analytics Dashboard" con costi e token per modello, progetto e periodo, calcolati dai log locali ([README](https://github.com/winfunc/opcode)). Non mostra la quota del piano.
- **Cosa lamentano.** Avviso "approaching usage limit" dopo circa 20 minuti in opcode, mentre in VS Code no ([#208](https://github.com/winfunc/opcode/issues/208)). "Credit balance too low" con un Pro attivo, cioè una API key nell'ambiente che vince sull'abbonamento ([#77](https://github.com/winfunc/opcode/issues/77)). Costi diversi sullo stesso account su due macchine ([#133](https://github.com/winfunc/opcode/issues/133)). Messaggi elaborati due volte, quindi token doppi ([#390](https://github.com/winfunc/opcode/issues/390)).
- **Termini.** Nessun problema noto: non tocca le credenziali.

### Sculptor (Imbue)

- **Login.** Avvia Claude Code (e l'harness Pi) nel workspace, con il login esistente. La doc parla solo di login per Pi ([integrated_harnesses](https://github.com/imbue-ai/sculptor/blob/main/docs/help/integrated_harnesses.md)).
- **Uso.** Mostra solo la percentuale di contesto a fine turno. Quota e costi non sono documentati.
- **Termini.** Nessun problema noto.

### Superset

- **Login.** È un terminale che avvia le CLI (`claude` ecc.) con i loro login ([docs](https://www.mintlify.com/superset-sh/superset/concepts/agents)).
- **Uso.** C'è una pagina Usage (`/settings/usage`). Il codice legge il token dal Portachiavi e chiama gli endpoint non documentati `oauth/usage` e `oauth/profile` ([claude.ts](https://github.com/superset-sh/superset/blob/main/packages/host-service/src/trpc/router/usage/claude.ts)). La proposta originale prevede polling ogni 5 minuti, avvisi all'80% e al 95%, icona nella barra dei menu e backoff sui 429 ([#5733](https://github.com/superset-sh/superset/issues/5733)).
- **Cosa lamentano.** Nella 1.25.1 il pulsante Usage è finito dentro Impostazioni: "turns a glance into a detour" ([#7096](https://github.com/superset-sh/superset/issues/7096)). Chiedono più account per provider ([#6903](https://github.com/superset-sh/superset/issues/6903)).
- **Cosa vogliono gli utenti.** L'analisi interna del feedback su X ([piano](https://github.com/superset-sh/superset/blob/main/plans/20260815-token-spend-twitter-feedback.md)) conclude: "quota/limit % (5h session + weekly reset) matters more than raw token counts". Chi usa Superset controlla `/usage` "several times a day" o usa CodexBar e runway. Un utente scrive su Slack e non su X per paura di un ban per violazione dei termini: gli utenti sanno che questi tracker sono in zona grigia.

### CodeAgentSwarm

- **Login.** App desktop che ospita più terminali, ognuno con la sua CLI e il suo login ([guida](https://www.codeagentswarm.com/en/guides/claude-code-agent-swarm)).
- **Uso.** Nelle pagine pubbliche non ho trovato una vista su quota o costi. Il sito ha risposto 429 a parte delle richieste.

### ClaudeGUI

Il nome copre più progetti piccoli:
- **Tenvy** (repo `Rostmen/ClaudeGUI`, Swift 6, macOS 26, 2 stelle). Gestisce sessioni dai file in `~/.claude/projects/`, con terminale incorporato. Niente login né quota.
- **Claude Code GUI** (markes76, 34 stelle). Supporta sia `ANTHROPIC_API_KEY` sia `claude login`, con cruscotto di token e costi dai log locali ([repo](https://github.com/markes76/claude-code-gui)).

### Agentic Stack Desktop

App nativa macOS (71 stelle). Il README dice: "Agent execution uses the official Claude Code and Codex CLIs and their existing accounts. Agentic Stack does not copy provider tokens or implement a substitute OAuth client" ([README](https://github.com/codejunkie99/agentic-stack-desktop)). È l'unico a dichiarare per iscritto la regola che serve a Bubo. Non mostra la quota.

### Strumenti di uso a parte (riferimento)

- **CodexBar** (22.050 stelle, Swift, barra dei menu). Tre fonti in ordine: OAuth API, poi `/usage` letto da un PTY, poi i cookie di claude.ai. Mostra la finestra di 5 ore, la settimanale, i limiti per modello e i crediti extra. Aggiorna al massimo ogni 60 s. Chiede l'accesso al Portachiavi "Only on user action" ([doc](https://mintlify.wiki/steipete/codexbar/providers/claude)).
- **runway** (24 stelle). Più account per provider, indicatore di ritmo ("pace") e spesa stimata (dal piano di Superset sopra).
- **ccusage.** Report da JSONL locali. Non garantisce l'esattezza dei costi ([npm](https://npmjs.com/package/ccusage)).
- **T3 Code.** Pagina di uso con costi e token da Claude Code e Codex, dai log locali (dal piano di Superset).

### Numeri misurabili trovati

| Concorrente | Clic per vedere la quota | Aggiornamento | Finestre mostrate |
|---|---|---|---|
| App ufficiale | 1 (ring) | dal binario | periodo del piano |
| Conductor 0.86 | 1 (popover) | non documentato | limiti e reset |
| Nimbalyst | 0 per la 5 h, 1 per il resto | 30 min | 5 h nell'anello |
| Superset 1.25.1 | 2+ (Impostazioni) | proposta: 5 min | 5 h, settimanale |
| CodexBar | 1 (menu) | ≥ 60 s | 5 h, settimanale, per modello, crediti |
| opcode, ClaudeGUI, T3 | — | log locali | solo token e costi |

Tempi e RAM legati a questa feature non sono pubblicati da nessuno.

## Stato dei termini Anthropic ad oggi

**Cronologia** (le fonti secondarie sono segnate come tali):

| Data | Evento | Fonte |
|---|---|---|
| 09/01/2026 | Blocco lato server dei token OAuth di abbonamento fuori da Claude Code e claude.ai. Colpiti OpenCode, Cline, RooCode, OpenClaw, cioè gli strumenti che imitavano il client. Errore: "This credential is only authorized for use with Claude Code". | [VentureBeat](https://venturebeat.com/ai/anthropic-cracks-down-on-unauthorized-claude-usage-by-third-party-harnesses/), [falcao.org](https://falcao.org/posts/anthropic-claude-access-crackdown-ecosystem-fallout/) (secondarie) |
| febbraio 2026 | Testo esplicito su OAuth nella pagina legale di Claude Code. I Consumer Terms restano quelli dell'8/10/2025. | [legal-and-compliance](https://code.claude.com/docs/en/legal-and-compliance), [consumer-terms](https://www.anthropic.com/legal/consumer-terms) |
| 19/03/2026 | Richieste legali a OpenCode, che rimuove l'integrazione Anthropic. | falcao.org (secondaria) |
| 04/04/2026 | Stop all'uso dell'abbonamento negli harness di terzi, con un credito una tantum. | [TechRadar](https://www.techradar.com/pro/bad-news-claude-users-anthropic-says-youll-need-to-pay-to-use-openclaw-now) (secondaria) |
| 13/05/2026 | Annuncio dei crediti Agent SDK (20/100/200 $) dal 15/06. Citate OpenClaw, Conductor, T3 Code, Zed, Jean. | [@ClaudeDevs](https://x.com/ClaudeDevs/status/2054610152817619388), [VentureBeat](https://venturebeat.com/technology/anthropic-reinstates-openclaw-and-third-party-agent-usage-on-claude-subscriptions-with-a-catch) |
| 15/06/2026 | **Sospeso.** "Claude Agent SDK, `claude -p`, and third-party app usage still draw from your subscription's usage limits." | [support 15036540](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan) (aggiornata il 16/06) |
| 16/06/2026 | Zed conferma: ACP, `claude -p`, Agent SDK e app di terzi "continue to work with Claude subscriptions exactly as they did before". | [blog Zed](https://zed.dev/blog/anthropic-subscription-changes) |
| 29/09/2026 | Nessuna novità ufficiale dopo il 16/06. La pagina di supporto è ancora quella. | verifica diretta |

**Testi in vigore oggi:**

- Agent SDK overview: "Unless previously approved, Anthropic does not allow third party developers to offer claude.ai login or rate limits for their products, including agents built on the Claude Agent SDK." ([overview](https://code.claude.com/docs/en/agent-sdk/overview))
- Legal and compliance: "Anthropic does not permit third-party developers to offer Claude.ai login into their own applications [...] developers may not collect, store, or intermediate Claude.ai credentials or session tokens — sign-in to a Claude account must complete through Anthropic's own flow." Resta lo spiraglio: "Nor does it prevent an end user from signing in to the unmodified Claude Code binary with their own Claude subscription".
- Stessa pagina: "Advertised usage limits for Pro and Max plans assume ordinary, individual usage of Claude Code and the Agent SDK."

**Come leggerlo per Bubo:**

- Avviare il binario `claude` non modificato con il login fatto dall'utente in Terminale è il caso di Conductor, Superset, Sculptor e Agentic Stack. Nessuno di loro risulta bloccato.
- Mostrare "Accedi con Claude" dentro Bubo resta il caso vietato dall'SDK senza approvazione.
- **Leggere il token dal Portachiavi per interrogare `oauth/usage`** (Nimbalyst, Superset, CodexBar) è in contrasto diretto con "collect [...] session tokens". Inoltre l'endpoint non è documentato e può cambiare. Bubo non deve farlo.
- Il "rate limits" in "offer claude.ai login or rate limits" fa pensare che anche mostrare i limiti dell'abbonamento come funzione del prodotto sia delicato. Mostrare ciò che il binario già emette (`rate_limit_event`) è il modo più prudente.

## API coinvolte

| Cosa | API | Note |
|---|---|---|
| CLI installata | `claude --version` | cercare nel PATH |
| Login e piano | `claude auth status` (JSON, exit 0/1) | chiavi `loggedIn`, `authMethod`, `email`, `orgName`, `subscriptionType`, `configDirectory` (`configDirectory` dalla 2.1.268, [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)). Nessun token. |
| Login e logout | `claude auth login [--claudeai\|--console]`, `claude auth logout` | flusso nel browser di Anthropic. Accetta anche il codice incollato quando il callback su localhost non funziona. |
| Account a sessione avviata | `query.accountInfo()` → `AccountInfo { email, organization, subscriptionType, tokenSource, apiKeySource }` | [TS reference](https://code.claude.com/docs/en/agent-sdk/typescript) |
| Flusso di auth nello stream | `SDKAuthStatusMessage { type: "auth_status", isAuthenticating, output[], error? }` | utile per mostrare lo stato del login |
| Quota durante il lavoro | `SDKRateLimitEvent { type: "rate_limit_event", rate_limit_info: { status: "allowed" \| "allowed_warning" \| "rejected", resetsAt?, utilization?, errorCode?: "credits_required", canUserPurchaseCredits?, hasChargeableSavedPaymentMethod? } }` | "Emitted when the session encounters a rate limit". Non dice a quale finestra si riferisce. `credits_required` richiede Claude Code ≥ 2.1.181. |
| Errore del messaggio | `SDKAssistantMessage.error`: `rate_limit` (429 sulla quota), `overloaded` (529), `billing_error`, `authentication_failed`, `oauth_org_not_allowed`, `account_on_hold`, … | distinguere `rate_limit` da `overloaded` |
| Retry dei subagent | `tool_progress.subagent_retry` con `error_category` (`rate_limit`, `overloaded`, …) | per mostrare "in attesa" |
| Costo | `result.total_cost_usd`, `ModelUsage.costUSD` per modello | "client-side estimate", non fattura ([cost-tracking](https://code.claude.com/docs/en/agent-sdk/cost-tracking)). Dalla 2.1.277 i totali di una sessione headless ripresa non ripartono da zero. |
| Modello di riserva | opzione `fallbackModel` (lista separata da virgole) | utile per i limiti Opus e Sonnet, che valgono per famiglia |
| Uso del piano, a richiesta | `/usage` inviato come prompt | testo non strutturato. La CLI usa un "plan-usage endpoint" interno con backoff (CHANGELOG 2.1.284). |
| Status line | campo `rate_limits.five_hour` / `seven_day` con `used_percentage`, `resets_at`; `spend_limit` per i gateway | solo sessione interattiva, Pro e Max ([statusline](https://code.claude.com/docs/en/statusline)) |

**Messaggi di limite** ([errors](https://code.claude.com/docs/en/errors#usage-limits)):
- `You've hit your session limit · resets 3:45pm`, `... weekly limit ...`, `... Opus limit ...`, `... Sonnet limit ...`.
- Avviso prima: `You've used 85% of your session limit · resets 3:45pm`.
- `API Error: Server is temporarily limiting requests (not your usage limit)`: throttle del server, riconosciuto dall'assenza degli header di quota. Dalla 2.1.199 si ritenta da solo.
- `Credit balance is too low`: di solito c'è una `ANTHROPIC_API_KEY` nell'ambiente che vince sull'abbonamento.
- Dalla 2.1.234 la CLI interattiva aspetta il reset e continua da sola ("Continue automatically at usage limit" in `/config`).

**Fallback abbonamento → API key.** Nessun concorrente lo fa in automatico. Tecnicamente per Bubo vuol dire: riconoscere `rate_limit` o `rate_limit_event.status == "rejected"`, chiedere il consenso, riavviare il processo figlio con `ANTHROPIC_API_KEY` impostata e riprendere la sessione (`resume`). Anthropic chiede consenso esplicito per passare ai crediti ("All transitions to API credit usage require explicit user consent"). Lo stesso principio va applicato al passaggio all'API key.

## Il meglio da battere

- **Uso a colpo d'occhio.** Il migliore oggi è l'anello di Nimbalyst (0 clic, ma solo 5 h e aggiornato ogni 30 min). Criterio candidato: finestra di 5 h e settimanale visibili a 0 clic nel Panel o nell'HUD, con orario di reset, aggiornate entro 1 s da ogni `rate_limit_event`.
- **Limite raggiunto.** Il migliore è l'app ufficiale (card + auto-continue, ma solo per la sessione). Criterio: entro 1 s dal rifiuto Bubo mostra causa, orario di reset e 3 scelte (attendi e riprendi, cambia famiglia di modello, passa all'API key con consenso). Nessuno stop silenzioso.
- **Credenziali.** Il migliore è Agentic Stack Desktop, che le dichiara intoccate. Criterio: 0 letture del Portachiavi e 0 chiamate a endpoint non documentati, verificabile con un test.
- **Onboarding account.** Criterio: `claude auth status` letto in meno di 1 s all'avvio, con "Collegato come <email> · <piano>". Nessun clic se il login esiste già.
- **API key per errore.** Criterio: avviso chiaro quando `ANTHROPIC_API_KEY` sta per far pagare a consumo un utente con abbonamento (il caso di opcode #77).

## Rischi e casi limite

- **Termini.** Qualunque "Accedi con Claude" dentro Bubo, o la lettura del token dal Portachiavi, può portare a un blocco "without prior notice". Serve l'approvazione di Anthropic, oppure limitarsi al binario non modificato con il login fatto dall'utente.
- **Dati di quota scarsi.** `rate_limit_event` arriva solo durante il lavoro e non indica la finestra. A riposo Bubo potrebbe non avere numeri. Da verificare con un prototipo, insieme alla lettura di `/usage` come testo.
- **Piani che cambiano.** Il credito Agent SDK può tornare in una nuova forma, con un pool separato. L'interfaccia deve reggere più "secchi" di quota (5 h, settimana, per modello, crediti extra, eventuale credito SDK).
- **API key nascosta.** Un `ANTHROPIC_API_KEY` o `ANTHROPIC_AUTH_TOKEN` nell'ambiente sposta i costi sull'API senza avviso. Bubo deve controllare l'ambiente del figlio.
- **Più account.** È una richiesta frequente (Nimbalyst #573, Superset #6903). Con `CLAUDE_CONFIG_DIR` ogni profilo ha il suo login.
- **Login scaduto.** `Login expired · Please run /login`, con avviso 3 giorni prima. Bubo deve mostrarlo e rimandare al flusso Anthropic.
- **Limiti per famiglia.** Opus e Sonnet hanno limiti propri. Il router può cambiare famiglia, ma cambia anche la cache del prompt e quindi il costo.
- **Throttle del server** diverso dal limite del piano: non va mostrato come "quota finita".
- **Molte sessioni in parallelo.** Tutte consumano la stessa quota; un fan-out pesante può esaurire la settimana prima della finestra di 5 h.
- **macOS 26.** Aprire il Terminale con `osascript` richiede l'entitlement `com.apple.security.automation.apple-events` (Nimbalyst #57).

## Mappa

_da definire_

## Specifica "migliore di"

_da definire_

## Fonti

Primarie Anthropic:
- https://code.claude.com/docs/en/legal-and-compliance
- https://code.claude.com/docs/en/agent-sdk/overview
- https://code.claude.com/docs/en/agent-sdk/typescript
- https://code.claude.com/docs/en/agent-sdk/cost-tracking
- https://code.claude.com/docs/en/errors
- https://code.claude.com/docs/en/desktop
- https://code.claude.com/docs/en/statusline
- https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
- https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan
- https://www.anthropic.com/legal/consumer-terms
- https://x.com/ClaudeDevs/status/2054610152817619388

Concorrenti (primarie):
- https://www.conductor.build/llms-full.txt, https://www.conductor.build/docs/guides/providers, https://www.conductor.build/docs/reference/harnesses/claude-code, https://www.conductor.build/changelog
- https://github.com/nimbalyst/nimbalyst (issue 57, 573, 650, 788, 865, 889, 1470, 1490, 1497, 1509; `ClaudeUsageService.ts`)
- https://github.com/winfunc/opcode (issue 77, 133, 208, 390)
- https://github.com/imbue-ai/sculptor
- https://github.com/superset-sh/superset (issue 5733, 6903, 7096; `packages/host-service/src/trpc/router/usage/claude.ts`; `plans/20260815-token-spend-twitter-feedback.md`)
- https://www.codeagentswarm.com/en/guides/claude-code-agent-swarm
- https://github.com/Rostmen/ClaudeGUI, https://github.com/markes76/claude-code-gui
- https://github.com/codejunkie99/agentic-stack-desktop
- https://github.com/steipete/CodexBar, https://mintlify.wiki/steipete/codexbar/providers/claude
- https://zed.dev/blog/anthropic-subscription-changes

Secondarie (solo per la cronologia):
- https://venturebeat.com/ai/anthropic-cracks-down-on-unauthorized-claude-usage-by-third-party-harnesses/
- https://venturebeat.com/technology/anthropic-reinstates-openclaw-and-third-party-agent-usage-on-claude-subscriptions-with-a-catch
- https://falcao.org/posts/anthropic-claude-access-crackdown-ecosystem-fallout/
- https://www.techradar.com/pro/bad-news-claude-users-anthropic-says-youll-need-to-pay-to-use-openclaw-now
- https://www.developersdigest.tech/blog/nimbalyst-visual-workspace-codex-claude-code
