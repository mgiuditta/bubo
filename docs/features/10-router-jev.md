# 10 — Jev (TypeSafe) come motore di decisione

Ricerca allegata a [10 — Router](10-router.md).

Ticket: [#58](https://github.com/mgiuditta/bubo/issues/58). Mappa: [#42](https://github.com/mgiuditta/bubo/issues/42). Decisione del router: [#52](https://github.com/mgiuditta/bubo/issues/52).
Ricerca del 2026-09-30 su **jev-1.13.0** (alias `jev-latest`, doc "jaggedness" rivista il 2026-09-17).

In sintesi: Jev è un modello cloud che **non genera testo**. Riceve uno `state` (testo o JSON) e una mappa di domande tipizzate; restituisce per ciascuna un sì/no (`noul`, 0–1), una scelta da elenco (`choice`, al massimo **255 opzioni**) o una posizione su una scala (`score`, da 2 a **10 livelli**), con probabilità e `confidence`. Costa **$0,042 per milione di token in ingresso**, l'uscita è gratis. La latenza dichiarata è "circa 100 ms" e nei cookbook ufficiali la media misurata è **111–114 ms** andata e ritorno, dagli USA. L'**italiano è supportato ma non garantito**: l'inglese è la lingua dove funziona meglio. Per Bubo si presta bene a decisioni **su testo che l'utente ha già deciso di mandare al cloud**, oppure su testo senza dati del Progetto: la Variante dal Catalogo, in due passaggi perché 500 > 255, e i controlli con Noul. Come **classificatore del Tipo di richiesta non rispetta il criterio "0 byte del prompt a router di terzi"** deciso in #52: lì resta Apple Foundation Models, con Jev solo come secondo parere su consenso. Sul **Livello di rischio** va bene come segnale in più, mai come unico giudice.

## Ricerca

### Cos'è e cosa fa

TypeSafe lo chiama "System One model": fa giudizi rapidi e stretti ("la decisione che una persona esperta prenderebbe in pochi secondi") e lascia al codice il controllo del flusso [1][2]. Non scrive testo, non ragiona a più passaggi e non chiama tool. Non sostituisce il modello di un agente di coding [3].

| Tipo | Domanda | Risposta | Limiti |
|---|---|---|---|
| **Noul** | "È vero che…?" | `noul`: probabilità del sì, da 0 a 1. Niente `confidence` | `criteria` facoltativi (`true`/`false`) [4] |
| **Choice** | "Quale di queste opzioni?" | `choice`, `probabilities` (somma 1), `confidence` | **Massimo 255 opzioni** per Choice [4] |
| **Score** | "A che livello?" | `score` (media pesata, può cadere tra due livelli), `legend`, `probabilities`, `confidence` | Da 2 a **10 livelli** ordinati [4] |

- Più domande nella stessa chiamata vengono valutate **in parallelo e ognuna per conto suo** contro lo stesso `state`. Secondo TypeSafe aggiungere domande "cambia appena" il tempo di risposta [2]. In un cookbook, 13 domande in una chiamata sono state 12,2 volte più economiche e 10 volte più veloci di 13 chiamate separate: 0,27 s contro 2,71 s [5].
- `confidence` è una statistica calcolata dalla distribuzione. La doc suggerisce tre fasce (agisci / conferma / non agire) e soglie che **crescono con la gravità** dell'azione [6].
- **Input**: 64k token per richiesta, di cui 32k per `state` più la domanda più lunga. Solo testo: stringa, oggetto JSON o array [7].
- **Limiti noti** (doc "jaggedness" 1.13) [8]: legge le istruzioni alla lettera; non conta e non fa conti; non confronta date; perde accuratezza con le indirezioni e con uno `state` pieno di cose irrilevanti; **contenuto avversario nello `state` può spostare la risposta** (prompt injection); Noul e Choice sulla stessa domanda non sono confrontabili tra loro; non genera testo.

### Numeri: prezzo, limiti, latenza

| Voce | Valore | Fonte |
|---|---|---|
| Prezzo | $0,042 / M token in ingresso ($42 / miliardo); uscita gratis | [7] |
| Rate limit (API diretta) | 250.000 token/s, 1.200 richieste/min; "possono cambiare senza preavviso" | [7] |
| Latenza dichiarata | "La maggior parte delle query si completa in circa 100 ms" [9]; "150ms" negli esempi d'uso [10] | TypeSafe |
| Latenza misurata da TypeSafe | Media andata e ritorno di **114 ms** (Choice, 15 chiamate) e **111 ms** (Noul), contro 0,8–13 s degli LLM nello stesso test [11][12] | cookbook ufficiali |
| Latenza misurata da noi | **Non misurata**: nell'ambiente non c'è `TYPESAFE_API_KEY` e non abbiamo creato account. I server sono negli USA [13]: dall'Italia la rete aggiunge un tempo di andata e ritorno transatlantico. È una **stima non verificata**, da misurare con la chiave dell'utente | — |
| Costo per Bubo (stima) | Una richiesta di routing di ~500 token costa circa $0,00002. 1.000 decisioni al giorno costano circa 2 centesimi | calcolo su [7] |

### Come si raggiunge

| Via | Endpoint e modello | Contesto | Chiave | Note |
|---|---|---|---|---|
| **API diretta** | `POST https://api.typesafe.ai/v1/systemone`, `model: "jev-latest"` o `"jev-1.13.0"` | 64k | Bearer, chiave da `console.typesafe.ai/keys` | Riferimento [4][14]. Accesso: la home parla di "early access" [15]; un articolo di terzi del 24 settembre dice che le iscrizioni sono **sospese** e gli account esistenti funzionano [16]. **Non verificato in fonte primaria** (la console risponde 403 senza login) |
| **OpenRouter** | `POST https://openrouter.ai/api/v1/systemone` (anche `api/alpha/decisions`), `typesafe/jev-1.13` o `~typesafe/jev-latest` | **32k** | Chiave OpenRouter | Basta un account OpenRouter, pagamento sui crediti OpenRouter [17]. È compatibile con l'SDK TypeSafe cambiando `base_url` [18] |
| **Vercel AI Gateway** | `https://ai-gateway.vercel.sh/typesafe/v1/systemone`, `typesafe-ai/jev`. C'è anche l'API generica `POST /v1/evaluate` | — | Chiave AI Gateway, oppure BYOK con chiave TypeSafe | Stesse forme di richiesta e risposta, più `provider_metadata.gateway.cost` e un **ripiego** su un altro modello se `confidence` scende sotto una soglia [19][20] |
| **Cloudflare** | `POST …/accounts/{id}/ai/run`, modello `typesafe/jev` (anche binding `env.AI.run`) | **32k** | Token Cloudflare | La pagina dichiara "Zero data retention" [21] |
| Pydantic AI Gateway | `https://gateway-us.pydantic.dev/proxy/typesafe` | — | Chiave Pydantic | Citato nella doc dell'SDK [18] |

**SDK**: Python `typesafe-sdk` e JavaScript `@typesafe-ai/sdk` [18][22]. **Non esiste un SDK Swift**: per Bubo basta `URLSession` con JSON su un endpoint solo. L'SDK JS rifiuta di girare nel browser se non si attiva `dangerouslyAllowBrowser`, perché la chiave sarebbe esposta agli utenti della pagina [22]. In un'app desktop con la chiave dell'utente nel Portachiavi questo rischio non c'è.

**Esempio di richiesta e risposta** (dalla API reference [4]):

```json
{
  "state": "Help! My payouts have been failing for 3 days.",
  "model": "jev-latest",
  "questions": {
    "department": {
      "type": "choice",
      "instructions": "Which team should handle this?",
      "criteria": {
        "billing": "Payments, invoicing, refunds",
        "technical": "Bugs, outages, integrations",
        "sales": "Pricing, upgrades, new accounts"
      }
    }
  }
}
```

```json
{
  "model": "jev-1.13.0",
  "answers": {
    "department": {
      "type": "choice",
      "choice": "billing",
      "probabilities": { "billing": 0.88, "technical": 0.12, "sales": 0.0 },
      "confidence": 0.81
    }
  },
  "usage": { "input_tokens": 318, "output_tokens": 34 }
}
```

Errori: `401` chiave, `422` validazione, `429` limite superato, `529` servizio sovraccarico. Su `429` e `529` si ritenta con backoff esponenziale [4]. Il campo `model` della risposta riporta la versione esatta: gli alias si spostano e le soglie tarate vanno legate a una versione fissa [7].

### Dati e termini d'uso

- **Addestramento**: "Jev non è addestrato sulle richieste o risposte dei clienti" [7]. L'informativa privacy aggiunge: "non addestreremo né faremo fine-tuning … sui vostri prompt o altri Input" [13].
- **Conservazione**: nessuna durata pubblicata, solo "per quanto ragionevolmente necessario" [13][23]. La **Zero Data Retention c'è solo per i clienti enterprise**, su contratto [24]. Via Cloudflare la pagina del modello dichiara zero data retention [21]. Per OpenRouter la guida su Jev non dice nulla sulla conservazione [17].
- **Dove**: i servizi sono ospitati negli USA [13]. Il DPA prevede le Clausole Contrattuali Standard UE, modulo 2, con l'Irlanda come autorità competente [23].
- **Chiave dell'utente in un'app desktop**: il Master Customer Agreement permette di integrare l'API in applicazioni per i propri utenti finali, chiede di tenere riservate le credenziali e di non darne accesso a chi non è dipendente o collaboratore del cliente [25]. In Bubo il cliente è l'utente: la chiave è sua, sta sul suo Mac e la usa lui. Non si condivide e non si ridistribuisce nulla, e lo schema è lo stesso già accettato per OpenAI in `10-router.md`. **Non letta** la Acceptable Use Policy completa. **Da verificare**: se TypeSafe ammette esplicitamente client desktop di terzi (qui la lettura è nostra, non una clausola esplicita).
- **Lingue**: "L'inglese è la lingua principale di addestramento e quella dove oggi l'accuratezza è migliore. Le altre lingue … sono gestite ma non altrettanto bene; testate sui vostri contenuti prima di affidarvi a Jev per un carico non in inglese" [7]. **Sull'italiano non ci sono dati.** Criteri e istruzioni si possono scrivere in inglese anche quando lo `state` è in italiano: è un'ipotesi da misurare.

### Usi tipici documentati

TypeSafe li pubblica come pattern e cookbook: instradamento per intento con `confidence` minima 0,5 prima di passare a un umano [26]; soglie di confidenza legate alla gravità [6]; "speculative fan-out", cioè fare in una chiamata tutte le domande che potrebbero servire [27]; guardrail in ingresso e in uscita da un LLM con una serie di Noul di pericolo e uno Score di danno [28]; **scelta di una skill tra le 182 del catalogo Hermes**, con due richieste (ordina tutto, poi ricontrolla le prime tre con descrizioni lunghe), che ha ridotto i caricamenti sbagliati dal 16,8% al 7,3% [29]; classificazione gerarchica con beam search su tassonomie profonde [30]; classificazione dei passaggi RAG [31]; verifica delle citazioni [32]; function calling su argomenti a insieme chiuso [33]. Vercel documenta l'**auto-approvazione delle chiamate a tool** in eve: una Choice `clear`/`caution` sul solo comando e i suoi argomenti, senza la conversazione [34].

## Il meglio da battere / adatto a Bubo

Confronto sulle stesse decisioni con **Apple Foundation Models** (on-device, ~3 miliardi di parametri, 15 lingue tra cui l'italiano [35]; 4.096 token di contesto per sessione [36]). La guided generation con `@Generable` usa campionamento vincolato: l'uscita è sempre un tipo Swift valido, quindi anche un `enum` chiuso [37]. C'è anche un caso d'uso `contentTagging` [38]. **Nelle pagine lette Foundation Models non restituisce probabilità o confidenza**, e Apple non pubblica cifre di latenza [35]: tutte e due le cose sono da misurare sul Mac.

| Decisione di Bubo | Jev | Apple Foundation Models | Verdetto |
|---|---|---|---|
| **Tipo di richiesta** (10 classi chiuse, #52) | Adatto per forma: Choice con 10 opzioni più `confidence` per decidere quando chiedere o ripiegare, come nel pattern di intent routing [26]. Latenza ~110 ms più la rete dagli USA. **Viola però il criterio 4 di #52 (0 byte del prompt a router di terzi)** e il vincolo "contenuti del Progetto solo a Claude e ai modelli sul Mac" | Enum `@Generable` a 10 casi, in locale, senza rete, in italiano. Niente confidenza nativa: l'incertezza va ricavata in altro modo (regole, ripetizione) | **Resta Apple FM più le regole.** Jev solo come secondo parere facoltativo con consenso esplicito per fornitore, o per le Domande senza Progetto se l'utente l'ha attivato. Misurare accuratezza e latenza su 200 richieste (metà in italiano) prima di qualunque promozione |
| **Variante dal Catalogo** (fino a 500) | 500 > 255: servono **due passaggi**, per esempio Categoria (12) e poi Variante nella Categoria, oppure blocchi da ≤255 e poi un ricontrollo della rosa corta. È il pattern della scelta di skill, provato su 182 voci [29], e della classificazione gerarchica [30]. I nomi e le descrizioni delle Varianti non sono dati del Progetto, e con la richiesta dell'utente come `state` bastano 1–2 round trip | 500 voci non stanno in 4.096 token con le descrizioni. Anche qui servono due passaggi (Categoria → Variante), oppure un preordinamento con embedding o regole | **Il punto dove Jev rende di più**: scelta con probabilità, e la seconda Variante utile per il Morph. Il vincolo resta la privacy della richiesta: se il testo contiene contenuti del Progetto serve il consenso. Senza consenso, Apple FM in due passaggi. Non deve mai ritardare il primo Morph: la Variante può arrivare dopo il Blob |
| **Livello di rischio** di un'azione (1–5) | Uno Score a 5 livelli rientra nei limiti (≤10) [4]. La doc lega le soglie alla gravità [6] e Vercel lo usa per auto-approvare comandi [34]. Ma il comando è **contenuto avversario** possibile, e 1.13 può esserne influenzato [8]. Il comando e i suoi argomenti sono dati del Progetto | Enum a 5 casi in locale, stesso rischio di injection, nessuna confidenza | **Solo come segnale aggiuntivo.** Il livello lo decidono le regole deterministiche (tipo di tool, comando, percorso). Un modello può solo **alzare** il livello, mai abbassarlo. I livelli 4–5 non passano mai da un modello |
| **Cosa scrivere in memoria / Secondo cervello** | Noul "vale la pena ricordarlo?" più Choice sulla destinazione (Memoria di Progetto / Secondo cervello / niente). Se serve anche la nota giusta, Choice sui titoli o sulle righe candidate [31][39]. Il testo da scrivere lo genera Claude, non Jev [8] | Fattibile con `@Generable`, in locale e sui dati del Progetto senza consenso | **Apple FM di default** (tocca dati del Progetto). Jev con consenso quando serve una rosa grande di note (fino a 255 per domanda) |
| Altre, dai casi d'uso documentati | **Guardrail/verifica**: controllare se una risposta cita correttamente un file [32]. **Scelta di skill/subagent** per il turno [29]. **"Attende te"**: Noul "il messaggio dell'agente sta chiedendo qualcosa all'utente?". **Sintesi parlata** estrattiva: Choice sulle frasi della risposta da leggere [39]. **Filtro dei passaggi del Secondo cervello** prima di passarli a Claude [31] | Tutte fattibili in locale entro 4.096 token | Da valutare una per una. Jev conviene quando ci sono molte domande in parallelo sullo stesso testo, oppure una rosa di opzioni grande |

**Criteri candidati per l'uso di Jev in Bubo:**

1. **Privacy prima di tutto**: nessuna chiamata a Jev con contenuti del Progetto senza il consenso per fornitore già previsto in #52. La Variante e il Tipo di richiesta si calcolano sempre anche in locale.
2. **Latenza**: p95 ≤ 300 ms dall'Italia, misurata con la chiave dell'utente, altrimenti Jev non entra nel percorso sincrono prima del primo Morph.
3. **Accuratezza in italiano** ≥ Apple FM sullo stesso set di 200 richieste etichettate. Altrimenti Jev resta spento per le richieste in italiano.
4. **Soglie legate a una versione fissa** (`jev-1.13.0`, non `jev-latest`) [7], con `confidence` salvata nel log locale per la taratura.
5. **Chiave nel Portachiavi**, chiamata diretta dal Mac a `api.typesafe.ai` (oppure OpenRouter con la chiave OAuth già prevista), senza proxy di Bubo.

## Rischi e casi limite

- **Accesso incerto.** Le iscrizioni dirette risultano in "early access" e, secondo fonti di terzi, sospese [15][16]. Se l'utente non ha già un account, l'unica via senza lista d'attesa è un gateway: OpenRouter (32k, già nell'architettura di #52) o Vercel/Cloudflare, che richiedono un altro account.
- **Conflitto con #52.** Usare Jev per il Tipo di richiesta porta il prompt a un servizio cloud di terzi e fallisce il criterio 4. Va trattato come fornitore cloud con consenso, non come parte del router locale.
- **Italiano non garantito** [7]: senza misure, il rischio è un'accuratezza sotto l'85% sulle richieste in italiano.
- **Prompt injection** nello `state` [8]: grave per il Livello di rischio e per i permessi.
- **Conservazione dei dati non dichiarata** per l'API diretta: ZDR solo enterprise [24]. Via OpenRouter la policy di Jev non è documentata [17].
- **Alias che si muovono**: `jev-latest` può cambiare risposta senza preavviso [7].
- **Rate limit dinamici** [7]: con picchi di domanda può arrivare un `429`/`529`, e il router deve avere sempre il ripiego locale.
- **Limite di 255 opzioni e 32k di contesto sui gateway**: il Catalogo da 500 non entra in una sola Choice, e OpenRouter e Cloudflare hanno metà del contesto dell'API diretta [17][21].
- **Latenza reale non misurata**: i 111–114 ms sono di TypeSafe, dagli USA [11][12].

## Mappa

_da definire_

## Fonti

1. TypeSafe, "System One" — https://docs.typesafe.ai/concepts/system-one
2. TypeSafe, "Introduction" — https://docs.typesafe.ai/introduction
3. TypeSafe, "Jev with coding agents" — https://docs.typesafe.ai/introduction/coding-agents
4. TypeSafe, "API reference" — https://docs.typesafe.ai/api
5. TypeSafe, cookbook "Parallel questions" — https://docs.typesafe.ai/cookbooks/parallel_questions
6. TypeSafe, "Confidence" — https://docs.typesafe.ai/confidence
7. TypeSafe, "Models" (prezzo, limiti, contesto, lingue, alias, dati) — https://docs.typesafe.ai/models
8. TypeSafe, "Jev 1.13 jaggedness" (rivista il 2026-09-17) — https://docs.typesafe.ai/model-jaggedness/jev-1.13
9. TypeSafe, "How to build with TypeSafe" (card "Fast") — https://docs.typesafe.ai/concepts/how-to-build-with-system-one
10. TypeSafe, "Example use cases" — https://docs.typesafe.ai/concepts/use-case-map
11. TypeSafe, cookbook "Self-consistency: choices" (114 ms) — https://docs.typesafe.ai/cookbooks/consistency_choice_cookbook
12. TypeSafe, cookbook "Self-consistency: nouls" (111 ms) — https://docs.typesafe.ai/cookbooks/consistency_noul_cookbook
13. TypeSafe, Privacy Policy — https://typesafe.ai/legal/privacy-policy
14. TypeSafe, "Quick start" — https://docs.typesafe.ai/introduction/quickstart
15. TypeSafe, home page ("early access", 0,114 s) — https://typesafe.ai/
16. Flavio Copes, "How to get a Jev API key" (fonte secondaria; iscrizioni sospese al 2026-09-24) — https://flaviocopes.com/jev-api-key/
17. OpenRouter, "Jev" (guida community) — https://openrouter.ai/docs/guides/community/jev
18. TypeSafe, Python SDK "Usage" (base URL per OpenRouter, Vercel, Pydantic) — https://docs.typesafe.ai/sdk/python/usage
19. Vercel, "TypeSafe API with AI Gateway" (agg. 2026-09-21) — https://vercel.com/docs/ai-gateway/sdks-and-apis/typesafe
20. Vercel, changelog "AI Gateway now supports TypeSafe clients and HTTP API for Jev" — https://vercel.com/changelog/ai-gateway-now-supports-typesafe-clients-and-http-api-for-jev
21. Cloudflare, "Jev (typesafe)" — https://developers.cloudflare.com/ai/models/typesafe/jev/
22. TypeSafe, JavaScript SDK `TypeSafeClientConfig` (`dangerouslyAllowBrowser`) — https://docs.typesafe.ai/sdk/javascript/api/interfaces/TypeSafeClientConfig
23. TypeSafe, Data Processing Agreement — https://typesafe.ai/legal/data-processing
24. TypeSafe, "Legal" (ZDR per enterprise) — https://docs.typesafe.ai/legal
25. TypeSafe, Master Customer Agreement — https://typesafe.ai/legal/mca
26. TypeSafe, pattern "Intent routing" — https://docs.typesafe.ai/patterns/intent-routing
27. TypeSafe, pattern "Speculative fan-out" — https://docs.typesafe.ai/patterns/fan-out
28. TypeSafe, cookbook "Guardrails for LLMs" — https://docs.typesafe.ai/cookbooks/llm_guardrails
29. TypeSafe, cookbook "Skill suggestion" (182 skill, 16,8% → 7,3%) — https://docs.typesafe.ai/cookbooks/skill_suggestion
30. TypeSafe, cookbook "Hierarchical classification" — https://docs.typesafe.ai/cookbooks/hierarchical_classification
31. TypeSafe, cookbook "Classifying RAG passages" — https://docs.typesafe.ai/cookbooks/classifying_rag_passages
32. TypeSafe, cookbook "Double-checking citations" — https://docs.typesafe.ai/cookbooks/citation_check
33. TypeSafe, cookbook "Function calling" — https://docs.typesafe.ai/cookbooks/function_calling
34. Vercel KB, "Auto-approve tool calls in eve with Jev" — https://vercel.com/kb/guide/auto-approve-tool-calls-eve-jev
35. Apple Machine Learning Research, "Apple Intelligence Foundation Language Models, 2025 updates" — https://machinelearning.apple.com/research/apple-foundation-models-2025-updates
36. Apple, TN3193 "Managing the on-device foundation model's context window" — https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window
37. Apple, "Generating Swift data structures with guided generation" — https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation
38. Apple, `SystemLanguageModel.UseCase.contentTagging` — https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/usecase/contenttagging
39. TypeSafe, cookbook "Line-by-line search" (Choice su 218 righe) — https://docs.typesafe.ai/cookbooks/semantic_find

Fonti secondarie consultate solo come punti di partenza, non citate come prova: llmreference.com (contesto, data di uscita), apidog.com (vie d'accesso; riporta una latenza "70–500 ms" non trovata in fonte primaria).
