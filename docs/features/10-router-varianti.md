# 10 — Router: set etichettato con la Variante e budget di token

Nota di lavoro per [#381](https://github.com/mgiuditta/bubo/issues/381) (scelta della Variante in due passaggi, Categoria poi Variante). L'elenco delle Varianti è quello **provvisorio** di [#377](https://github.com/mgiuditta/bubo/issues/377) (`docs/catalogo-elenco.json`, revisione dell'utente in [#393](https://github.com/mgiuditta/bubo/issues/393)): quando l'elenco cambia, cambiano anche le etichette.

## Il set

File: `BuboTests/Fixtures/richieste-varianti.json`. Controllo: `python3 scripts/varianti-set-check.py` (solo libreria standard, esce con 1 se fallisce).

- **Stesso formato di #85** (`richieste-etichettate.json`): `versione`, `revisione`, `tipi` e `richieste` con `id`, `lingua`, `testo`, `tipo`, `categoria`, `variante`, `allegati` facoltativi. In più `elenco` (il file da cui vengono i nomi) e, per ogni richiesta, `seconda`: una seconda Variante accettabile nei casi ambigui, `null` altrimenti.
- **`variante` qui è un nome dell'elenco di #377**, non di `catalogo.json`: per questo il set è un file fratello e non una colonna in più nel set di #85, che `scripts/richieste-check.ts` e `RequestClassifierTests` leggono con le Varianti di `catalogo.json` (deciso nella notte, reversibile: si può fondere quando l'elenco entra nel Catalogo).
- **374 richieste in italiano**, scritte da zero: nessuna copia degli `esempi` dell'elenco (servono a misurare) né delle 200 richieste di #85. Brevi e lunghe, colloquiali, con qualche refuso, nomi di file e di progetti, allegati in 19 righe.
- **Ogni Variante dei blocchi 1–5 (le prime 120) ha almeno 2 righe**; in tutto le righe usano 134 Varianti. 216 righe hanno una seconda Variante.
- **Categoria** coerente con la Variante (il controllo lo verifica sull'elenco).

### Distribuzione per Tipo

Il set di #85 ha 20 richieste per Tipo, cioè il 10% ciascuno. Il controllo ammette 2 punti di scarto (deciso nella notte, reversibile).

| Tipo | Righe | Questo set | #85 |
|---|---:|---:|---:|
| sessione.pianifica | 36 | 9,6% | 10% |
| sessione.correzione-piccola | 36 | 9,6% | 10% |
| sessione.modifica-ampia | 36 | 9,6% | 10% |
| sessione.esplora | 36 | 9,6% | 10% |
| sessione.revisione | 36 | 9,6% | 10% |
| domanda.fatto-breve | 41 | 11,0% | 10% |
| domanda.riassunto | 38 | 10,2% | 10% |
| domanda.scrittura | 37 | 9,9% | 10% |
| domanda.ragionamento | 39 | 10,4% | 10% |
| domanda.ricerca-web | 39 | 10,4% | 10% |

### Copertura per Categoria

| Categoria | Righe | Varianti coperte / totali | Prime 120 con ≥ 2 righe |
|---|---:|---:|---:|
| Codice | 162 | 42 / 91 | 28 / 28 |
| Chat | 32 | 14 / 87 | 14 / 14 |
| Ricerca | 30 | 10 / 27 | 10 / 10 |
| Agente | 22 | 7 / 36 | 7 / 7 |
| Tempo | 18 | 8 / 18 | 8 / 8 |
| Finanza | 17 | 8 / 24 | 8 / 8 |
| Mail | 17 | 8 / 17 | 8 / 8 |
| Creativo | 16 | 8 / 34 | 8 / 8 |
| Viaggi | 16 | 7 / 38 | 7 / 7 |
| Salute | 16 | 8 / 53 | 8 / 8 |
| Meteo | 14 | 7 / 21 | 7 / 7 |
| Musica | 14 | 7 / 34 | 7 / 7 |

Codice pesa il 43% perché metà dei Tipi sono di Sessione, come in #85. Le Varianti dei blocchi 6–20 sono coperte solo dove servivano a etichettare bene una richiesta (`compasso`, `elmetto`, `lanterna`, `lavagna`…): vanno aggiunte righe man mano che i blocchi entrano nel Catalogo.

## Budget di token

Script: `python3 scripts/varianti-token.py`. Conta `nome: descrizione` per riga a 4 caratteri per token; tra parentesi a 3,3, la stima di #394 per l'italiano, più prudente.

Deciso nella notte, reversibile: contesto di Apple Foundation Models 4.096 token, **margine 1.200** per istruzioni di sistema, schema della generazione guidata, richiesta e risposta; **budget utile 2.896 token** per la rosa.

### Secondo passaggio (rose effettive)

| Rosa | Voci | Token (4 car) | Token (3,3 car) | Budget |
|---|---:|---:|---:|---:|
| agente | 36 | 674 | 817 | 23% |
| viaggi | 38 | 592 | 717 | 20% |
| chat/conversazione | 33 | 556 | 675 | 19% |
| musica | 34 | 556 | 673 | 19% |
| creativo | 34 | 547 | 663 | 19% |
| codice/scrittura | 30 | 546 | 661 | 19% |
| ricerca | 27 | 507 | 615 | 18% |
| chat/natura | 32 | 441 | 535 | 15% |
| codice/verifica | 23 | 434 | 527 | 15% |
| codice/rilascio | 23 | 418 | 507 | 14% |
| salute/corpo | 27 | 416 | 504 | 14% |
| finanza | 24 | 414 | 501 | 14% |
| salute/movimento | 26 | 364 | 442 | 13% |
| meteo | 21 | 342 | 414 | 12% |
| chat/casa | 22 | 305 | 370 | 11% |
| mail | 17 | 295 | 357 | 10% |
| tempo | 18 | 291 | 353 | 10% |
| codice/infrastruttura | 15 | 269 | 326 | 9% |

Senza gruppi le Categorie intere restano sotto il budget anche loro: Codice 1.667 token (2.021 a 3,3), Chat 1.302 (1.579), Salute 780 (946).

### Primo passaggio

18 scelte (9 gruppi con la loro descrizione e 9 Categorie senza gruppi): circa 403 token (489), il 14% del budget. Le Categorie senza gruppi non hanno una descrizione nell'elenco: la stima usa la lunghezza media delle descrizioni dei gruppi (deciso nella notte, reversibile). Tutte le 480 voci in un solo passaggio sarebbero circa 7.966 token (9.656): non entrano.

### Preordinamento

**Nessuna rosa ha bisogno del preordinamento** con l'elenco di oggi: la più grande, Agente, usa il 23% del budget. Il preordinamento con gli embedding dell'Indice (#112) o con le regole serve solo se una rosa supera circa 2.900 token, cioè circa 11.600 caratteri di `nome: descrizione`: con le righe attuali (66 caratteri di media) oltre 170 voci. I gruppi quindi non servono per i token, ma per tenere ogni rosa sotto le 40 voci, perché un modello piccolo sceglie peggio tra tante opzioni simili.

Non misurato: il tokenizer vero di Foundation Models e il costo dello schema (con `DynamicGenerationSchema` i nomi compaiono una seconda volta come scelte chiuse, circa 1–3 token per nome). Da misurare sul Mac con #381.
