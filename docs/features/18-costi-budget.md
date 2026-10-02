# 18 — Costi e uso, budget e avvisi

Ticket: [#129](https://github.com/mgiuditta/bubo/issues/129) (ricerca), [#135](https://github.com/mgiuditta/bubo/issues/135) (decisioni), [#136](https://github.com/mgiuditta/bubo/issues/136) (Automazioni a Budget esaurito), [#140](https://github.com/mgiuditta/bubo/issues/140) (ingressi). Mappa: [#125](https://github.com/mgiuditta/bubo/issues/125).
Base: [03 — Account e uso](03-account-uso.md) (Quota), [10 — Router](10-router.md) (riga sotto la risposta, scelte automatiche), [ADR 0003](../adr/0003-login-con-la-cli-claude-dell-utente.md) (abbonamento e API key), [ADR 0006](../adr/0006-bubo-conserva-le-conversazioni.md) (copia a specchio).
Ricerca del 2026-09-30 su Agent SDK TS **0.3.285** (CLI inclusa **2.1.285**). Le citazioni restano in inglese come nell'originale. Dove una fonte non è primaria lo dico.

> **Nota sulla ricerca.** È scritta prima delle decisioni e in due punti è superata. Al 100% di soglia il router **non** "scende di un gradino o passa a un fornitore gratuito": alla soglia **evita** il fornitore o il Progetto nelle scelte automatiche se ha un'alternativa, al 100% non lo sceglie più da solo ([#135](https://github.com/mgiuditta/bubo/issues/135)). Le "tre unità" della ricerca hanno ora nome nel glossario: **Spesa**, **Valore a listino**, **Quota**. Valgono la Mappa e la Specifica qui sotto.

In sintesi: ogni turno di Bubo porta già con sé i suoi token, e quasi sempre anche una cifra in dollari. Le **Sessioni** Claude danno `total_cost_usd` e `modelUsage` per modello, ma sono **stime a listino calcolate sul Mac**; con l'abbonamento quel numero è **Valore a listino**, non **Spesa**. Le **Domande** su OpenAI, Gemini, Ollama e LM Studio danno solo token (con `stream_options.include_usage`); **OpenRouter** dà anche la cifra in ogni risposta. Apple FM e i modelli sul Mac sono gratis. Chi mostra i costi (ccusage, CodexBar, opcode, T3 Code, Superset) **mostra e basta**: nessuno impone un budget. Chi lo impone è il fornitore (OpenAI, Anthropic Console, OpenRouter, Cursor), e lì il limite **blocca** mentre gli avvisi **non fermano**. L'Agent SDK ha un tetto nativo, `maxBudgetUsd`, che chiude la query in modo pulito. Bubo tiene un solo registro locale di ogni turno, per Progetto, Sessione, modello e fornitore, con unità e origine di ogni cifra, e un **Budget** mensile con stop morbido: alla soglia avvisa e il router evita, al 100% ferma e chiede, mai senza uscita.

## Ricerca

### Da dove vengono token e cifra di ogni turno

| Motore | Token | Cifra in $ | Note |
|---|---|---|---|
| **Sessione Claude (Agent SDK)** | `result.modelUsage[modello]`: `inputTokens`, `outputTokens`, `cacheReadInputTokens`, `cacheCreationInputTokens`, `webSearchRequests`, `thinkingTokens` (già dentro `outputTokens`) [1] | `result.total_cost_usd` e `modelUsage[m].costUSD` | "client-side estimates, not authoritative billing data", calcolate "from a price table bundled at build time" [2]. `costBasis`: `list`, `managed` (tabella `modelPricing` gestita) o `unknown` (modello non riconosciuto: "costUSD is a guess at the default model's rate") [1]. |
| **Domanda Claude (Agent SDK)** | come sopra | come sopra | stessa pipeline |
| **OpenAI** (Chat Completions) | `usage.prompt_tokens`, `completion_tokens`, `prompt_tokens_details.cached_tokens`, `completion_tokens_details.reasoning_tokens` [3] | **nessuna** | In streaming lo `usage` arriva solo con `stream_options: {include_usage: true}`, in un chunk finale "before the `data: [DONE]` message" con `choices` vuoto [3]. |
| **Gemini** (endpoint OpenAI-compatibile) | `usage` con `include_usage` in streaming [4] | nessuna | La doc non dice se i token di ragionamento sono separati: da verificare con un prototipo. |
| **OpenRouter** | `usage` sempre incluso | **sì**, `usage.cost` | "Full usage details are now always included automatically in every response"; con BYOK anche `cost_details.upstream_inference_cost`; in streaming nell'ultimo messaggio SSE; a posteriori con `/generation?id=` [5]. |
| **Ollama** (`/v1/chat/completions`) | `usage`, `include_usage` supportato [6] | zero | Sul Mac. |
| **LM Studio** | `usage`; `include_usage` dalla 0.3.18, conteggi corretti in streaming dalla 0.3.19 [7] | zero | Sul Mac. |
| **Apple Foundation Models** | nessuno `usage` sulla risposta; `SystemLanguageModel.tokenCount(for:)` e `contextSize` (26.4, retrocompatibili) [8] | zero | Il conteggio è a richiesta, non automatico. |
| **Jev** (via TypeSafe o OpenRouter) | come OpenRouter se passa da lì | via OpenRouter sì | La [10](10-router.md) ha già deciso: totale mensile nelle impostazioni, nessun tetto. |

**Dettagli dell'SDK che contano per lo storico** [1][2]:

- `usage` sul `result` copre **solo il ciclo principale**; `total_cost_usd` e `modelUsage` includono subagent, compattazione e Workflow. Lo storico va costruito su `modelUsage`.
- In streaming input (le Sessioni di Bubo) ogni turno emette un `result` con il **totale progressivo** della chiamata: si legge l'ultimo, non si somma. `/clear` azzera il totale e cambia `session_id`.
- Una Sessione ripresa (`resume`) riparte dai totali salvati nel transcript (dalla CLI 2.1.277): sommare i risultati conta due volte.
- `output_tokens` sui singoli messaggi `assistant` è un segnaposto: il vero valore sta nel `result`.
- Un crash (`error_during_execution`) può portare costi azzerati; il recupero parziale passa dai messaggi precedenti.
- Le cifre applicano da sole la maggiorazione 1,1× per `inference_geo: "us"` [2].
- `modelPricing` (tariffe contrattate) vale solo da impostazioni gestite o "when supplied by a host application that manages the model provider" [1]; per Bubo, che non gestisce il fornitore, resta a listino.

**Quota e crediti extra dal binario.** `query.usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET()` e il messaggio `SDKUsageReport` di `/usage` restituiscono i totali della sessione, le righe di quota del server (`kind`, `percent`, `resets_at`, `severity`) ed `extra_usage` (crediti extra del mese, `monthly_limit`, `used_credits`, in centesimi) [1]. Passa dal binario, non dal Portachiavi (compatibile con ADR 0003), ma è dichiarato sperimentale.

**Quanto vale il numero con l'abbonamento.** La doc di Claude Code: "Claude Max and Pro subscribers have usage included in their subscription, so the session cost figure isn't relevant for billing purposes" [9]. `total_cost_usd` è quindi quanto si pagherebbe a consumo: il **Valore a listino**. Superset, T3 Code e ccusage lo mostrano apposta come "risparmio rispetto all'API"; è il dato che gli utenti chiamano "vanity" [10] (analisi interna di Superset su feedback X, secondaria per i giudizi degli utenti).

**Cronologia CLI.** Le conversazioni fatte fuori da Bubo stanno in `~/.claude/projects/<cwd codificata>/*.jsonl`, con token per messaggio. La cartella dà già il Progetto. Trappole documentate da Superset dopo il confronto "cent-exact" con ccusage [10]: deduplicare per `message.id` + `requestId` tenendo **l'ultima** occorrenza (la prima sottostima l'output del ~10%), saltare le righe `isSidechain` se si contano i subagent a parte, i token di ragionamento sono un sottoinsieme dell'output, raggruppare i giorni nel fuso dell'utente.

### Come fanno i concorrenti

| Strumento | Fonte dei dati | Viste | Budget / avvisi | Blocca? |
|---|---|---|---|---|
| **ccusage** (18.812★) | JSONL locali di 18 CLI (Claude Code, Codex, Gemini CLI, …) | giorno, mese, sessione, blocchi di 5 h, statusline [11] | `blocks --token-limit N\|max`: barre e indicatori di avviso/superamento [12] | No, solo mostra |
| **CodexBar** (22.063★) | endpoint dei fornitori, Admin API, scansione dei log locali | spesa per fornitore, Progetto, Sessione, modello, andamento giornaliero e orario [13] | mostra i budget **dei fornitori** (OpenRouter, LiteLLM, Bedrock); notifiche solo sulla quota | No |
| **opcode** | JSONL locali | costi e token per modello, Progetto, periodo [14] | nessuno trovato | No |
| **Superset** | endpoint `oauth/usage` (quota) + JSONL (storico, per Progetto) | quota per account, storico 7/30/90 giorni, tabella per modello, barre per Progetto [10][15] | "budget caps" solo nei passi successivi, non costruiti [10] | No |
| **T3 Code** | JSONL di Claude Code e Codex, anche da più Mac | costo/token, 24 h–90 d, risparmio da cache, etichetta `costSource: providerReported \| modelPriced \| unpriced` [10] (descrizione secondaria) | nessuno | No |
| **OpenRouter** | il proprio conteggio | `/api/v1/key`: `usage`, `usage_daily/weekly/monthly`, `limit`, `limit_remaining`, `limit_reset` [16] | limite per chiave (reset giornaliero, settimanale o mensile), Guardrails per membro con BYOK facoltativo [16][17] | **Sì**: 402, `limit_source` = `openrouter_key_limit` o `openrouter_credits` [16] |
| **Cursor** | il proprio conteggio | dashboard | **spend limit** mensile (individuale; team; per membro su Enterprise) e **spend alert** via email [18][19] | **Sì** il limite ("AI features stop working for that specific user"), con ritardo ("usage can briefly exceed"); **no** gli avvisi ("don't stop usage") |
| **OpenAI** (piattaforma) | il proprio conteggio | Costs API (`/organization/costs`, chiave admin) [3] | hard spend limit mensile per organizzazione e per progetto, via Admin API [3] | **Sì** (limite "hard") |
| **Anthropic Console** | il proprio conteggio | Usage and Cost API (chiave admin) | spend limit mensile per workspace, "configure alerts when spending reaches certain thresholds" [20] | **Sì** il limite, no gli avvisi |
| **Abbonamento Claude** | server Anthropic | `/usage` | crediti extra con limite mensile; al limite "Claude Code prompts you to raise or remove the limit" [9] | Sì, con proposta di alzarlo |
| **Agent SDK** | stima locale | — | `maxBudgetUsd` per `query()`: rifiuta nuovi subagent ("Budget limit reached"), ferma quelli in background, chiude con `error_max_budget_usd` [21] | **Sì**, pulito |

**Cosa ne esce.**

1. **Le app locali non impongono nulla.** ccusage, CodexBar, opcode, Superset e T3 Code mostrano; nessuno ferma un agente. L'unico "budget" di ccusage è un tetto di token per blocco di 5 ore, visivo.
2. **I fornitori bloccano, gli avvisi no.** Cursor, OpenAI, Anthropic Console e OpenRouter separano due cose: il **limite** blocca (402 o funzioni spente), l'**avviso** è una soglia che manda un'email e non ferma. OpenRouter documenta il blocco ma non un avviso prima [17].
3. **Il blocco dei fornitori è brusco e in ritardo.** Cursor ammette lo sforamento; OpenRouter risponde 402 anche sui modelli gratuiti se il saldo è negativo [16]. Nessuno propone un'alternativa al momento del blocco, tranne l'abbonamento Claude che chiede di alzare il limite.
4. **Nessuno unisce abbonamento e consumo.** Chi mostra la quota non mostra i dollari degli altri fornitori, e viceversa; solo CodexBar li mette nello stesso menu, ma per fornitore, non per Progetto o Sessione di un'app.
5. **L'onestà sull'origine del numero è rara.** Solo T3 Code etichetta "riportato dal fornitore / calcolato / senza prezzo"; l'SDK ha l'equivalente in `costBasis`. La prima domanda sotto il lancio di T3 era "is this actually correct?" [10].

### Budget: bloccano o avvisano?

- **Blocco nativo per Claude a consumo.** `maxBudgetUsd` conta solo la spesa della chiamata corrente (esclusi i totali ripristinati da `resume`; `/clear` lo riparte) [2]. Un Budget **mensile** si ottiene passando alla query il residuo del mese; al tetto l'SDK chiude in modo pulito, con `total_cost_usd` che include la risposta che ha superato il tetto (si sfora di al massimo una risposta).
- **Per OpenAI, Gemini e xAI** non c'è un blocco dal lato client: Bubo deve fermarsi da sé prima di inviare; il limite vero, se l'utente l'ha messo, è sul conto del fornitore.
- **Per OpenRouter** il limite della chiave dell'utente è leggibile con la sua stessa chiave (`/api/v1/key`) e il 402 dice quale limite è scattato [16]: Bubo può mostrarlo invece di duplicarlo.
- **Per l'abbonamento Claude** conta la Quota (03); gli unici dollari veri sono i crediti extra, con limite gestito da Anthropic.

### Prezzi aggiornati e come tenerli

| Fonte | Cosa copre | Formato | Aggiornamento | Licenza |
|---|---|---|---|---|
| **Tabella dentro l'SDK** | modelli Claude | interna, con `costBasis` | a ogni versione del binario [2] | — |
| **Anthropic, pagina prezzi** | Claude: base, cache 5 m / 1 h, lettura cache, output, batch, fast mode, 1,1× US [22] | HTML | a mano | — |
| **OpenRouter `/api/v1/models`** | 464 modelli; prezzo per token di prompt, completion, cache in lettura/scrittura, ricerca web, richiesta; soglie per contesto lungo (`overrides` con `min_prompt_tokens`) [23] | JSON, 762 KB | continuo | — |
| **models.dev** | fornitori e modelli, `cost` con `tiers` per contesto (es. Gemini 2.5 Pro oltre 200k) | JSON, 5,3 MB | continuo | MIT [24] |
| **LiteLLM `model_prices_and_context_window.json`** | molto ampio: batch, flex, priority, soglie 200k | JSON, 3,0 MB | continuo | nel repo LiteLLM [25] |

Misura B (questo Mac, 2026-09-30): le tre URL rispondono 200 senza chiave; OpenRouter `/models` risponde anche senza autenticazione, benché la doc la indichi. Per Claude Opus 5.5 models.dev e LiteLLM coincidono con la pagina Anthropic ($4 input, $20 output, $0,20 lettura cache, $5/$8 scrittura cache 5 m/1 h per MTok) [22].

**Come fanno gli altri.** ccusage fissa un'istantanea di LiteLLM e models.dev nel pacchetto, aggiornata da una GitHub Action **ogni ora**, con `--offline` per lavorare senza rete e prezzi storici applicati per data dell'evento [11][26]. Superset ha scritto i prezzi a mano e ha trovato errori (Fable 5 "priced 2x wrong" in una PR) [10].

**Conseguenza per Bubo.** Per Claude il prezzo lo mette l'SDK; per OpenRouter la cifra arriva nella risposta. Serve una tabella solo per OpenAI, Gemini, xAI e gli endpoint personalizzati: un'istantanea di models.dev nel bundle, ridotta ai fornitori usati, più un aggiornamento in background (una GET, nessun dato dell'utente). Modello assente: "senza prezzo", mai inventato.

### Fatti che toccavano i confini (risolti in [#135](https://github.com/mgiuditta/bubo/issues/135))

1. **Claude con API key è un fornitore a consumo**, e diventa il caso principale se Anthropic nega l'approvazione (ADR 0003). Ha un Budget come gli altri, con `maxBudgetUsd` come freno nativo.
2. **Con l'abbonamento `total_cost_usd` esiste lo stesso**: è Valore a listino, si mostra in secondo piano e non entra mai in un Budget.
3. **I crediti extra dell'abbonamento sono Spesa** con un limite già gestito da Anthropic: Bubo li mostra se l'SDK li distingue, senza un Budget proprio.
4. **Budget e router** si incrociano come la Quota: il router conosce il residuo ed evita il fornitore prima del 100%.
5. **"Tutti i fornitori per Progetto" richiede la Cronologia CLI**: inclusa di default, dalla copia a specchio (ADR 0006), deduplicata.

## Il meglio da battere

- **Storico:** T3 Code e Superset (per Progetto, 7–90 giorni, risparmio da cache), CodexBar (più fornitori). Nessuno per **Sessione di un'app** con tutti i fornitori insieme.
- **Onestà:** T3 Code (`costSource`). Criterio candidato: 100% delle cifre con unità e origine (riportata dal fornitore, stima a listino, prezzo da tabella, senza prezzo, gratis).
- **Budget:** Cursor (limite e avviso separati, per membro), ma blocca e basta, in ritardo. Criterio candidato: avviso prima del 100%, scelta al 100%, mai sforamento oltre una risposta sulle Sessioni a consumo.
- **Precisione:** Superset contro ccusage, "token-exact and cent-exact". Criterio candidato: per le Sessioni di Bubo, somma dello storico = somma dei `total_cost_usd` finali (scarto 0); per la Cronologia CLI, 0 turni contati due volte.

## Rischi e casi limite

- **Stima, non fattura.** Tutti i dollari dell'SDK sono stime a listino [2]: vanno etichettati come tali e mai usati per decisioni di fatturazione.
- **Modello sconosciuto all'SDK.** `costBasis: 'unknown'` fa usare il prezzo del modello predefinito [1]: la cifra va segnata come incerta.
- **Doppio conteggio.** Sommare i `result` in streaming o dopo `resume` raddoppia; sommare i messaggi paralleli con lo stesso id pure [2].
- **Crash.** `error_during_execution` con costi a zero: senza un `result` precedente Bubo perde l'output e i subagent di quel turno [2].
- **Streaming senza usage.** Senza `include_usage` OpenAI, Gemini, Ollama e LM Studio non danno token in streaming [3][6][7].
- **Prezzi che cambiano o sono a scaglioni.** Gemini cambia prezzo oltre 200k token; OpenAI e Gemini hanno priority/flex/batch; OpenRouter ha `overrides` per contesto lungo [23][24]. Una tabella piatta sbaglia.
- **Valuta.** Tutte le fonti sono in USD. Convertire in euro introduce un cambio da tenere aggiornato: Bubo mostra USD.
- **Abbonamento e API key insieme.** Una stessa Sessione può passare dall'abbonamento all'API key (ADR 0003): il registro separa i turni per modalità, altrimenti Valore a listino e Spesa si mescolano.
- **Sforamento di una risposta.** `maxBudgetUsd` ferma dopo la risposta che supera il tetto [2]; lo stesso succede nei limiti di Cursor [19]. Con più Sessioni sullo stesso Budget lo sforamento massimo è una risposta per Sessione attiva.
- **`maxBudgetUsd` su una query già aperta.** Le Sessioni di Bubo sono query lunghe in streaming input; `maxBudgetUsd` è un'opzione della query e conta la spesa della chiamata dal suo inizio [2]. Se non si può aggiornare a query aperta, il residuo condiviso si fa valere con il controllo di Bubo prima di ogni turno, e `maxBudgetUsd` resta il freno dentro il turno. Da verificare nel passo 4 dell'ordine di costruzione.
- **Endpoint sperimentale.** `usage_EXPERIMENTAL…` e `SDKUsageReport` possono cambiare in qualsiasi versione [1]: i crediti extra stanno dietro un adattatore, e se spariscono lo si dichiara.
- **Privacy dei prezzi.** Aggiornare la tabella è una richiesta di rete verso un terzo (models.dev); non porta dati, ma va dichiarata e si può spegnere.

## Mappa

Architettura comune in [INDEX.md](INDEX.md). Termini da `CONTEXT.md`: **Quota**, **Spesa**, **Valore a listino**, **Budget**, **Sessione**, **Domanda**, **Progetto**, **Cronologia CLI**, **Automazione**, **Esecuzione**, **Palette**, **Modello locale**, **HUD**.

### Tre unità (deciso)

Fonte: [#135](https://github.com/mgiuditta/bubo/issues/135).

- **Spesa**, in $: esatta da OpenRouter (`usage.cost`); stimata token × prezzi per OpenAI, Gemini, xAI ed endpoint personalizzati; stima a listino dell'SDK per Claude con API key.
- **Valore a listino**, in $ non pagati: Claude in abbonamento, in secondo piano, con la dicitura "a listino, incluso nell'abbonamento".
- **Quota**, in %: feature [03](03-account-uso.md), invariata.
- **Gratis**: Ollama, LM Studio e Apple FM, con i loro token.
- **Crediti extra dell'abbonamento**: Spesa separata solo se l'SDK li distingue (`extra_usage`); nessun Budget proprio, vale il limite di Anthropic, con il link. Se non si distinguono, la finestra Costi lo dichiara.
- Le tre unità **non si sommano mai**: nessun totale, grafico o colonna CSV le mescola.
- Ogni cifra porta anche la sua **origine**: riportata dal fornitore, stima a listino (con `costBasis`), prezzo da tabella (con la data della tabella), senza prezzo, gratis.

### Fonti dello storico (deciso)

- **Ogni turno** di Sessione e di Domanda, per qualunque fornitore.
- **Cronologia CLI di Claude**, inclusa di default con origine "riga di comando", filtrabile. Si legge dalla copia a specchio (ADR 0006), quindi anche oltre i 30 giorni della CLI. Deduplicata per `message.id` + `requestId`, ultima occorrenza.
  - Costruita in [#163](https://github.com/mgiuditta/bubo/issues/163): token + stima a listino con la tabella nostra `Bubo/Resources/PrezziAnthropic.json` (con la scrittura in cache a 1 h), rifatta da `scripts/update-anthropic-prices.sh`. Unità propria "Riga di comando, a listino", mai Spesa né Valore a listino, fuori dal `CostLedger` e quindi dai Budget. Si legge la copia, poi `~/.claude/projects`; restano fuori solo le righe con entrypoint `sdk-ts`, cioè le Sessioni e le Domande di Bubo, già nel registro. Filtro "Fonte" (Tutte, Bubo, Riga di comando) nella finestra Costi.
- **Altri strumenti a riga di comando** (Codex, Gemini CLI, …) fuori, e lo si dichiara nella finestra Costi.
- **Domande** nel gruppo "Domande": contano per fornitore e nel totale, non per Progetto. Una Domanda diventata Sessione porta le sue cifre nel Progetto da quel momento in avanti; i turni di prima restano nelle Domande.
- **Jev**: resta com'è nella [10](10-router.md), totale mensile nelle impostazioni, nessun Budget.
- Il prezzo registrato è quello **del momento del turno**, mai ricalcolato.

### Dove si vede (deciso)

- **Intestazione della Sessione**: il suo totale, a 0 clic, nell'unità giusta (Spesa, o Valore a listino in secondo piano).
- **Riga sotto ogni risposta** ([10](10-router.md)): resta com'è (Quota in % con l'abbonamento, $ sulla chiave dell'utente, "gratis" sul Mac). Claude con API key vi mostra la Spesa del turno. Qui compare anche l'avviso di soglia del Budget.
- **Finestra Costi**, fuori dall'HUD, come la Galassia: per Progetto, Sessione, modello, fornitore e periodo; tabella più grafico nel tempo; filtro per origine (Bubo o riga di comando); export CSV. Si apre dal menu Finestra, dalla Palette ([#140](https://github.com/mgiuditta/bubo/issues/140)) e dall'anello della Quota. **Nessun tasto**, nessuna scorciatoia globale.
- **Impostazioni**: solo Budget e tabella prezzi. **Nessun pannello nell'HUD.**

### Budget (deciso)

- **Mensili**, mese solare nel fuso del Mac, **tutti spenti di default**.
- **Per fornitore a consumo** (Claude con API key compreso: OpenAI, Gemini, xAI, OpenRouter, endpoint personalizzati).
- **Per Progetto**: somma della Spesa dei suoi fornitori a consumo.
- **Totale**, facoltativo.
- **Più Budget sullo stesso turno**: vale il più stretto.
- **Niente Budget** su abbonamento (c'è la Quota), modelli sul Mac, Apple FM, Jev.
- Contano solo i turni passati da Bubo: la riga di comando non si può fermare. La Cronologia CLI resta nello storico, fuori dai Budget.
  - Costruito in [#164](https://github.com/mgiuditta/bubo/issues/164): `Costs/BudgetSettings` (Impostazioni › Budget, in `UserDefaults`), `Costs/BudgetGuard` (residui ricalcolati a ogni lettura dal `CostLedger`, quindi subito dopo una modifica e a mezzanotte del primo), `Costs/BudgetAlerts` (notifica una volta per Budget, livello e limite al mese, chiamata dal registro a ogni turno). Il fornitore si riconosce dal nome nel registro ("Anthropic" per Claude, il nome dell'endpoint per gli altri; xAI è un endpoint personalizzato). Claude con `costBasis: unknown` conta, segnato incerto. Il router evita alla soglia: una preferenza va al predefinito, Claude con API key al Modello locale; senza alternativa resta, con l'avviso. Il 402 di OpenRouter (`limit_source`: chiave, crediti, richieste in corso) si mostra come limite del fornitore. Il 100% è [#165](https://github.com/mgiuditta/bubo/issues/165).

### Soglia e 100%: stop morbido (deciso)

- **Soglia** (default 80%, modificabile): avviso nella riga sotto la risposta e una notifica. Il router ([10](10-router.md)) evita quel fornitore o quel Progetto nelle scelte automatiche (default, preferenze "Usa sempre per «Tipo»") se ha un'alternativa, e il motivo lo dice. Senza alternativa, solo l'avviso.
- **100%**: nessuna scelta automatica su quel fornitore. Le scelte esplicite dell'utente ("Rifai con…", chip nel prompt) chiedono conferma. Mai blocchi silenziosi né senza uscita.
- **Claude con API key**: ogni Sessione riceve come `maxBudgetUsd` il **residuo corrente condiviso**, ricalcolato a ogni turno di ogni Sessione, senza suddivisione anticipata tra le Sessioni. Al 100% la Sessione si ferma da sola (`error_max_budget_usd`) e chiede: **[Aumenta] [Continua solo questa volta] [Passa all'abbonamento]** o **[Passa al locale]** dove ha senso. Il passaggio all'abbonamento segue ADR 0003.
- **OpenAI, Gemini, xAI, OpenRouter, endpoint personalizzati**: Bubo controlla il residuo prima di inviare; al 100% stesse scelte.
- **Sforamento massimo**: un turno per Sessione attiva, dichiarato nella schermata dei Budget.
- **Blocco duro**: lo si imposta dal fornitore; la schermata dei Budget porta il link.

### Automazioni (deciso)

Fonte: [#136](https://github.com/mgiuditta/bubo/issues/136), regola ereditata dalla 19.

- **Budget già al 100%** all'orario: l'Esecuzione non parte, esito **Saltata** ("Saltata: budget esaurito"), notifica con **[Avvia ora]**, che vale da conferma. Nessun avvio automatico.
- **Budget esaurito durante**: l'Esecuzione si ferma come ogni Sessione e aspetta l'utente.

### Prezzi (deciso)

- Istantanea di models.dev nel bundle, ridotta ai fornitori usati.
- Aggiornamento **acceso di default**, al massimo una volta al giorno, disattivabile. È l'unica chiamata di rete della feature.
- Offline o aggiornamento spento: vale l'istantanea. Prezzi vecchi di oltre 30 giorni: lo si dice ("prezzi del 12 agosto").
- Modello assente dalla tabella: "senza prezzo", nessuna cifra inventata; il turno conta i token.
- Claude dall'SDK, OpenRouter dalla risposta: nessuna tabella per loro. Nessun prezzo scritto nel codice.
- Costruito in [#143](https://github.com/mgiuditta/bubo/issues/143): istantanea in `Bubo/Resources/Prezzi.json`, rifatta con `scripts/update-prices.sh` (stesso taglio di `PriceTable` all'aggiornamento: `openai`, `google`, `xai`, solo il campo `cost`). L'età è la data dello scaricamento, con `etag` per la GET condizionale. xAI si riconosce dall'indirizzo `api.x.ai` di un endpoint personalizzato; gli altri endpoint personalizzati restano "senza prezzo". Prezzi a scaglioni per contesto (`tiers`) applicati a tutto il turno. Interruttore in Impostazioni › Modelli. La tabella Anthropic della Cronologia CLI ([#163](https://github.com/mgiuditta/bubo/issues/163), con la scrittura in cache a 1 h che models.dev non ha) va in un file a parte, non in questa istantanea: un aggiornamento da models.dev la perderebbe.

### Moduli

- `Costs/UsageReader`: dal `result` dell'SDK (ultimo totale della query, `modelUsage`, `costBasis`, `error_max_budget_usd`), dal chunk finale OpenAI-compatibile (`include_usage`, `usage.cost` di OpenRouter), da Apple FM (`tokenCount(for:)`). Produce una voce con token, cifra, unità e origine.
- `Costs/CostLedger`: registro locale, una riga per turno: Progetto o "Domande", Sessione o Domanda, modalità (abbonamento o API key), fornitore, modello, token (input, cache in lettura e scrittura, output, ragionamento), cifra, unità, origine, data della tabella prezzi. Idempotente: un turno riletto (streaming, `resume`, `/clear`) non crea una seconda riga.
- `Costs/CLIHistoryReader`: legge la Cronologia CLI dalla copia a specchio tramite `History/ConversationStore` (14, ADR 0006), deduplica per `message.id` + `requestId`, giorni nel fuso del Mac, origine "riga di comando".
- `Costs/PriceTable`: istantanea models.dev, aggiornamento giornaliero spegnibile, età dei prezzi, stato "senza prezzo".
- `Costs/BudgetGuard`: Budget, residui per fornitore, Progetto e totale, il più stretto; stato soglia/100%; valore di `maxBudgetUsd` per Sessione; controllo prima dell'invio per gli altri fornitori; decisione Saltata per le Esecuzioni.
- `Costs/CostsWindow`: finestra Costi (AppKit + SwiftUI), tabella, grafico nel tempo, filtri, export CSV.
- `Costs/BudgetSettings`: schermata dei Budget e della tabella prezzi nelle Impostazioni, con sforamento massimo dichiarato e link ai limiti dei fornitori.
- `HUD/SessionCostTotal`: totale nell'intestazione della Sessione.
- Riuso: `Agent/AgentBridge` (`result`, `maxBudgetUsd`, `error_max_budget_usd` nel protocollo stdio), `Router/ModelRouter` (Budget come vincolo accanto alla Quota), `Router/Providers` (`include_usage` sempre acceso), `HUD/RouterLine` (avviso di soglia), `Account/UsageMeter` (Quota, crediti extra dietro l'adattatore sperimentale), `System/` (notifiche), Palette ([#140](https://github.com/mgiuditta/bubo/issues/140)), Automazioni (19).

### Flusso

1. Turno → `result` dell'SDK o risposta OpenAI-compatibile o Apple FM → `UsageReader` → `CostLedger` (entro 1 s) → totale della Sessione e riga sotto la risposta aggiornati.
2. `BudgetGuard` ricalcola i residui → soglia superata: avviso nella riga + notifica, `ModelRouter` evita il fornitore o il Progetto → 100%: nessuna scelta automatica, `maxBudgetUsd` al residuo; la Sessione si ferma e mostra le tre scelte.
3. Richiesta successiva → `ModelRouter` legge lo stato di `BudgetGuard` → scelta automatica o conferma sulla scelta esplicita → invio con il residuo aggiornato.
4. Orario di un'Automazione → `BudgetGuard` → Budget al 100%: Esecuzione Saltata + notifica [Avvia ora]; altrimenti parte.
5. Menu Finestra, Palette o anello della Quota → finestra Costi dal `CostLedger` (turni di Bubo) + `CLIHistoryReader` (riga di comando), filtri, CSV.

### Casi limite

- **Streaming e `resume`**: si registra l'ultimo totale della query, mai la somma dei `result`; `/clear` apre una nuova query con nuovo `session_id`.
- **Crash** (`error_during_execution` con cifre a zero): si tiene l'ultimo `result` valido del turno; se manca, token dai messaggi precedenti e cifra segnata come incompleta.
- **`costBasis: 'unknown'`**: cifra mostrata come incerta, mai come esatta.
- **Sessione che passa dall'abbonamento all'API key** (ADR 0003): i turni di prima restano Valore a listino, quelli dopo sono Spesa ed entrano nei Budget.
- **Più Sessioni sullo stesso Budget**: residuo condiviso; sforamento massimo un turno per Sessione attiva.
- **Budget modificato o aumentato a metà mese**: il residuo si ricalcola subito; le Sessioni ferme al 100% ripartono solo su scelta dell'utente.
- **Cambio di mese**: i residui ripartono a mezzanotte del primo giorno nel fuso del Mac; un turno a cavallo conta nel mese in cui finisce.
- **Tabella prezzi vecchia o offline**: istantanea del bundle, età indicata oltre 30 giorni.
- **Modello senza prezzo** su un fornitore con Budget: il turno non ha cifra e il Budget non può contarlo; lo si dice nella riga e nella schermata dei Budget.
- **OpenRouter con limite di chiave proprio** (402, `limit_source`): si mostra il limite del fornitore, non lo si duplica.
- **Crediti extra non distinguibili** o API sperimentale sparita: la finestra Costi lo dichiara, nessuna cifra inventata.
- **Cronologia CLI con copia spenta** (interruttore di ADR 0006): lo storico mostra solo ciò che la CLI tiene ancora, e lo dice.
- **Domanda diventata Sessione**: le cifre passano al Progetto solo dai turni successivi.

### Test

- Transcript registrati con streaming, `resume`, `/clear`, subagent e crash: somma dello storico = somma dei `total_cost_usd` finali, scarto 0.
- JSONL della Cronologia CLI con righe duplicate e parallele: 0 turni contati due volte; stesso totale di ccusage sullo stesso giorno.
- Test automatico sulle unità: nessuna somma, grafico o colonna CSV che mescoli Spesa, Valore a listino e Quota.
- Budget Claude con API key su due Sessioni in parallelo: sforamento ≤ una risposta per Sessione attiva; avviso di soglia entro 1 s dal turno che la supera.
- Al 100%: nessuna scelta automatica sul fornitore (set di richieste con preferenze "Usa sempre per"), override con conferma in 1 clic, nessuno stato senza uscita.
- Automazione con Budget al 100%: Esecuzione Saltata, notifica con [Avvia ora].
- Tabella prezzi senza rete e con istantanea di oltre 30 giorni: cifre presenti, età indicata.
- Monitor di rete durante una Sessione e l'apertura della finestra Costi: unica chiamata della feature lo scaricamento dei prezzi, 0 byte del Progetto.
- Finestra Costi con 12 mesi di dati sintetici: apertura < 500 ms.
- Accessibilità: audit AppKit e SwiftUI della finestra Costi e della schermata dei Budget; il grafico ha la tabella come equivalente.

### Ordine di costruzione

1. **Registro dei turni e totale della Sessione**: `UsageReader` per l'SDK, `CostLedger`, `HUD/SessionCostTotal`, Spesa di Claude con API key nella riga. Dipende da: ponte agente ([#66](https://github.com/mgiuditta/bubo/issues/66)), 03 Account e uso ([#67](https://github.com/mgiuditta/bubo/issues/67), [#68](https://github.com/mgiuditta/bubo/issues/68), per la modalità abbonamento o API key), 01 Sessioni.
2. **Domande e prezzi**: `include_usage` nel client OpenAI-compatibile, `usage.cost` di OpenRouter, Apple FM gratis, `PriceTable` con istantanea models.dev e aggiornamento. Dipende da: passo 1, 10 Router (`Router/Providers`, ticket in [INDEX.md](INDEX.md)).
3. **Finestra Costi e Cronologia CLI**: `CostsWindow`, `CLIHistoryReader` dalla copia a specchio, filtri, CSV, ingressi dal menu Finestra e dall'anello della Quota. Dipende da: passi 1–2, copia a specchio ([ADR 0006](../adr/0006-bubo-conserva-le-conversazioni.md)); la voce nella Palette quando esiste ([#140](https://github.com/mgiuditta/bubo/issues/140)).
4. **Budget e stop morbido**: `BudgetGuard`, `BudgetSettings`, avviso e notifica, `ModelRouter` che evita, `maxBudgetUsd` al residuo condiviso, tre scelte al 100%. Apre con la verifica di `maxBudgetUsd` su una query già aperta. Dipende da: passi 1–2, 10 Router (`ModelRouter`), 06 (notifiche).
5. **Automazioni a Budget esaurito**: Esecuzione Saltata + [Avvia ora]. Dipende da: passo 4, 19 Automazioni.

## Specifica "migliore di"

Miglior concorrente per lo storico: **T3 Code** e **Superset** (per Progetto, 7–90 giorni, origine della cifra solo in T3) e **CodexBar** (più fornitori); nessuno per Sessione con tutti i fornitori, e nessuno impone un budget. Per il budget: **Cursor** (limite e avviso separati), che però blocca e basta, con sforamento non dichiarato.
Bubo li supera così:

1. **Ogni turno registrato**: token e cifra **entro 1 s** dal turno, per il **100%** dei fornitori, **sempre con unità e origine**.
2. **Storico a portata**: per Progetto, Sessione, modello, fornitore e periodo in **≤ 2 clic** dall'HUD; finestra Costi aperta in **< 500 ms** con 12 mesi di dati; totale della Sessione a **0 clic**.
3. **Precisione**: **0 turni** contati due volte dalla Cronologia CLI (test con JSONL duplicati); scarto **0** tra storico e `total_cost_usd` finali delle Sessioni di Bubo.
4. **Unità separate**: **0** somme tra Quota, Spesa e Valore a listino (test automatico).
5. **Budget Claude con API key**: sforamento **≤ una risposta per Sessione attiva**; avviso alla soglia **entro 1 s** dal turno che la supera.
6. **Al 100%**: **0 blocchi senza uscita**, **0 scelte automatiche** su quel fornitore, override in **1 clic** con conferma.
7. **Prezzi**: tabella funzionante **offline**; età indicata oltre **30 giorni**; **0 cifre** inventate per modelli senza prezzo.
8. **Privacy**: **0 dati** del Progetto inviati per i costi; unica chiamata di rete lo scaricamento dei prezzi, al massimo una volta al giorno.
9. **Automazioni**: **0 Esecuzioni** avviate con Budget al 100% senza [Avvia ora].
10. **Ingressi**: finestra Costi raggiungibile dal menu Finestra e dalla Palette; **0 scorciatoie globali** nuove.

## Fonti

1. `@anthropic-ai/claude-agent-sdk` 0.3.285, `sdk.d.ts` (`ModelUsage` con `costBasis`, `canonicalModel`, `thinkingTokens`; `SDKResultError` con `error_max_budget_usd`; `Options.maxBudgetUsd`; `SDKUsageReport`; `SDKControlGetUsageResponse`; `usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET`; `Settings.modelPricing`) — https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk
2. Claude Code, "Track cost and usage" (Agent SDK) — https://code.claude.com/docs/en/agent-sdk/cost-tracking
3. OpenAI, specifica OpenAPI (`stream_options.include_usage`, `CompletionUsage`, `/organization/costs`, `/organization/spend_limit`, `/organization/projects/{id}/spend_limit`) — https://github.com/openai/openai-openapi/blob/master/openapi.yaml (la doc su platform.openai.com risponde 403 al fetch diretto)
4. Google, "OpenAI compatibility" (Gemini API) — https://ai.google.dev/gemini-api/docs/openai
5. OpenRouter, "Usage Accounting" — https://openrouter.ai/docs/guides/guides/usage-accounting
6. Ollama, "OpenAI compatibility" — https://docs.ollama.com/api/openai-compatibility
7. LM Studio, "API changelog" (0.3.17, 0.3.18, 0.3.19) — https://lmstudio.ai/docs/developer/api-changelog
8. Apple, `SystemLanguageModel` (`contextSize`, `tokenCount(for:)`) — https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
9. Claude Code, "Manage costs effectively" (`/usage`, abbonamento, crediti extra, `modelPricing`, limiti dell'organizzazione) — https://code.claude.com/docs/en/costs
10. Superset, "Token-spend tracking — Twitter feedback analysis" e seguiti (analisi interna; giudizi degli utenti e descrizione di T3 Code sono secondari) — https://github.com/superset-sh/superset/blob/main/plans/20260815-token-spend-twitter-feedback.md
11. ccusage, README e "Cost Modes" — https://github.com/ryoppippi/ccusage , https://github.com/ryoppippi/ccusage/blob/main/docs/guide/cost-modes.md
12. ccusage, "Blocks reports" (`--token-limit`) — https://github.com/ryoppippi/ccusage/blob/main/docs/guide/blocks-reports.md
13. CodexBar, README e `docs/openrouter.md` — https://github.com/steipete/CodexBar
14. opcode, README — https://github.com/winfunc/opcode
15. Superset, issue #5733 "Token Usage screen" — https://github.com/superset-sh/superset/issues/5733
16. OpenRouter, "API limits" (`/api/v1/key`, 402, `limit_source`) — https://openrouter.ai/docs/api-reference/limits
17. OpenRouter, "Guardrails" — https://openrouter.ai/docs/guides/features/guardrails
18. Cursor, "Spend alerts" — https://cursor.com/docs/account/billing/spend-alerts
19. Cursor, "Spend limits" — https://cursor.com/help/account-and-billing/spend-limits
20. Anthropic, "Workspaces" (spend limit mensile e avvisi a soglia; workspace Claude Code) — https://platform.claude.com/docs/en/manage-claude/workspaces
21. Claude Code, "Subagents in the SDK" → "Cap subagent depth, concurrency, and spend" — https://code.claude.com/docs/en/agent-sdk/subagents
22. Anthropic, "Pricing" — https://platform.claude.com/docs/en/about-claude/pricing
23. OpenRouter, "List models" (oggetto `pricing`) — https://openrouter.ai/docs/api-reference/models/get-models ; dati: https://openrouter.ai/api/v1/models
24. models.dev (MIT) — https://github.com/sst/models.dev ; dati: https://models.dev/api.json
25. LiteLLM, `model_prices_and_context_window.json` — https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json
26. ccusage, workflow "update pricing" (cron orario) — https://github.com/ryoppippi/ccusage/blob/main/.github/workflows/update-pricing.yaml

Misura B: `curl` dal Mac il 2026-09-30 sulle tre fonti di prezzi (codice HTTP, dimensione, numero di modelli, voce di Claude Opus 5.5 confrontata con la pagina Anthropic).
