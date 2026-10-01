# 10 — Router multi-modello

Ticket: [#44](https://github.com/mgiuditta/bubo/issues/44). Mappa: [#42](https://github.com/mgiuditta/bubo/issues/42). Decisioni: [Prototipo: scelta del router spiegata e override](https://github.com/mgiuditta/bubo/issues/50), [Router: fornitori, criteri di scelta, override](https://github.com/mgiuditta/bubo/issues/52), [Jev: quali decisioni di Bubo gli affidiamo](https://github.com/mgiuditta/bubo/issues/59). Ricerca allegata: [10 — Jev (TypeSafe) come motore di decisione](10-router-jev.md).
Ricerca del 2026-09-29 su Agent SDK TS **0.3.284** e CLI `claude` di sistema **2.1.285**.

In sintesi: nessun concorrente spiega davvero perché ha scelto un modello. Cursor lo nasconde per scelta; OpenRouter lo dice solo in un header opzionale; Not Diamond restituisce un nome e basta. Per le **Sessioni** l'Agent SDK dà già tutto quello che serve per scegliere modello e sforzo all'avvio **e a ogni turno** (`setModel`, `applyFlagSettings({effortLevel})`), con l'elenco dei modelli e degli sforzi ammessi letto dal binario (`supportedModels()`). Per le **Domande** gli altri fornitori si raggiungono tutti con due protocolli: OpenAI Chat Completions (OpenAI, Gemini, xAI, Ollama, LM Studio, MLX, OpenRouter) e Anthropic Messages (xAI, Ollama, LM Studio). Il router di Bubo può quindi girare in locale, spiegare la scelta e restare sotto il controllo dell'utente: è il punto dove si batte tutti.

## Ricerca

> Dove la ricerca e le decisioni divergono valgono le decisioni (sezioni Mappa e Specifica): **un solo client OpenAI-compatibile**, niente client Anthropic Messages (Claude passa dall'SDK); xAI solo come endpoint personalizzato finché i termini non sono verificati; il criterio "0 byte a router di terzi" ammette Jev con chiave e consenso, solo per il testo della richiesta ([#59](https://github.com/mgiuditta/bubo/issues/59)). I criteri del "meglio da battere" qui sotto sono candidati: quelli validi sono nella Specifica.

### Come scelgono e spiegano il modello i router esistenti

| Router | Come sceglie | Spiega la scelta? | Override | Costo del router |
|---|---|---|---|---|
| **Cursor Auto (Cursor Router)** | Un classificatore su ogni richiesta dell'agente, per tipo di compito e complessità; sceglie "il modello più economico che dà una qualità comparabile" [1]. Tre modalità: Cost, Balance, Intelligence [1][2]. Serve Grok 4.6 abilitato come modello di base economico [1]. | **No, di default.** L'admin può mostrare il modello scelto all'inizio della risposta; il default è nasconderlo "così i risultati si giudicano per merito, non per il nome del modello" [1]. | Scelta manuale del modello nel selettore; nell'SDK `auto-smart` con `optimize_for` = cost / balanced / intelligence [1]. | Prezzo di listino del modello scelto; per i modelli di terzi +Cursor Token Rate $0,25/M token su Teams/Enterprise [2]. |
| **Claude Code (`opusplan`, sforzo)** | Nessun classificatore: regole fisse. `opusplan` = Opus in plan mode, Sonnet in esecuzione [3]. `default` = runtime default dell'account (Opus 5.5 per quasi tutti i piani); `best` = Fable dove c'è, altrimenti Opus [3]. | Implicita: l'utente vede il modello nel selettore e nella statusline. | `/model`, `--model`, `/effort`, `--effort`, `CLAUDE_CODE_EFFORT_LEVEL`, `effortLevel` e `modelSettings` nei settings [3]. | Nessuno. |
| **OpenRouter Auto** (`openrouter/auto`, `openrouter/auto-beta`) | Classifica il prompt in ~30 tipi di compito (es. `code:debugging`, `agent:multi_step_planning`), poi ordina i candidati per **quota di spesa della community negli ultimi 7 giorni**, dentro il tier di costo (`low`…`max`, default ≈ `low`) [4]. | Solo il campo `model` nella risposta; il tipo di compito con l'header opt-in `X-OpenRouter-Metadata: enabled` [4]. | `allowed_models` (anche con jolly, `anthropic/*`) ed `excluded_models` [4]. | Nessun sovrapprezzo: si paga il modello scelto [4]. |
| **Not Diamond** | Router pre-addestrato o **custom** addestrato sui dati di valutazione del cliente; ottimizza qualità (default), costo o latenza; `cost_quality_tradeoff` da 0 a 10 [5]. | Restituisce solo "session ID e modello consigliato" [6]. | L'elenco dei candidati lo passa il client a ogni chiamata [6]. | Non pubblicato nelle pagine lette. **I messaggi vanno a Not Diamond**; la chiamata al modello la fa poi il client [6]. |
| **Martian** | Oggi la doc descrive un **gateway** OpenAI-compatibile con 200+ modelli scelti a mano (`openai/gpt-4.1-nano`), non un router automatico [7]. | Dashboard d'uso [7]. | Il modello lo scrive il client [7]. | — |
| **Raycast AI** (riferimento macOS) | Nessun router: l'utente sceglie nel selettore. BYOK per OpenAI, Anthropic, Google, OpenRouter; provider custom OpenAI-compatibili; Ollama rilevato in automatico. Richiede piano a pagamento (v2) [8]. | — | Selettore. | Piano Raycast. |

**Cosa ne esce.**

1. **La spiegazione manca ovunque.** Nessuno dice "ho scelto X perché la richiesta è di tipo Y e costa Z". OpenRouter è il più vicino (tipo di compito in un header). Cursor nasconde il modello apposta.
2. **L'override è sempre il selettore del modello**; nessuno offre "rifai con un modello più forte" sulla singola risposta.
3. **I router cloud vedono il prompt** (Not Diamond, OpenRouter, Cursor). Per Bubo, dove il principio è "nessun dato del Progetto al cloud senza consenso", la classificazione va fatta in locale.
4. **Regole semplici funzionano**: `opusplan` è una regola a due righe e copre il caso più comune (pianificare forte, eseguire veloce).

### Cosa permette l'Agent SDK sulla scelta di modello e sforzo

Da `sdk.d.ts` 0.3.284 [9] e dalla doc di Claude Code [3].

| Cosa | Per Sessione (avvio) | Per turno (a sessione aperta) |
|---|---|---|
| Modello | `Options.model` (alias o id) | `query.setModel(model?)` — "per le risposte successive", solo in streaming input |
| Sforzo | `Options.effort: 'low'…'max'` | `query.applyFlagSettings({ effortLevel })`; `null` torna al default del modello. `'max'` è solo di sessione e scende a `high` sui modelli senza `max` |
| Ragionamento | `Options.thinking: {type:'adaptive'}` o `{type:'enabled', budgetTokens}` | `setMaxThinkingTokens` (deprecato) |
| Ripiego | `Options.fallbackModel` (lista separata da virgole; il primario si riprova a ogni turno utente) | — |
| Subagent | `AgentDefinition.model` (alias, id o `inherit`) e `AgentDefinition.effort` | — |
| Catalogo | `query.supportedModels()` → `ModelInfo`: `value`, `resolvedModel`, `displayName`, `supportsEffort`, `supportedEffortLevels`, `supportsAdaptiveThinking` | idem |
| Sforzo effettivo | Hook: `effort.level` "dopo l'eventuale declassamento silenzioso per il modello scelto"; anche `CLAUDE_EFFORT` nell'ambiente di Bash | idem |
| Limiti dell'org | `availableModels`, `deniedModels`, `maxEffortLevel`, `modelSettings.<modello>.maxEffortLevel` (managed settings): Bubo deve rispettarli, non aggirarli | idem |
| Prewarm | `prewarm()` + `claim({model, settings:{effortLevel}})`: modello e sforzo si decidono al momento del claim, non al prewarm | — |

**Default di sforzo** [3]: `high` su tutti i modelli con sforzo, tranne Opus 5.5 e Sonnet 5.5 (`medium`) e Opus 4.7 (`xhigh`). Precedenza: scelta esplicita (`CLAUDE_CODE_EFFORT_LEVEL`, `--effort`, `/effort`) > settings dell'utente > default del modello.

**Misura A** (questo Mac, `supportedModels()` con `settingSources: []`, risposta in 817 ms): 12 righe. `default` e `opus` → `claude-opus-5-5`; `sonnet` → `claude-sonnet-5-5`; `haiku` → `claude-haiku-4-5-20251001` **senza sforzo**; Fable 5.1, Fable 5, Sonnet 5, Opus 5, Opus 4.8, Opus 4.7 con `low…max`; Opus 4.6 e Sonnet 4.6 senza `xhigh`. `opusplan` non compare nel catalogo dell'account, pur essendo un alias valido [3].

**Conseguenza per Bubo.** Il router della Sessione non ha bisogno di un secondo processo: decide modello e sforzo prima del primo messaggio (o del `claim`) e può cambiarli tra un turno e l'altro. Il catalogo si legge sempre da `supportedModels()`, mai da una lista scritta nel codice: così segue il piano dell'utente e le restrizioni dell'org.

### Come si raggiungono gli altri fornitori (solo Domande)

| Fornitore | Endpoint | Protocollo | Note |
|---|---|---|---|
| **OpenAI** | `api.openai.com/v1` | OpenAI (Chat Completions, Responses) | Chiave dell'utente. Vedi termini sotto [10][11]. |
| **Google Gemini** | `generativelanguage.googleapis.com/v1beta/openai/` | OpenAI-compatibile | `reasoning_effort` mappato sul thinking di Gemini (per 2.5: `medium` = 8.192 token, `high` = 24.576) [12]. |
| **xAI** | `api.x.ai/v1` | OpenAI e Anthropic compatibili; API primaria Responses | Risposte salvate 30 giorni e poi cancellate; sforzo configurabile sui modelli di ragionamento [13][14]. |
| **Ollama** | `localhost:11434/v1` | OpenAI (`chat/completions`, `responses`, `embeddings`, `models`) **e** Anthropic `/v1/messages` | Il server locale ignora la chiave. Anthropic: niente `tool_choice`, conteggio token, prompt caching, PDF; token contati per approssimazione [15][16]. |
| **LM Studio** | `localhost:1234` | OpenAI e Anthropic compatibili, REST proprio, SDK TS/Python | Headless con `llmster` / `lms server start` [17]. |
| **MLX (`mlx_lm.server`)** | `localhost:8080` | OpenAI-compatibile (`chat/completions`, `models`) | "Non raccomandato in produzione: implementa solo controlli di sicurezza di base" [18]. |
| **Apple Foundation Models** | in processo (framework, macOS 26) | API Swift nativa | Modello on-device di Apple Intelligence; **4.096 token** di contesto per sessione; tool calling; 3–5 tool al massimo consigliati [19]. |
| **OpenRouter** | `openrouter.ai/api/v1` | OpenAI-compatibile | Nessun ricarico sui prezzi; 5,5% (min $0,80) sull'acquisto crediti con Stripe; log dei prompt spento di default [20]. BYOK: 5% del costo normale, gratis fino a $25.000/mese di listino sul pay-as-you-go [21]. OAuth PKCE con callback su `localhost` a porta libera: l'utente autorizza senza incollare chiavi [22]. |

**Conseguenza per Bubo.** Due client bastano: uno **OpenAI Chat Completions** e uno **Anthropic Messages**, più Foundation Models in Swift. La Tinta viene dal fornitore (endpoint), non dal modello.

### Termini d'uso delle chiavi in un'app di terzi

- **Anthropic.** L'Agent SDK è regolato dai Commercial Terms. "Salvo approvazione, Anthropic non consente a sviluppatori terzi di offrire il login claude.ai o i suoi rate limit nei loro prodotti, compresi gli agenti costruiti con l'Agent SDK" [23]. Branding: ammesso "Claude Agent" o "{Nome} Powered by Claude"; vietato "Claude Code" [23]. Già deciso in ADR 0003 (binario `claude` intatto, login fatto dall'utente, API key solo con consenso).
- **OpenAI.** Il Services Agreement vieta di "comprare, vendere o trasferire chiavi API da, a o con terzi" e di condividere credenziali tra utenti [10]. La guida sulla sicurezza delle chiavi dice di non metterle mai "in ambienti client come browser o app mobili" e di passare da un backend [11]. Per Bubo la chiave è **dell'utente, sul suo Mac, usata da lui**: non c'è trasferimento a terzi e la chiave non è distribuita dentro l'app. Il rischio della guida (chiave dello sviluppatore esposta a tutti) non si applica; resta l'obbligo di tenerla nel Portachiavi e mai nei log.
- **Google Gemini.** Maggiore età (18+). "Si possono usare solo i Servizi a pagamento quando si rendono disponibili API Client a utenti in SEE, Svizzera o Regno Unito"; sui servizi gratuiti Google usa contenuti e risposte per migliorare i prodotti, con revisori umani [24]. Per un utente italiano: chiave con fatturazione attiva, altrimenti avviso.
- **xAI.** Risposte conservate 30 giorni lato server [14]. Termini sulle chiavi non letti in fonte primaria (da verificare prima della spec).
- **Cursor BYOK** (confronto): la chiave "non è salvata sui nostri server" ma passa dal loro backend a ogni richiesta; con chiavi proprie la Zero Data Retention di Cursor non vale; Tab resta sui loro modelli [25]. Bubo può fare meglio: chiamata diretta dal Mac al fornitore, nessun intermediario.

## Il meglio da battere

Il riferimento è **Cursor Auto** per la qualità della scelta e **OpenRouter Auto** per la trasparenza, entrambi cloud e opachi. Criteri candidati:

1. **Scelta spiegata sempre:** ogni risposta mostra modello, sforzo e il motivo in una riga (es. "Domanda breve, nessun file → Haiku, sforzo basso"). 100% delle risposte, contro 0% di default in Cursor.
2. **Classificazione locale:** il router decide senza mandare il prompt a nessun servizio (regole + eventuale Foundation Models on-device). 0 byte a router di terzi.
3. **Override in 1 clic sulla singola risposta:** "rifai più forte" / "rifai con…" alza modello o sforzo solo per quel turno (`setModel` + `applyFlagSettings`), senza toccare il default.
4. **Latenza del router:** decisione in < 50 ms con le regole; < 300 ms se si usa il modello on-device (da misurare). Deve arrivare prima del primo Morph.
5. **Catalogo sempre vero:** modelli e sforzi solo da `supportedModels()`; 0 scelte rifiutate per modello non disponibile o sforzo non supportato.
6. **Chiavi solo nel Portachiavi, chiamate dirette:** nessun proxy di Bubo; OpenRouter via OAuth PKCE senza incollare chiavi.

## Rischi e casi limite

- **Declassamento silenzioso dello sforzo.** Un livello non supportato scende senza errore (es. `max` → `high`; Haiku 4.5 senza sforzo). Bubo deve mostrare lo sforzo **effettivo** (hook `effort.level`), non quello chiesto [9].
- **Limiti dell'organizzazione.** `availableModels`, `deniedModels` e `maxEffortLevel` possono vietare la scelta del router; il Default "scende" da solo e con `exact` Claude Code può non partire [9]. Il router deve trattarli come vincoli.
- **Cambio di modello a metà Sessione.** `setModel` cambia modello ma non la finestra di contesto: passare a un modello con contesto più piccolo può forzare una compattazione. `opusplan` usa "la finestra di contesto del rispettivo modello" [3].
- **Costo nascosto.** Uno sforzo alto consuma più della finestra di 5 ore dell'abbonamento (ADR 0003). La scelta del router va collegata all'uso visibile.
- **Dati del Progetto verso altri fornitori.** Una Domanda con file allegati diventa un invio al cloud: serve consenso per fornitore. Gemini gratuito in SEE non è ammesso e usa i dati per addestrare [24].
- **Compatibilità parziale.** Ollama in modalità Anthropic non supporta `tool_choice` né il caching [16]; MLX server non è da produzione [18]; Foundation Models ha 4.096 token [19]. Il router deve conoscere i limiti di ciascun motore.
- **Sessioni su modelli non Claude.** Tecnicamente `ANTHROPIC_BASE_URL=http://localhost:11434` fa girare Claude Code su Ollama [16], ma la mappa lo esclude: le Sessioni restano Claude.
- **Router cloud come dipendenza.** OpenRouter Auto sceglie per spesa della community [4], non per il gusto dell'utente; Not Diamond riceve i messaggi [6]. Solo come ripiego esplicito.
- **Chiave OpenRouter con ripiego sulla capacità condivisa.** Se le chiavi BYOK falliscono, OpenRouter passa da solo ai suoi endpoint e addebita i crediti; si spegne con "Never use shared capacity" [21].

## Mappa

Architettura comune in [INDEX.md](INDEX.md). Termini da `CONTEXT.md`: **Tipo di richiesta**, **Scala**, **Domanda**, **Sessione**, **Tinta**, **Variante**, **Livello di rischio**, **Sintesi parlata**.

### Cosa decide il router

Per ogni richiesta: **Tipo di richiesta** → modello · sforzo (e fornitore per le Domande), con un motivo in una riga. Nella stessa chiamata di classificazione esce anche la **Variante** per l'Orb ([Voce → Orb](https://github.com/mgiuditta/bubo/issues/57)); il suo percorso fino al Morph è nella pipeline degli ingressi di [09 — Sistema](09-sistema.md), qui non si ripete.

**Tipi di richiesta** (elenco chiuso; un Tipo nuovo solo per decisione esplicita) e **default** per famiglia, risolti sul catalogo di `supportedModels()`:

| Tipo | Default |
|---|---|
| Sessione · Pianifica | Opus · alto |
| Sessione · Correzione piccola (1–3 file) | Sonnet · medio |
| Sessione · Modifica ampia | Opus · medio |
| Sessione · Esplora il codice | Sonnet · basso |
| Sessione · Revisione | Opus · alto |
| Domanda · Fatto breve | Apple FM, altrimenti Haiku |
| Domanda · Riassunto | Haiku (Apple FM se l'Allegato sta in 2.000 token) |
| Domanda · Scrittura | Sonnet · medio |
| Domanda · Ragionamento | Opus · medio |
| Domanda · Ricerca sul web | Sonnet · basso |

Una preferenza "Usa sempre per «Tipo»" sostituisce il default: ambito il Progetto per le Sessioni, tutte le Domande per le Domande.

**Classificatore.**
- Senza Jev: Apple Foundation Models on-device (solo `SystemLanguageModel.default`, mai Private Cloud Compute), con **regole** di ripiego (parole pesate in italiano e inglese, segni di codice) senza Apple Intelligence, su errore o oltre i 300 ms. Una sola generazione guidata dà Tipo, Categoria e Variante: lo schema si costruisce a runtime (`DynamicGenerationSchema`, scelte chiuse come un enum) perché le Varianti vengono da `catalogo.json`; con centinaia di Varianti andrà in due passi, Categoria poi Variante. Codice, Salute e Chat sono divise in gruppi (`docs/catalogo-elenco.json`): nel primo passo i gruppi sono scelte a sé, 18 in tutto, così ogni rosa del secondo passo resta sotto le 40 voci.
- Con Jev (facoltativo, consigliato all'avvio con il costo): Jev decide Tipo e Variante (due passi: Categoria, poi Variante, per il limite di 255 opzioni) **solo se passa il cancello di adozione**; altrimenti fa da secondo parere. Jev vede solo il testo della richiesta e il contesto minimo (Sessione o Domanda, nomi dei file allegati), mai file, diff o memoria del Progetto. Versione fissata a `jev-1.13.0`. Budget 300 ms: oltre, su errore o offline → Apple FM + regole, detto nel motivo, nessun nuovo tentativo sul turno. Dettagli in [10-router-jev.md](10-router-jev.md).
- **Incertezza**: confidenza < 0,6 o prime due a meno di 0,15 (con Jev), o incertezza di Apple FM tra due Tipi (campo facoltativo `alternativa`, perché Foundation Models non dà probabilità) o pari punti tra due Tipi nelle regole → default più forte dei due, detto nel motivo ("Correzione 48% / Modifica ampia 41% → Opus medio"). Variante incerta → Blob con la Categoria scelta. Il router non chiede mai. Soglie tarabili.
- **Livello di rischio**: Jev è solo un segnale che alza, mai abbassa; i livelli 4–5 restano alle regole (feature 05).
- **Sintesi parlata**: esclusa da Jev, che non genera testo e dovrebbe vedere la risposta; la scrive il modello che risponde ([08](08-voce.md), [#63](https://github.com/mgiuditta/bubo/issues/63)).

**Nella Sessione.** Modello scelto all'avvio (o al `claim` del prewarm); cambia da solo solo al passaggio plan mode ↔ esecuzione (regola `opusplan`) o per override. Lo sforzo si rivaluta a ogni turno con `applyFlagSettings({effortLevel})`.

**Scala di "Rifai più forte".** Da `supportedModels()`: Haiku → Sonnet basso/medio/alto → Opus medio/alto/xhigh → Fable (se c'è). Prima lo sforzo, poi il modello. `max` fuori (solo di Sessione); gradini vietati da `availableModels`/`deniedModels`/`maxEffortLevel` saltati; in cima il comando si disattiva. Modelli vecchi solo da "Rifai con…". Per gli altri fornitori: i loro modelli, poi Claude.

**Fornitori delle Domande (v1).** Claude via Agent SDK (default); Apple Foundation Models; un solo client OpenAI-compatibile per OpenAI, Gemini (solo con fatturazione attiva, altrimenti avviso), OpenRouter (OAuth PKCE, senza "shared capacity"), Ollama e LM Studio (rilevati su localhost), endpoint personalizzati (xAI solo così). Chiavi nel Portachiavi, chiamate dirette dal Mac, nessun proxy. Le Sessioni restano sempre Claude.

**Scelta automatica di fornitore.** Da solo il router sceglie, fuori da Claude, solo Apple FM, l'unico modello di qualità nota. Ollama e LM Studio entrano solo per scelta dell'utente: un **Modello locale** unico nelle impostazioni, proposto una volta quando Bubo li rileva ("Hai Ollama con X: usarlo per Fatto breve e Riassunto?", con preselezionato il modello caricato in `/api/ps`, altrimenti il più recente di `/api/tags` o `/v1/models`; il sì diventa "Usa sempre per" su quei due Tipi), poi "Usa sempre per «Tipo»", "Rifai con…" e il ripiego della quota o senza rete. Nessun elenco di modelli consigliati. Un cloud diverso da Claude solo per "Rifai con…" o preferenza ricordata ([#65](https://github.com/mgiuditta/bubo/issues/65), rettifica il #52).

**Quota.** Finestra di 5 ore (feature 03) oltre l'80%: le scelte automatiche scendono di un gradino della Scala e il motivo lo dice; oltre il 95%, e senza rete, le Domande vanno al Modello locale se impostato, altrimenti ad Apple FM; le Sessioni restano su Claude. Mai blocchi, override intatti. Soglie nelle impostazioni.

**Privacy.** Contenuti del Progetto solo a Claude e ai modelli sul Mac. Verso un altro cloud: consenso per fornitore alla prima occorrenza, revocabile; senza consenso quel fornitore sparisce da "Rifai con…" per quel turno, con il motivo. Eccezione unica: Jev, con consenso unico all'aggiunta della chiave, e solo per il testo della richiesta.

### Interfaccia (variante A + chip da C, [prototipo](https://github.com/mgiuditta/bubo/tree/prototype/router))

- **Riga sotto ogni risposta**: pallino della Tinta, modello · sforzo **effettivo** (hook `effort.level`), motivo in una riga, costo stimato. Origine indicata: "(tua preferenza)", "scelto da te", "rifatto da te".
- **Costo**: Claude in % della finestra di 5 ore (login CLI, ADR 0003); altri fornitori in $ sulla chiave dell'utente; modelli sul Mac "gratis". Il costo di Jev non entra nella riga: totale mensile nelle impostazioni, nessun tetto.
- **Override sul turno**: "Rifai più forte" ⌘↑ (un gradino della Scala); "Rifai con…" ⌘⇧↑ (alternative vicine con dove gira, primo token, costo; da qui "Usa sempre per «Tipo»"). Il default non cambia.
- **Chip nel prompt** (prima di inviare): previsione modello · sforzo · costo con il motivo sopra; Tab/⇧Tab cambia modello, ⌥↑/⌥↓ lo sforzo, Esc torna al router. Il controllo dello sforzo compare solo se il modello lo supporta.
- **Voce**: con ⌥Spazio tenuto niente chip (invio al rilascio), solo riga dopo e ⌘↑/⌘⇧↑; con ⌥⇧ (dettatura nel prompt) la chip c'è.
- **Variante**: si vede sotto l'Orb ("Variante lente · Tinta Anthropic"), non nella riga, non si sovrascrive.
- Niente pannello router fisso nell'HUD: le preferenze si gestiscono da "Rifai con…" e dalle impostazioni.

### Moduli

- `Router/RequestClassifier`: motori in ordine, ciascuno nel suo budget, poi le regole (`RuleClassifier`); Apple FM in `FoundationModelsClassifier`. Interfaccia unica `ClassificationEngine`: Jev si aggiunge in testa come motore in più, e vede solo `ClassifierInput` (testo e nomi degli Allegati).
- `Router/JevClient`: `URLSession` su `api.typesafe.ai/v1/systemone` o OpenRouter (`~typesafe/jev-latest`), versione fissata, budget 300 ms, filtro del contenuto inviato.
- `Router/ModelRouter`: Tipo → modello · sforzo · fornitore; default, preferenze ricordate, Scala da `supportedModels()` con i vincoli dell'org, quota (feature 03), consensi; produce il motivo.
- `Router/Providers`: client OpenAI-compatibile (Chat Completions, streaming) + `FoundationModels`; rilevamento di Ollama e LM Studio su localhost; OAuth PKCE di OpenRouter; chiavi nel Portachiavi (`Account/`).
- `Agent/AgentBridge`: comandi `setModel` e `applyFlagSettings({effortLevel})` nel protocollo stdio; sforzo effettivo dall'hook `effort` verso Swift.
- `HUD/RouterLine`, `HUD/RouterChip`, menu "Rifai con…": interfaccia sopra.
- Persistenza: preferenze per Tipo (per Progetto e globali), consensi per fornitore, soglie di quota e di incertezza.

### Flusso

Richiesta (testo, voce o altro ingresso, vedi [09](09-sistema.md)) → classificazione (Jev se attivo e sotto 300 ms, altrimenti Apple FM, altrimenti regole) → Tipo + Variante → preferenza o default → vincoli (catalogo, org, quota, consenso) → modello · sforzo · fornitore + motivo → invio (Sessione: `model`/`effort` all'avvio o `setModel`/`applyFlagSettings` al turno; Domanda: SDK, Apple FM o client OpenAI-compatibile) → risposta con riga del motivo → eventuale override ⌘↑/⌘⇧↑ sul turno successivo.

### Casi limite

- Sforzo declassato in silenzio dall'SDK (Haiku senza sforzo, `max` → `high`): la riga mostra l'effettivo.
- Org con `deniedModels`/`maxEffortLevel`: gradini saltati, mai una scelta rifiutata.
- Apple Intelligence spenta o non disponibile: solo regole, detto nel motivo.
- Allegato oltre 2.000 token per Apple FM: Fatto breve e Riassunto vanno ad Haiku, e il motivo lo dice ("allegato troppo lungo per Apple FM → Haiku").
- Modello locale scaricato o server spento: si torna al default del Tipo, detto nel motivo.
- Cambio a un modello con finestra più piccola a metà Sessione: possibile compattazione.
- Gemini senza fatturazione in SEE: avviso, niente invio.
- OpenRouter che ripiega sulla capacità condivisa: spento.
- Jev lento, in errore o offline: ripiego locale, nessun nuovo tentativo.
- Quota oltre 95% senza modelli locali: nessun blocco; vale la discesa di un gradino dell'80%.

### Test

- Set etichettato di 200 richieste (metà it, metà en, 20 per Tipo): accuratezza di Apple FM, regole e Jev; è anche il cancello di adozione di Jev e il test di aggiornamento della sua versione.
  - File: `BuboTests/Fixtures/richieste-etichettate.json` ([#85](https://github.com/mgiuditta/bubo/issues/85)); controllo: `bun scripts/richieste-check.ts`.
  - **Provvisorio**: rivisto da Claude, non ancora dall'utente ([#367](https://github.com/mgiuditta/bubo/issues/367)). Fino ad allora l'accuratezza e il cancello di Jev misurati sul set non sono definitivi.
  - **JSON unico, non JSONL né CSV**: `JSONDecoder` lo legge nei test Swift senza codice in più, e i testi con virgole e virgolette restano leggibili.
  - **Tipi con id ASCII** (`sessione.correzione-piccola`), come i `nome` del Catalogo: stabili se cambia il nome mostrato.
  - **Variante `null`** quando nessuna voce del Catalogo di oggi si adatta: è il caso "Blob con la Categoria" del router. Il controllo accetta solo nomi di `catalogo.json` e solo con la loro Categoria, perché ogni Variante appartiene a una sola Categoria: `lente` solo nelle richieste di Categoria Ricerca. Le richieste di Esplora il codice che cercano nei file ("trova dove…") hanno Categoria Ricerca e `lente`, come dice la descrizione della Variante. Con le 11 Forme del primo blocco ([#355](https://github.com/mgiuditta/bubo/pull/355)) ogni Categoria ha la sua Variante: una richiesta prende quella della sua Categoria quando corrisponde chiaramente alla Forma (`parentesi` per il codice, `nuvola` per il meteo, `moneta` per la borsa). Una ricerca sul web di un dominio preciso tiene la sua Categoria e la Variante di quel dominio. Restano `null` quasi tutte le richieste di Chat, che è la Categoria generica e non parla di conversazioni, e poche altre al confine: una didascalia sul temporale, un'agenda, un promemoria per le pause, un prefisso telefonico, un messaggio di benvenuto. Le etichette crescono con i blocchi del Catalogo.
  - **Le 100 richieste inglesi sono casi diversi dalle italiane**, non traduzioni: un errore del classificatore conta una volta sola e il set copre 200 casi distinti. Le Domande in inglese pescano soprattutto dalle Categorie piccole (Meteo, Tempo, Musica, Salute, Viaggi, Creativo).
  - Lo controlla anche `scripts/check.sh`.
  - **Categoria** dall'enum `Categoria.swift`, letta dal controllo: una sola fonte.
  - **`allegati`** con i soli nomi dei file, il contesto minimo che vede anche Jev; nei Riassunti la richiesta ha senso solo con l'Allegato.
  - Le Domande che chiedono dati del momento (meteo, cambi, orari) stanno in Ricerca sul web, non in Fatto breve, perché Apple FM non li conosce.
- Latenza del classificatore p95 (regole, Apple FM, Jev dall'Italia con handshake).
- Scala su cataloghi finti (`supportedModels()` con e senza Fable, con `deniedModels`, `maxEffortLevel`).
- Corpo delle richieste a Jev e ai cloud non Claude: 0 byte di file, diff o memoria del Progetto senza consenso.
- Override in Sessione: `setModel`/`applyFlagSettings` attivi dal turno successivo senza riavvio.
- Ripiego: timeout, errore e rete assente di Jev → scelta locale nel 100% dei casi.

## Specifica "migliore di"

Miglior concorrente: **Cursor Auto** per la qualità della scelta e **OpenRouter Auto** per la trasparenza; entrambi classificano nel cloud, Cursor nasconde il modello di default, OpenRouter dà il tipo di compito solo in un header opt-in. Nessuno offre l'override sulla singola risposta.
Bubo li supera così:
- **Motivo sul 100% delle risposte** (modello · sforzo effettivo · motivo · costo), contro 0% di default in Cursor.
- **Decisione ≤ 50 ms p95** con le regole, **≤ 300 ms p95** on-device o con Jev (dall'Italia, handshake compreso), sempre prima del primo Morph.
- **Accuratezza ≥ 85%** del Tipo di richiesta su 200 richieste etichettate (metà it, metà en, 20 per Tipo).
- **0 scelte rifiutate** per modello o sforzo non disponibile; **0 byte del prompt a router di terzi**, salvo Jev con chiave e consenso (solo testo della richiesta); **0 byte** di file, diff o memoria del Progetto verso Jev o cloud non Claude senza consenso.
- **Override attivo dal turno successivo** senza riavviare la Sessione; "Rifai più forte" in 1 tasto (⌘↑).
- **Ripiego locale nel 100%** dei casi di timeout, errore o rete assente di Jev.
- **Cancello di Jev**: motore principale di Tipo e Variante solo se batte Apple FM di **≥ 5 punti** di accuratezza in italiano sulle 200 richieste.
- Segnale di taratura (non bloccante): "Rifai più forte" **< 15%** delle risposte, misurato in locale.

## Fonti

1. Cursor, "Cursor Router" — https://cursor.com/docs/cursor-router
2. Cursor, "Models" — https://cursor.com/docs/models
3. Claude Code, "Model configuration" (alias, `opusplan`, livelli di sforzo e default) — https://code.claude.com/docs/en/model-config
4. OpenRouter, "Auto Router" — https://openrouter.ai/docs/guides/routing/routers/auto-router
5. Not Diamond, "Key concepts" — https://docs.notdiamond.ai/docs/key-concepts
6. Not Diamond, "Chat Router Quickstart" — https://docs.notdiamond.ai/docs/quickstart-routing.md ; API `modelSelect` — https://docs.notdiamond.ai/reference/token_model_select_v2_modelrouter_modelselect_post.md
7. Martian, "Quickstart Guide" — https://docs.withmartian.com/quickstart
8. Raycast, "Changes to Bring Your Own AI in v2" — https://manual.raycast.com/ai/byoai ; "Custom providers" — https://manual.raycast.com/ai/custom-providers
9. `@anthropic-ai/claude-agent-sdk` 0.3.284, `sdk.d.ts` (`Options.model|effort|thinking|fallbackModel`, `Query.setModel`, `applyFlagSettings`, `supportedModels`, `ModelInfo`, `AgentDefinition.model|effort`, hook `effort`, `prewarm`/`claim`, `Settings.availableModels|deniedModels|maxEffortLevel|modelSettings`) — https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk
10. OpenAI, "Services Agreement", §3 Restrictions — https://openai.com/policies/services-agreement/ (403 al fetch diretto; testo dal PDF https://cdn.openai.com/osa/openai-services-agreement.pdf e dall'estratto indicizzato)
11. OpenAI Help, "Best Practices for API Key Safety" — https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety
12. Google, "OpenAI compatibility" (Gemini API) — https://ai.google.dev/gemini-api/docs/openai
13. xAI, "Integrations" (compatibilità OpenAI e Anthropic, base URL) — https://docs.x.ai/api/integrations
14. xAI, "API reference — Responses" — https://docs.x.ai/docs/api-reference
15. Ollama, "OpenAI compatibility" — https://docs.ollama.com/api/openai-compatibility
16. Ollama, "Anthropic compatibility" — https://docs.ollama.com/api/anthropic-compatibility
17. LM Studio, "Developer docs" — https://lmstudio.ai/docs/developer
18. ml-explore/mlx-lm, `SERVER.md` — https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/SERVER.md
19. Apple, TN3193 "Managing the on-device foundation model's context window" (rev. 2026-03-31) — https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window
20. OpenRouter, "FAQ" (commissioni, nessun ricarico, log dei prompt) — https://openrouter.ai/docs/faq
21. OpenRouter, "BYOK" — https://openrouter.ai/docs/guides/overview/auth/byok
22. OpenRouter, "OAuth PKCE" — https://openrouter.ai/docs/guides/overview/auth/oauth
23. Claude Code, "Agent SDK overview" (nota sul login claude.ai, branding, licenza) — https://code.claude.com/docs/en/agent-sdk/overview
24. Google, "Gemini API Additional Terms of Service" (in vigore dal 2026-03-23, agg. 2026-04-28) — https://ai.google.dev/gemini-api/terms
25. Cursor, "API keys" — https://cursor.com/docs/settings/api-keys

Misura A: script locale sull'SDK 0.3.284 con la CLI inclusa nel pacchetto, eseguito su questo Mac il 2026-09-29 (`query()` in streaming, `supportedModels()`, nessun prompt inviato al modello).

Decisioni: [#50](https://github.com/mgiuditta/bubo/issues/50) (interfaccia), [#52](https://github.com/mgiuditta/bubo/issues/52) (Tipi, default, Scala, fornitori, quota, privacy, criteri), [#57](https://github.com/mgiuditta/bubo/issues/57) (Variante nella stessa chiamata), [#58](https://github.com/mgiuditta/bubo/issues/58) e [#59](https://github.com/mgiuditta/bubo/issues/59) (Jev), ADR 0003 (login e uso).
