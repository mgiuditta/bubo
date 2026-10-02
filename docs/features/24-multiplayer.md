# 24 — Multiplayer: Consegna e Risorse di squadra (v2)

Stato: **v2**. In v1 c'è solo la voce **In arrivo** in Impostazioni › Aggiornamenti ([#258](https://github.com/mgiuditta/bubo/issues/258)); il resto si costruisce dopo la v1.

Ticket: [#234](https://github.com/mgiuditta/bubo/issues/234) (prima ricerca), [#237](https://github.com/mgiuditta/bubo/issues/237) (decisioni v1), [#260](https://github.com/mgiuditta/bubo/issues/260)–[#265](https://github.com/mgiuditta/bubo/issues/265) (ricerche v2), [#267](https://github.com/mgiuditta/bubo/issues/267) (decisioni v2), [#268](https://github.com/mgiuditta/bubo/issues/268) (prototipo del foglio di Consegna e del Biglietto). Mappe: [#231](https://github.com/mgiuditta/bubo/issues/231) (v1), [#259](https://github.com/mgiuditta/bubo/issues/259) (v2).
Ricerche del 2026-09-30 con CLI `claude` **2.1.285** e Agent SDK TS **0.3.285**, una per branch:
[ripresa su un altro account](https://github.com/mgiuditta/bubo/blob/research/v2-ripresa-altro-account/docs/features/research/v2-24-ripresa-altro-account.md),
[canale di consegna](https://github.com/mgiuditta/bubo/blob/research/v2-canale-di-consegna/docs/features/research/v2-24-canale-di-consegna.md),
[risorse di squadra](https://github.com/mgiuditta/bubo/blob/research/v2-risorse-di-squadra/docs/features/research/v2-24-risorse-di-squadra.md),
[dal vivo](https://github.com/mgiuditta/bubo/blob/research/v2-dal-vivo/docs/features/research/v2-24-dal-vivo.md),
[concorrenti](https://github.com/mgiuditta/bubo/blob/research/v2-concorrenti/docs/features/research/v2-24-concorrenti.md),
[evoluzioni rimandate](https://github.com/mgiuditta/bubo/blob/research/v2-evoluzioni-rimandate/docs/features/research/v2-evoluzioni-rimandate.md).
Prima ricerca: [`24-multiplayer.md`](https://github.com/mgiuditta/bubo/blob/research/multiplayer/docs/features/research/24-multiplayer.md) sul branch `research/multiplayer`. Prototipo (da buttare): [`prototypes/consegna.html`](https://github.com/mgiuditta/bubo/blob/prototype/consegna/prototypes/consegna.html) sul branch `prototype/consegna`. Decisioni di architettura: [ADR 0008](../adr/0008-consegna-come-file-hpke-verso-una-macchina.md), [ADR 0009](../adr/0009-risorse-di-squadra-con-fiducia-per-voce.md).

> **Nota sulle ricerche.** Sono scritte prima delle decisioni. CKShare, file nel repo, age, rete locale e SharePlay non sono la strada della prima versione: la Consegna è un file `.bubo` cifrato con HPKE, mandato col Condividi di macOS. La condivisione dal vivo è fuori. La ripresa con un secondo account **vero** non è ancora provata (la ricerca l'ha simulata riscrivendo il JSONL): per questo il primo ticket è un cancello. Valgono la Mappa e la Specifica qui sotto.

In sintesi: il multiplayer di Bubo sono due cose. La **Consegna** passa una Sessione (conversazione ripulita, subagent e ramo) a un altro utente Bubo, che la riprende col **proprio** account: si consegna a una **Macchina**, con un file `.bubo` cifrato per la chiave che quella Macchina tiene nel Secure Enclave e autenticato dalla chiave di chi manda. Il file viaggia con AirDrop, Messaggi, Mail o qualunque altro mezzo dell'utente: niente server di Bubo né di terzi che leggano. Prima di uscire, un foglio unico mostra a chi va, cosa esce, cosa Bubo ha tolto e i possibili segreti da decidere; Condividi resta bloccato finché ne manca uno. Chi riceve la trova tra le **Bozze** e la avvia quando vuole. Le **Risorse di squadra** sono Automazioni e Regole di permesso di Bubo salvate in `.bubo/` nel repo: ognuna vale solo dopo che chi la usa l'ha accettata, e va riaccettata se il contenuto cambia. Tutti i concorrenti passano da un proprio server senza cifratura end-to-end, e il riferimento per la consegna (Cursor "Fork to Cursor") chiede il piano Teams; Bubo lo fa senza server, cifrato e con qualunque account.

## Ricerca

Riassunto; dettagli, prove e fonti complete nei file di ricerca.

### Ripresa su un altro account ([#260](https://github.com/mgiuditta/bubo/issues/260))

- **Si riprende con un'altra organizzazione**: nessun rifiuto; la CLI aggiunge una riga `credential_org` con l'organizzazione attuale e prosegue. Provato riscrivendo il JSONL con un solo account; un secondo account vero manca.
- **Il ragionamento si perde**: i blocchi `thinking` valgono solo nell'account che li ha prodotti "o in un account collegato"; con un altro account l'API li scarta in silenzio [1]. Il testo visibile resta.
- **Identità**: email e organizzazione stanno solo in `session_context` e `credential_org`; toglierle vuole la catena `parentUuid` ricucita.
- **Percorsi**: la ripresa funziona con tutti i percorsi riscritti, comprese la forma codificata (`-Users-…-proj`), `environment` e `persistedOutputPath`. `prompt_snapshot` (il prompt di sistema del mittente) si toglie.
- **Il modello legge `message.content`**, non `toolUseResult`: si ripuliscono entrambi, più i file in `tool-results/`.
- **Metadati fuori catena** (`pr-link`, `file-history-*`, `ai-title`, `last-prompt`, `cost-state`, `queue-operation`) si tolgono senza effetti; un transcript di prova è sceso da 225 KB a 48 KB.
- **Subagent**: serve la cartella `<sessionId>/subagents/` accanto al file, altrimenti "No transcript found for agent ID"; anche lì ci sono email, organizzazione e percorsi.
- **`sessionStore`** funziona solo con il `projectKey` della cwd di chi riprende [2].
- **Nessuno scanner trova tutto**: gitleaks manca token a bassa entropia e valori senza prefisso; detect-secrets li trova con 10 falsi positivi su 11 [3][4].

### Canale e cifratura ([#261](https://github.com/mgiuditta/bubo/issues/261))

- **HPKE di CryptoKit** (macOS 14+) ha la modalità auth, che autentica il mittente; age v1 no [5][6].
- **Secure Enclave**: una chiave P-256 apre HPKE con suite P-256; X25519 no [7].
- **`.bubo` come tipo esportato** conforme a `public.data` e `public.content` (serve ad AirDrop); Quick Look con `QLPreviewProvider` vede solo i metadati in chiaro [8][9].
- **CKShare** tra Apple ID diversi ha la ricevuta ma non la scadenza, ed è end-to-end solo con ADP per tutti [10][11]. **Git** non revoca: dopo il push i dati restano in cloni e cache [12].
- **AirDrop** e **LocalSend** non hanno terzi in mezzo; Magic Wormhole, Croc e Keybase sì. Signal verifica le chiavi con 60 cifre o un QR.

### Risorse di squadra ([#262](https://github.com/mgiuditta/bubo/issues/262))

- **La fiducia di Claude Code è sì/no per cartella**, senza hash: una `allow` aggiunta dopo vale subito, senza nuova richiesta [13].
- **Con l'SDK il dialogo non compare**: le `allow` del repo sono ignorate, ma hook, `env`, `apiKeyHelper` e `.mcp.json` girano lo stesso. Tocca già la v1: [#266](https://github.com/mgiuditta/bubo/issues/266).
- **Fiducia legata al contenuto**: direnv (sha256), Codex per gli hook, Gemini CLI, Cursor per le voci MCP, Nix per coppia chiave-valore [14][15].
- **Nessuno mette automazioni programmate nel repo**: Claude Desktop le tiene in `~/.claude/scheduled-tasks/` [16].
- Una chiave `"bubo"` in `.claude/settings.json` è ignorata senza avvisi, ma lo schema e le regole di quel file sono di Anthropic.

### Dal vivo ([#263](https://github.com/mgiuditta/bubo/issues/263))

- Lo stream pesa 15–25 kbit/s. SharePlay su macOS passa da FaceTime o Messaggi, messaggi ≤ 256 KB, e la capability con Developer ID è da provare [17]. Ogni P2P su internet usa un relay di qualcuno. Non entra (Decisione 9).

### Concorrenti ([#264](https://github.com/mgiuditta/bubo/issues/264))

| Prodotto | Cosa fa | Server | E2E | Account del turno | Limiti |
|---|---|---|---|---|---|
| **Cursor Fork to Cursor** [18] | copia in lettura, poi fork col proprio account | Cursor | no | di chi fa il fork | solo Teams (40 $/utente/mese) ed Enterprise, 50 al giorno, redazione "best-effort", niente subagent documentati |
| **Cursor team follow-up** [18] | il collega scrive nel thread | Cursor | no | del creatore | — |
| **Codex `.codex/rules`** [19] | regole nel repo | — | — | — | caricate se `.codex/` è fidata; fiducia per cartella, hash solo sugli hook |
| **Warp Agent Session Sharing** [20] | dal vivo, spettatori ed editor | Warp | no | del creatore | scade dopo ~1 settimana, nessuna redazione |
| **Amp** [21] | thread condivisi | Amp | no | "billed to the thread owner" | thread pubblici tolti |
| **Claude Code** [22] | sessioni cloud in lettura, `--teleport` stesso account | Anthropic | no | stesso account | nessuna consegna tra persone; Routine "not shared with teammates" |

Nessuno dei 13 prodotti letti condivide una sessione agentica senza un server del fornitore. Nessuno salva automazioni come file versionato nel repo.

## Il meglio da battere

Per la **Consegna** il riferimento è **Cursor "Fork to Cursor"**: l'unico "continua col tuo account". Passa però dal server di Cursor, senza cifratura end-to-end, solo con il piano Teams, con una redazione "best-effort" che l'utente non vede prima e 50 condivisioni al giorno. Per le **Risorse di squadra** il riferimento è **Codex** con `.codex/rules`: regole nel repo, caricate solo se la cartella è fidata. Ma la fiducia è per cartella: una regola aggiunta dopo vale senza chiedere. Nessuno versiona le automazioni nel repo. **Warp** è il riferimento per il dal vivo, che Bubo non fa.

## Rischi e casi limite

- **Secondo account vero mai provato**: la ripresa è dedotta da una simulazione. Se la CLI rifiuta, la Consegna non esiste. Per questo il primo ticket è un cancello.
- **HPKE auth con la chiave del mittente nel Secure Enclave** mai provata: l'API accetta una chiave privata generica, ma va verificato che quella del Secure Enclave funzioni come mittente e come destinatario.
- **Formato interno del JSONL**: cambia tra versioni della CLI. La pulizia deve fallire in modo esplicito su righe che non conosce, non lasciarle passare.
- **Segreti non trovati**: nessuno scanner è completo. L'anteprima obbligatoria è la garanzia, lo scanner un aiuto.
- **Mittente e destinatario con versioni di `claude` diverse**: il transcript di una versione nuova può non riprendersi su una vecchia.
- **Ramo che parte da commit assenti** dal destinatario (base non pushata).
- **Chiave del Secure Enclave persa** (Mac reinstallato, cambio di Mac): le Consegne in viaggio non si aprono più.
- **Man in the middle sullo scambio dei Biglietti**: il canale è qualunque; solo il codice confrontato a voce lo esclude.
- **File grandi**: Messaggi si ferma intorno ai 100 MB; un transcript con molti `tool-results` e un ramo con file binari possono superarli.
- **Risorse di squadra scritte da altri**: un'`allow` larga o un'Automazione in Modalità autonoma sono istruzioni di un'altra persona che girano col tuo account.
- **Hook e `.mcp.json` del repo** girano via SDK anche senza fiducia ([#266](https://github.com/mgiuditta/bubo/issues/266)): va chiuso in v1, prima delle Risorse di squadra.

## Mappa

Architettura comune in [INDEX.md](INDEX.md). Si appoggia su ponte agente con disclaim (ADR 0005), Sessioni in worktree (01), account (03), Richieste e Regole con `TrustGate` (05), copia a specchio (14, ADR 0006), Bozze (17), Automazioni e Regole dell'Automazione (19), Macchina e `MachineShell` (23), Impostazioni › Aggiornamenti (27).

### In v1 (deciso)

Fonte: [#237](https://github.com/mgiuditta/bubo/issues/237).

1. **Tutta la 24 in v2**: Consegna, Risorse di squadra, e il dal vivo (poi escluso, Decisione 9).
2. **Già in v1 senza lavoro nuovo**: ciò che il repo porta da sé e Bubo legge con la 04 (`CLAUDE.md`, `.claude/agents`, `skills`, `settings.json`).
3. **In arrivo** (glossario): le funzioni v2 compaiono in **Impostazioni › Aggiornamenti**, sotto la versione, come elenco statico nel bundle: nome e una riga, senza date, aggiornato a ogni release. Niente elenco remoto, niente segnaposto o bottoni grigi nell'HUD.
4. **Contenuto di In arrivo**: **Consegna di una Sessione** e **Risorse di squadra nel repo**. Resta così anche dopo la mappa v2 ([#267](https://github.com/mgiuditta/bubo/issues/267), punto 11); ogni voce esce dall'elenco nella release che la porta.
5. **Fuori anche in v2**: la co-guida simultanea della stessa Sessione, perché ogni turno consuma l'account di chi lo manda.

### Consegna (deciso)

Fonte: [#267](https://github.com/mgiuditta/bubo/issues/267), glossario: **Consegna**, **Biglietto**. Decisione di architettura: [ADR 0008](../adr/0008-consegna-come-file-hpke-verso-una-macchina.md).

1. **Canale**: un file `.bubo` cifrato, mandato col Condividi di macOS (AirDrop, Messaggi, Mail, Salva sul disco…). Un destinatario per volta. Niente CKShare né file nel repo nella prima versione; CKShare si può aggiungere dopo con lo stesso formato.
2. **Cifratura**: HPKE di CryptoKit in modalità auth, suite P-256. Una chiave per **Macchina**, nel **Secure Enclave**, non esportabile. Si consegna a una Macchina, non a una persona. Solo il Mac con Bubo riceve: una Macchina SSH non ha un Biglietto proprio, ma la Bozza può partire su qualunque Macchina del Progetto.
3. **Accoppiamento**: un **Biglietto** `.bubo` con la chiave pubblica, mandato con gli stessi canali, più un codice di verifica confrontato a voce. Lo scambio va **nei due sensi** (in HPKE auth chi riceve ha bisogno della chiave di chi manda). Il codice è uno per la coppia, calcolato dalle due chiavi, di **12 cifre in 3 gruppi da 4**. Avviso se la chiave cambia. Niente QR.
4. **Pulizia**: tolti email, organizzazione, `prompt_snapshot` e metadati fuori catena; percorsi riscritti; subagent inclusi e ripuliti; blocchi di ragionamento tolti. Lo scanner **segnala** i possibili segreti; l'**anteprima obbligatoria** di cosa esce è la vera garanzia.
5. **Ricevuta, revoca, scadenza**: nessuna. Il foglio lo dice: "Una volta consegnata, è sua".
6. **Ragionamento**: si perde con un altro account; il foglio lo dice.
7. **In chiaro nel `.bubo`**: tipo, versione, identificativo della chiave del destinatario e di quella del mittente, peso. Servono a Quick Look e a dare l'errore giusto prima di decifrare. Titolo e contenuto sono cifrati.
8. **Per chi riceve**: la Consegna diventa una **Bozza** con il chip `consegna`; Avvia la riprende col suo account e i suoi Livelli di permesso. Il ramo arriva come `consegna/‹mittente›/‹nome›`.

### Risorse di squadra (deciso)

Fonte: [#267](https://github.com/mgiuditta/bubo/issues/267), glossario: **Risorsa di squadra**. Decisione di architettura: [ADR 0009](../adr/0009-risorse-di-squadra-con-fiducia-per-voce.md).

1. **Formato**: cartella `.bubo/` nel repo, un file per **Automazione** più un file di **Regole di permesso**. Non sotto `.claude/settings.json`.
2. **Fiducia per voce**: ogni Automazione e ogni `allow` è legata allo sha256 del suo contenuto; se cambia, Bubo chiede di nuovo. `deny` e `ask` valgono subito, senza accettazione.
3. **Automazioni**: arrivano disattivate e girano con l'account di chi le attiva.
4. **Livelli 4–5**: una `allow` del repo che copre un'azione di livello 4–5 non si accetta (dai livelli 4–5 non nasce mai una Regola di permesso, 05).
5. **Prima di tutto la v1**: la fiducia del repo per hook, `env` e `.mcp.json` si decide nella 05 ([#266](https://github.com/mgiuditta/bubo/issues/266)). Le Risorse di squadra si aggiungono sopra, non la sostituiscono.

### Dal vivo (deciso)

Fuori da questa mappa ([#267](https://github.com/mgiuditta/bubo/issues/267), punto 9): SharePlay con Developer ID non è provato, il valore è basso e la Consegna copre il caso d'uso. Si riapre solo con un trasporto dell'utente provato e una richiesta vera.

### Interfaccia (deciso)

Fonte: [#268](https://github.com/mgiuditta/bubo/issues/268), vince la variante **B, Foglio unico**, con un pezzo della **C** (il segreto evidenziato dentro la conversazione). Il design visivo si rifà in costruzione.

**Foglio di Consegna (mittente)**

- **Ingresso**: "Consegna…" nel menu della Sessione e nella barra della Sessione. Apre un foglio attaccato alla finestra.
- **A chi** (colonna sinistra): Biglietti ricevuti come righe "Persona · Macchina" con il chip `verificato`. Una riga con la chiave cambiata ha il chip `chiave cambiata`, non si seleziona e rimanda a Impostazioni › Consegne. In fondo "+ Aggiungi con un Biglietto…". Sopra, la nota "Si consegna a una Macchina".
- **Avvisi** sotto A chi, sempre visibili:
  - "**Il ragionamento non passa.** Con un altro account gli N blocchi di ragionamento non si riprendono: ‹nome› vede messaggi, strumenti e ramo."
  - "**Una volta consegnata, è sua.** Non si revoca, non scade e non avvisa quando la apre."
- **Cosa esce** (colonna destra), in quest'ordine:
  - **Da decidere (N)**: ogni possibile segreto dello scanner con nome, estratto mascherato, dove sta (messaggio, strumento) e i pulsanti Togli · Lascia · Mostra nella conversazione. Nessuna scelta predefinita.
  - **Cosa esce**: Conversazione (N messaggi, strumenti e risultati), Subagent (N, ripuliti allo stesso modo), Ramo (commit, file, modifiche non salvate).
  - **Tolto da Bubo**: email dell'account, organizzazione, percorsi (→ `‹progetto›`), `prompt_snapshot` e metadati fuori catena.
  - **Conversazione ripulita**: anteprima scorrevole, con segreti e parti tolte evidenziati. "Mostra nella conversazione" la scorre fino al punto e lo evidenzia.
- **Piede**: lo stato ("Scegli a chi", "Decidi i possibili segreti", "Pronta: 2,4 MB"), poi Annulla e **Condividi…** (primario), disattivato finché manca il destinatario o un segreto non è deciso. Apre il Condividi di macOS.
- **Dopo**: avviso nella Sessione "Consegnata con ‹canale› a ‹nome›. La Sessione resta tua; da qui in poi le due copie vanno ognuna per conto suo." Nessuna ricevuta.

**Destinatario**

- **Quick Look** del `.bubo`: tipo "Consegna Bubo, cifrata"; Da (nome e Macchina se c'è un Biglietto per quella chiave, altrimenti "mittente sconosciuto" in rosso); Per ("questa Macchina" oppure il nome dell'altra, in rosso); peso; nota "si legge in Bubo".
- **Apertura** (doppio clic): foglio "Consegna ricevuta" con titolo e chip `verificata`, "da ‹nome› · ‹Macchina›". **Dove**: il Progetto con lo stesso remote; se non c'è, "Scegli…" · "Clona", e Metti tra le Bozze resta disattivato. **Cosa arriva**: messaggi, subagent, "il ragionamento di ‹nome› non c'è", il ramo `consegna/‹mittente›/‹nome›`. Nota "Diventa una Bozza. Quando la avvii, riprende col tuo account e i tuoi Livelli di permesso." Pulsanti: Scarta · **Metti tra le Bozze**.
- **Bozza** con il chip `consegna` tra le Bozze del Progetto. Avvia crea la Sessione che riprende la conversazione, sulla Macchina del Progetto.

**Errori** (foglio "Non si apre", un solo testo per caso)

- **Altra Macchina**: "Questa Consegna è per un'altra Macchina. È cifrata per «‹Macchina›». Aprila lì, oppure chiedi a ‹nome› di rifarla per «‹questa›»."
- **File modificato o danneggiato** (l'autenticazione non passa): "Il file è stato modificato o è danneggiato. Bubo non lo apre. Chiedi a ‹nome› di rimandarlo."
- **Mittente sconosciuto**: "Non conosci chi l'ha mandata. Bubo apre solo Consegne di chi ha un Biglietto verificato. Scambiatevi i Biglietti, poi riaprila." Pulsante: Impostazioni › Consegne.

**Biglietto** (Impostazioni › Consegne)

- **Il mio Biglietto**: la Macchina, "chiave nel Secure Enclave di questo Mac, non si esporta", Condividi….
- **Biglietti ricevuti**: righe Persona · Macchina con codice, stato e Rimuovi; con la chiave cambiata anche Riverifica.
- **Import** (doppio clic sul Biglietto): "Biglietto di ‹nome› per ‹Macchina›", il codice in grande, "Leggetevi il codice a voce o in chiamata. Deve essere uguale sul Mac di ‹nome›." Pulsanti: Non coincide (distruttivo) · **Coincide**. Non coincide scarta il Biglietto; Coincide lo salva come verificato e propone "Manda il mio Biglietto…".
- **Chiave cambiata**: stesso foglio con l'avviso in cima: "Può essere un Mac reinstallato, o qualcuno che si spaccia per ‹nome›. Finché non confrontate il codice, non puoi consegnare lì."

**Risorse di squadra** (non prototipate; stessa lingua visiva del foglio di Consegna)

- **Avviso nel Progetto** quando `.bubo/` ha voci nuove o cambiate: "Nel repo ci sono N Risorse di squadra da guardare", con **Guarda…**.
- **Foglio Risorse di squadra**: una riga per voce (Automazione o `allow`), con autore dell'ultimo commit che l'ha toccata, contenuto completo (prompt, ripetizione, modello, agente, Modalità autonoma, regole dell'Automazione; oppure la regola con il suo Livello di rischio) e, se è cambiata, il diff dalla versione accettata. Pulsanti per riga: Accetta · Ignora. `deny` e `ask` compaiono in una sezione "Già attive" senza pulsanti.
- **Condividi con la squadra…** su un'Automazione (finestra Automazioni) e su una Regola del Progetto (Impostazioni del Progetto): Bubo scrive il file in `.bubo/` e lo mostra nel diff della Sessione o del checkout; il commit lo fa l'utente.

**Accessibilità**: le righe "segreto?" e le righe delle Risorse di squadra sono gruppi VoiceOver con azioni personalizzate (Togli, Lascia, Mostra; Accetta, Ignora); il contatore "Da decidere" si annuncia quando cambia. Condividi disattivato ha un suggerimento che dice cosa manca. Il codice di verifica si legge a gruppi ("4821, 0937, 5562"). I chip non usano solo il colore.

### Cancello (deciso)

Primo ticket di costruzione, con una persona: **due Mac, due account Claude di organizzazioni diverse**.

- **Ripresa**: una Sessione vera con subagent, ripulita con le regole di questa spec, ripresa sul secondo account. Deve rispondere giusto a 5 domande su fatti della conversazione e dei subagent; si misurano token e costo del primo turno senza ragionamento.
- **HPKE auth nel Secure Enclave**: chiave del mittente e del destinatario entrambe nel Secure Enclave, suite P-256, un file di 50 MB cifrato su un Mac e aperto sull'altro; file alterato di un byte → rifiuto.
- **Esiti**:
  - Ripresa rifiutata o contesto perso → la Consegna si ferma e si riapre la questione con un nuovo ADR.
  - Secure Enclave non usabile come mittente HPKE → la chiave va nel Portachiavi del Mac (P-256, `ThisDeviceOnly`, non sincronizzata), con un emendamento all'ADR 0008.

### Dettagli di costruzione

Scelti scrivendo la spec, non nelle issue. Si possono cambiare senza toccare le decisioni sopra.

**Chiave della Macchina e Biglietto**

- `SecureEnclave.P256.KeyAgreement.PrivateKey` creata alla prima apertura di Impostazioni › Consegne o del foglio di Consegna, con controllo d'accesso `.privateKeyUsage`. La sua `dataRepresentation` (un riferimento opaco, inutile fuori da questo Secure Enclave) sta nel Portachiavi con `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- **Identificativo della chiave**: i primi 8 byte di SHA-256 della chiave pubblica in forma x9.63, in esadecimale.
- **Biglietto**: `.bubo` di tipo `biglietto`, non cifrato: versione, nome della persona (dal nome dell'account macOS, modificabile), nome della Macchina (nome del computer), chiave pubblica.
- **Codice di verifica**: SHA-256 di `"bubo-biglietto-v1" ‖ min(A, B) ‖ max(A, B)` sulle due chiavi pubbliche, primi 5 byte come intero modulo 10¹², in 3 gruppi da 4. Uguale sui due Mac.
- **Chiave cambiata**: un Biglietto con la stessa coppia Persona · Macchina di uno salvato ma un'altra chiave. Il vecchio resta, marcato `chiave cambiata`, finché Riverifica non confronta il nuovo codice.
- **Biglietti ricevuti** in `Deliveries/TicketStore`, accanto agli altri store di Bubo. Sono chiavi pubbliche: niente Portachiavi.

**Formato `.bubo`**

- **Intestazione in chiaro**: magia `BUBO`, tipo (`consegna` o `biglietto`), versione del formato, identificativo della chiave del destinatario e del mittente, peso del contenuto. Per una Consegna tutta l'intestazione entra come dato associato di ogni pezzo cifrato: cambiarla fa fallire l'apertura.
- **Cifratura**: `HPKE.Sender(recipientKey:ciphersuite: .P256_SHA256_AES_GCM_256, info: "bubo-consegna-v1", authenticatedBy:)` con la chiave del mittente; chiave incapsulata dopo l'intestazione. Il contenuto si cifra a pezzi da 1 MiB con lo stesso contesto (il nonce cresce da solo); il dato associato di ogni pezzo aggiunge indice e un segno di ultimo pezzo, così un file troncato non si apre.
- **Contenuto** (prima della cifratura, in un Apple Archive con compressione LZFSE):
  - `manifest.json`: titolo, nome e Macchina del mittente, remote del Progetto, commit di base, nome del ramo, conteggi (messaggi, subagent, blocchi di ragionamento tolti, segreti tolti), versione di `claude` che ha scritto il transcript;
  - `transcript.jsonl` ripulito;
  - `subagents/*.jsonl` e `tool-results/*` ripuliti;
  - `ramo.bundle`: `git bundle` dei commit del ramo dalla base (il merge-base con il ramo principale del remote), più un commit "Modifiche non salvate di ‹nome›" costruito con un indice temporaneo (`GIT_INDEX_FILE`, `git add -A`, `write-tree`, `commit-tree`) senza toccare il worktree del mittente. I file ignorati da git non escono.
- **Tipo** `it.bubo.consegna` esportato, conforme a `public.data` e `public.content`, estensione `.bubo`; Quick Look con un'estensione `QLPreviewProvider` che legge solo l'intestazione e il `TicketStore`.

**Pulizia** (`Deliveries/TranscriptCleaner`, codice puro)

- Riga per riga, con una tabella dei tipi conosciuti a due livelli: il `type` della riga e, per `attachment`, l'`attachment.type`. Ogni valore ha una regola (tieni e riscrivi, togli). **Un valore sconosciuto a uno dei due livelli blocca la Consegna** con "Questa Sessione ha righe che Bubo non sa ancora ripulire", invece di passare.
- Tolte: le righe `pr-link`, `file-history-*`, `ai-title`, `custom-title`, `last-prompt`, `cost-state`, `queue-operation`, `atis-latch`, `progress`; gli `attachment` `session_context`, `credential_org`, `environment`, `model`, `remote_session_change`, `prompt_snapshot`, `prompt_render_point`, `deferred_tools_record`; i blocchi `thinking` e `redacted_thinking` (un messaggio fatto solo di ragionamento sparisce). Catena `parentUuid` ricucita (anche `logicalParentUuid` e `leafUuid`).
- **Percorsi**: il worktree del mittente, la home e le loro forme codificate diventano un segnaposto `‹progetto›` in ogni stringa di ogni riga (`cwd`, `persistedOutputPath`, `message.content`, `toolUseResult`, `wireIngestContext`, righe `system`, `instructions`…), nei `agent-<id>.meta.json` dei subagent e nei `tool-results/`. Email e organizzazione dell'account diventano `‹tolto›` ovunque compaiano. All'Avvia il segnaposto diventa il worktree del destinatario.
- **Segreti decisi "Togli"**: il valore diventa `‹tolto›` in `message.content`, `toolUseResult` e nei file `tool-results/`, ovunque compaia (anche nei subagent).
- **`sessionId`** nuovo per il destinatario, riscritto in tutte le righe e nei subagent.

**Scanner** (`Deliveries/SecretScanner`, codice puro)

- Tre fonti: regole con prefisso noto (portate dalle regole di gitleaks con parole chiave, entropia e allowlist, licenza MIT, versione annotata in `Resources/RegoleGitleaks.json` e rifatte con `scripts/update-gitleaks-rules.sh`); valori ad alta entropia accanto a parole chiave (`token`, `secret`, `password`, `key`, `Authorization`); righe `NOME=valore` di file `.env` letti durante la Sessione.
- Gira su conversazione, subagent, `tool-results` e sul diff delle modifiche non salvate. Ogni risultato ha estratto mascherato (primi 4 caratteri e lunghezza) e posizione.
- Un risultato che compare in più punti è **una** riga "Da decidere".

**Mittente**

- `Deliveries/DeliveryBuilder`: legge il transcript dalla copia a specchio (14), pulisce, scansiona, prepara l'anteprima; al Condividi costruisce il bundle del ramo, archivia, cifra e scrive il `.bubo` in una cartella temporanea, poi `NSSharingServicePicker`. Il file temporaneo si cancella alla chiusura del Condividi.
- **Sessione su una Macchina remota** (23): transcript dalla copia a specchio, bundle del ramo via `MachineShell`.
- **Peso**: sopra 100 MB il piede dice "Grande: Messaggi potrebbe non mandarla. Usa AirDrop o Salva sul disco".

**Destinatario**

- **Apertura**: intestazione → identificativo del destinatario ≠ il mio → "Altra Macchina"; mittente sconosciuto o non verificato → "Mittente sconosciuto"; `HPKE.Recipient(… authenticatedBy:)` o un pezzo che non si apre → "File modificato o danneggiato". Tutto prima di mostrare qualunque contenuto.
- **Metti tra le Bozze**: `git fetch <ramo.bundle> <ramo>:refs/heads/consegna/<mittente>/<nome>` nel checkout principale; se mancano commit di base, prima `git fetch` dal remote e poi di nuovo. Contenuto decifrato in `Application Support/Bubo/Consegne/<id>/` con protezione dei file; il `.bubo` originale non si tocca. Bozza in `Sessions/DraftStore` con fonte `consegna`.
- **Avvia**: worktree sul ramo `consegna/…` (01); segnaposto → worktree; transcript e subagent scritti per il `projectKey` del worktree del destinatario (via `sessionStore` e nella cartella di `claude` della Macchina, con `MachineShell` se remota); `resume` col nuovo `sessionId`. Poi la cartella in `Consegne/<id>/` si cancella: la conversazione vive nella copia a specchio come ogni altra.
- **Scarta**: cancella Bozza, contenuto decifrato e ramo `consegna/…` se non ha worktree.

**Risorse di squadra**

- **`.bubo/regole.json`**: `{"version": 1, "allow": [...], "deny": [...], "ask": [...]}`, con la stessa sintassi delle regole di Claude Code. Ogni stringa di `allow` è una voce.
- **`.bubo/automazioni/<slug>.md`**: frontmatter YAML con `nome`, `ripetizione` (gli stessi valori della 19, niente cron), `modello`, `agente`, `modalita_autonoma`, `regole` (le `allow` dell'Automazione); corpo = richiesta. Il file intero è una voce.
- **Hash**: sha256 del testo della voce normalizzato (UTF-8, fine riga `\n`, spazi finali tolti). Accettazioni in `Team/TrustLedger`, per Progetto: voce → hash accettato, chi, quando.
- **Dove si legge**: `.bubo/` del checkout principale, con FSEvents; vale per tutte le Sessioni del Progetto, anche nei worktree.
- **Come valgono**: `deny` e `ask` passano alla `query()` di ogni Sessione del Progetto come regole di sessione; le `allow` accettate come regole `allow` di sessione (destinazione `cliArg`), come le Regole dell'Automazione della 19. Le `allow` non accettate non esistono per Bubo.
- **Automazione accettata**: diventa un'Automazione della 19, in pausa, con il segno "dal repo"; l'utente la attiva. Se il file cambia, torna da riaccettare e le Esecuzioni sono **Saltate** con motivo "Cambiata nel repo, da riaccettare". Se il file sparisce, l'Automazione va in pausa con la stessa nota.
- **Livello 4–5**: `Permissions/RiskClassifier` valuta ogni `allow` del repo; se copre un'azione di livello 4–5 la riga dice "Non si accetta: livello ‹N›" senza pulsante.

### Moduli

Architettura comune in [INDEX.md](INDEX.md). Moduli nuovi:

- `DeliveryKit` (pacchetto, codice puro dove possibile): intestazione, cifratura a pezzi, codice di verifica, identificativi.
- `Deliveries/MachineKey`: chiave nel Secure Enclave e Portachiavi.
- `Deliveries/TicketStore`, `Deliveries/TicketImporter`.
- `Deliveries/TranscriptCleaner`, `Deliveries/SecretScanner`, `Deliveries/BranchBundler`.
- `Deliveries/DeliveryBuilder` (mittente), `Deliveries/DeliveryOpener` (destinatario).
- `BuboQuickLook` (estensione `QLPreviewProvider`).
- `HUD/DeliverySheet`, `HUD/DeliveryReceivedSheet`, `HUD/DeliveryErrorSheet`, `Settings/DeliveriesPane`, `HUD/TicketImportSheet`.
- `Team/TeamResourceReader` (lettura di `.bubo/`, FSEvents), `Team/TrustLedger`, `Team/TeamResourcesSheet`, `Team/TeamResourceWriter` (Condividi con la squadra).
- Estensioni: `Sessions/DraftStore` (fonte `consegna`, avvio con `resume`), `Sessions/WorktreeManager` (worktree su un ramo esistente), `History/ConversationStore` (scrittura per un `projectKey` nuovo), `Permissions/TrustGate` e `RuleStore` (regole di squadra), `Automations/` (Automazione "dal repo", Saltata "Cambiata nel repo"), `Settings/UpdatesPane` (voci In arrivo tolte quando escono).

### Flusso

1. **Scambio dei Biglietti**: Impostazioni › Consegne → Condividi… il mio Biglietto → l'altro lo apre → codice in grande → confronto a voce → Coincide → "Manda il mio Biglietto…" → stesso percorso al contrario.
2. **Consegna**: Sessione → Consegna… → scelta della Macchina → decisione di ogni possibile segreto → Condividi… → Condividi di macOS → avviso "Consegnata".
3. **Ricezione**: `.bubo` → Quick Look (facoltativo) → doppio clic → verifica di intestazione, mittente e autenticazione → foglio "Consegna ricevuta" → Dove → Metti tra le Bozze → ramo importato → Bozza con chip `consegna`.
4. **Avvio**: Avvia → worktree sul ramo → transcript ripristinato → `resume` col proprio account → Sessione in Aperta · Lavora o Attende te.
5. **Risorse di squadra**: `git pull` porta `.bubo/` nuovo → avviso nel Progetto → Guarda… → Accetta per voce → regole attive nelle Sessioni; Automazione in pausa → Attiva.

### Casi limite

- **Consegna a sé stessi su un altro Mac**: funziona come con chiunque (serve il Biglietto dell'altro Mac); il ragionamento passa solo se l'account è lo stesso, ma Bubo lo toglie comunque.
- **Stessa Consegna aperta due volte**: la seconda apre la Bozza già creata (chiave: identificativo della Consegna nel manifest).
- **Progetto senza remote o non git**: la Consegna porta solo la conversazione; il foglio lo dice ("Niente ramo: il Progetto non è un repo") e il destinatario sceglie una cartella.
- **Ramo con commit di base non raggiungibili** nemmeno dopo `git fetch`: foglio "Non si apre" con "Il ramo parte da commit che non hai. Chiedi a ‹nome› di pushare ‹branch di base›."
- **Nome del ramo già usato**: suffisso `-2`, `-3`.
- **`claude` del destinatario più vecchio** di quello del mittente (dal manifest): avviso nella Bozza "Aggiorna claude prima di avviarla"; Avvia resta possibile.
- **Sessione in Lavora**: Consegna… è disattivata finché il turno non finisce.
- **Mac reinstallato**: nuova chiave, nuovo Biglietto; chi lo aveva vede `chiave cambiata`. Le Consegne vecchie non si aprono (errore "Altra Macchina").
- **Più Mac della stessa persona**: un Biglietto per Mac; nel foglio righe separate "Persona · Macchina".
- **Biglietto aperto su un Mac che ne ha già uno uguale**: nessun doppione, riga già verificata.
- **Risorsa di squadra su un ramo diverso**: vale solo ciò che sta nel checkout principale; i cambi in un worktree di Sessione non contano finché non arrivano lì.
- **`regole.json` non valido**: nessuna `allow` di squadra attiva; `deny` e `ask` non leggibili → avviso rosso nel Progetto "Le regole di squadra non si leggono", per non far credere che un `deny` valga.
- **Automazione dal repo con un agente che il destinatario non ha**: si accetta, ma l'Esecuzione è Saltata "Agente ‹nome› mancante".
- **Due Automazioni con lo stesso nome** (una locale, una dal repo): quella dal repo porta il segno "dal repo" e non sostituisce l'altra.

### Test

- **Cancello**: vedi sopra; esito nel ticket.
- `DeliveryKit`: cifratura e apertura; intestazione cambiata, pezzo scambiato, pezzo tolto, ultimo pezzo tolto → rifiuto; mittente con un'altra chiave → rifiuto; codice di verifica uguale con le chiavi in ordine inverso; vettori di prova fissi.
- `TranscriptCleaner` su un corpus di transcript veri (con subagent, MCP, compattazione, `tool-results`): nessuna email, organizzazione, percorso del mittente, `prompt_snapshot` o blocco di ragionamento nel risultato (ricerca testuale → 0); catena `parentUuid` valida; tipo di riga sconosciuto → errore.
- **Ripresa** del transcript ripulito sullo stesso account in CI (senza ragionamento): 5 domande sul contenuto con risposta giusta.
- `SecretScanner` su un corpus con segreti piantati (con e senza prefisso, a bassa entropia, in `.env`): quota trovata e falsi positivi nel report; nessun valore in chiaro nei log.
- `BranchBundler`: commit, modifiche non salvate, file nuovi non tracciati, file ignorati (non escono); fetch dal bundle in un clone con e senza la base.
- **Foglio**: Condividi disattivato senza destinatario e con un segreto non deciso; riga `chiave cambiata` non selezionabile.
- **End-to-end** tra due Mac con due account (dopo il cancello, a mano): Consegna via AirDrop, apertura, Bozza, Avvia, risposta giusta su un fatto della conversazione.
- **Risorse di squadra**: `allow` accettata → vale; file cambiato di un carattere → non vale più fino a nuova accettazione; `deny` nuovo → vale subito; Automazione dal repo → in pausa, gira con l'account di chi la attiva; file cambiato → Esecuzione Saltata; `allow` di livello 5 → nessun pulsante.
- Accessibilità: audit SwiftUI e AppKit del foglio di Consegna, dei fogli del destinatario, di Impostazioni › Consegne e del foglio Risorse di squadra.

### Ordine di costruzione

1. **Cancello: ripresa con un secondo account vero e HPKE auth nel Secure Enclave**, con una persona, due Mac e due account. Non tocca il codice dell'app: può partire subito. Esito nel ticket. Ticket: [#274](https://github.com/mgiuditta/bubo/issues/274).
2. **Chiave della Macchina, Biglietto e tipo `.bubo`**: `DeliveryKit`, `MachineKey`, `TicketStore`, Impostazioni › Consegne, import con codice, chiave cambiata, tipo esportato e Quick Look. Dipende da 1 e dagli entitlement della 27 ([#219](https://github.com/mgiuditta/bubo/issues/219)). Ticket: [#275](https://github.com/mgiuditta/bubo/issues/275).
3. **Pulizia del transcript e scanner dei segreti**: `TranscriptCleaner`, `SecretScanner`, corpus di prova, ripresa in CI. Dipende da 1. Ticket: [#276](https://github.com/mgiuditta/bubo/issues/276).
4. **Foglio di Consegna**: `BranchBundler`, `DeliveryBuilder`, foglio B con il pezzo di C, Condividi di macOS, avviso nella Sessione. Dipende da 2, 3, 01 e 14. Ticket: [#277](https://github.com/mgiuditta/bubo/issues/277).
5. **Apertura, Bozza e ripresa**: `DeliveryOpener`, i tre errori, foglio "Consegna ricevuta", ramo `consegna/…`, Bozza con chip, Avvia con `resume` (anche su una Macchina remota); "Consegna di una Sessione" esce da In arrivo. Dipende da 4 e da 17. Ticket: [#278](https://github.com/mgiuditta/bubo/issues/278).
6. **Regole di permesso di squadra**: `.bubo/regole.json`, `TeamResourceReader`, `TrustLedger`, foglio Risorse di squadra per le regole, Condividi con la squadra. Dipende da 05 e da [#266](https://github.com/mgiuditta/bubo/issues/266); indipendente dalla Consegna. Ticket: [#279](https://github.com/mgiuditta/bubo/issues/279).
7. **Automazioni di squadra**: `.bubo/automazioni/`, Automazione "dal repo" in pausa, Saltata "Cambiata nel repo", Condividi con la squadra; "Risorse di squadra nel repo" esce da In arrivo. Dipende da 6 e da 19. Ticket: [#280](https://github.com/mgiuditta/bubo/issues/280).

## Specifica "migliore di"

Migliori concorrenti: **Cursor "Fork to Cursor"** per la Consegna (continua col proprio account, ma server Cursor, niente E2E, solo Teams, redazione non visibile, 50 al giorno), **Codex `.codex/rules`** per le Risorse di squadra (regole nel repo, ma fiducia per cartella). Warp non si confronta: il dal vivo è fuori.
Bubo li supera così:

1. **Zero server**: **0** server di Bubo o di terzi che ricevono la Consegna in chiaro; viaggia solo sui canali dell'utente.
2. **E2E sempre**: **100%** del contenuto del `.bubo` cifrato, intestazione esclusa (tipo, versione, identificativi delle chiavi, peso); **0** aperture riuscite con un file alterato di un byte.
3. **Qualunque account**: funziona tra due account qualsiasi (Pro, Max, Team, Enterprise, API key), **0** piani richiesti in più.
4. **Anteprima obbligatoria**: **100%** delle Consegne passano dal foglio; **0** possibili segreti usciti senza una decisione esplicita.
5. **Subagent inclusi**: **100%** dei subagent della Sessione ripresi dal destinatario (contro "No transcript found for agent ID").
6. **Nessun limite**: **0** limiti giornalieri di Consegne.
7. **Pulizia verificabile**: **0** email, organizzazioni, percorsi del mittente o blocchi di ragionamento nel contenuto consegnato (ricerca testuale sul corpus di prova).
8. **Veloce da ricevere**: dal doppio clic alla Bozza **≤ 10 s** per una Consegna di 5 MB con la base già presente.
9. **Fiducia per voce**: **0** Automazioni o `allow` di squadra cambiate che valgono senza una nuova accettazione (contro Codex e Claude Code, dove una regola aggiunta dopo la fiducia vale subito).
10. **Automazioni versionate**: **1** file leggibile per Automazione in `.bubo/automazioni/`, revisionabile in una PR; nessun concorrente le mette nel repo.

### Dove perdiamo

- **Niente ragionamento**: con un altro account i blocchi di ragionamento non si riprendono (Cursor li ha sul suo server, dove il turno resta nello stesso sistema).
- **Niente revoca, ricevuta né scadenza**: un link di Cursor o una CKShare si possono togliere o seguire; un file consegnato no.
- **Serve scambiarsi i Biglietti prima**, con un codice letto a voce; un link di Cursor si manda subito.
- **Un destinatario per volta**, e a una Macchina, non a una persona.
- **Riceve solo un Mac con Bubo**: niente web, niente Linux, niente iPhone.
- **Niente dal vivo**: Warp mostra la sessione mentre gira.
- **Scanner non completo**: la garanzia è l'occhio di chi consegna, non lo scanner.
- **Formato interno di `claude`**: una nuova versione con righe sconosciute blocca la Consegna finché Bubo non si aggiorna.

## Fonti

Le fonti complete sono nei file di ricerca. Principali:

1. Claude, *Preserved thinking* — https://platform.claude.com/docs/en/build-with-claude/preserved-thinking
2. Agent SDK, *Session storage* — https://code.claude.com/docs/en/agent-sdk/session-storage
3. gitleaks — https://github.com/gitleaks/gitleaks
4. detect-secrets — https://github.com/Yelp/detect-secrets
5. Apple, CryptoKit `HPKE` — https://developer.apple.com/documentation/cryptokit/hpke
6. age v1 — https://age-encryption.org/v1
7. Apple, `SecureEnclave.P256.KeyAgreement.PrivateKey` — https://developer.apple.com/documentation/cryptokit/secureenclave/p256/keyagreement/privatekey
8. Apple, *Defining file and data types for your app* — https://developer.apple.com/documentation/uniformtypeidentifiers/defining-file-and-data-types-for-your-app
9. Apple, `QLPreviewProvider` — https://developer.apple.com/documentation/quicklookui/qlpreviewprovider
10. Apple, `CKShare` — https://developer.apple.com/documentation/cloudkit/ckshare
11. Apple, Protezione avanzata dei dati — https://support.apple.com/en-us/102651
12. GitHub, *Removing sensitive data from a repository* — https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository
13. Claude Code, *Security* e *Settings* — https://code.claude.com/docs/en/security , https://code.claude.com/docs/en/settings
14. direnv — https://direnv.net/man/direnv.1.html
15. OpenAI Codex, *Hooks* — https://learn.chatgpt.com/docs/hooks
16. Claude Code, *Desktop scheduled tasks* — https://code.claude.com/docs/en/desktop-scheduled-tasks
17. Apple, GroupActivities — https://developer.apple.com/documentation/groupactivities
18. Cursor, *Shared transcripts* — https://cursor.com/help/ai-features/shared-transcripts
19. OpenAI Codex, *Config reference* — https://learn.chatgpt.com/docs/config-file/config-reference
20. Warp, *Session sharing* — https://docs.warp.dev/agent-platform/local-agents/session-sharing/
21. Amp, *Threads* — https://ampcode.com/docs/threads
22. Claude Code, *Use Claude Code in the cloud* e *Routines* — https://code.claude.com/docs/en/claude-code-on-the-web , https://code.claude.com/docs/en/routines
