# Copilot solo per le Domande, le Sessioni restano Claude

**Stato: Accettato, in parte sostituito da [ADR 0012](0012-copilot-cli-motore-di-sessione.md)** (2026-10-03): le Sessioni possono girare anche su Copilot. **In parte superato da [ADR 0014](0014-copilot-alla-pari-nelle-domande.md)** (2026-10-05): la Domanda Copilot ha gli strumenti come nel terminale, e chi ha solo Copilot usa tutto Bubo. Ricerca: [486 — Claude e Copilot: insieme o uno solo?](../research/486-copilot-insieme-o-uno.md), che segue [486 — Bubo con GitHub Copilot](../research/486-copilot.md).

Molti utenti hanno già GitHub Copilot, e il fondatore voleva capire se Bubo deve lavorare con Claude e Copilot insieme o con uno solo. GitHub Models è stato ritirato e `api.githubcopilot.com` non è documentato. L'unica strada consentita è il binario `copilot` dell'utente, pilotato dal Copilot SDK. Abbiamo valutato tre forme:

- (a) Copilot come fornitore delle Domande;
- (b) Copilot come secondo motore di Sessione;
- (c) un solo motore, scelto all'onboarding.

Abbiamo scelto:

- **Sessioni solo Claude.** Resta la regola della spec 10, "Le Sessioni restano sempre Claude". Quota, Cronologia CLI, Memoria di Progetto, Plugin, Agenti, Regole di permesso, Sandbox e copia delle conversazioni (ADR 0006) sono costruiti su Claude Code: circa 13.000 righe di Swift e tutto il bridge. Un secondo motore li dovrebbe rifare o lasciare vuoti.
- **Copilot come fornitore delle Domande**, dalla 1.1. Si usa con "Rifai con…", con "Usa sempre per «Tipo»" e come ripiego quando la Quota finisce. Mai per scelte automatiche, classificazione o lavoro in background, per rispettare le Acceptable Use Policies di GitHub.
- **Lo stesso schema di ADR 0003.** `copilot` lo installa l'utente e il login lo fa lui (`copilot login`). Bubo lo avvia tramite il Copilot SDK nel bridge Node, con una sessione senza tool, e non legge, copia o salva token. `GH_TOKEN` e `GITHUB_TOKEN` vengono tolti dall'ambiente del figlio.
- **Il costo è Spesa.** I crediti GitHub (1 = $0,01) si stimano dai token sul listino, e il Budget vale anche per Copilot. Non esiste una Quota di Copilot, perché nessuna API documentata dà i crediti residui.
- **La privacy resta quella della spec 10.** I contenuti del Progetto vanno a Copilot solo con il consenso per fornitore. Va aggiunto un avviso: sui piani Free, Pro e Pro+ l'addestramento è attivo per default.
- **1.0 senza Copilot.** In 1.0 si aggiorna solo la spec 10. Il codice arriva in 1.1.

Scartate: (b), perché raddoppia ogni spec e dà alla stessa finestra due agenti con poteri diversi, appoggiandosi a sandbox e ACP ancora in preview; (c), perché costa quanto (b) e divide Bubo in due prodotti, in competizione con la GitHub Copilot app, che è gratuita su tutti i piani. Non serve nemmeno come copertura verso Anthropic. La pagina Legal di Claude Code ammette il login dell'utente nel binario intatto, e il ripiego resta l'API key di ADR 0003.

Si riapre (b) se si verifica una di queste condizioni: Anthropic chiude il login dell'abbonamento nel binario intatto; ACP e il sandbox locale di Copilot diventano GA; c'è una domanda misurabile di Sessioni su Copilot.

## Scelte sulle domande aperte

1. **Utenti solo Copilot**: in 1.x Bubo richiede Claude (abbonamento o API key) per le Sessioni. Chi ha solo Copilot può fare Domande.
2. **Tinta**: quella del vendor del modello (GPT via Copilot = Tinta OpenAI). "via Copilot" va nella riga del motivo.
3. **Claude via Copilot**: Claude passa sempre da `claude`. Copilot serve per i modelli non Anthropic, salvo scelta esplicita dell'utente in "Rifai con…".
4. **Copilot Free**: escluso, come in Zed e opencode. Senza scelta del modello il router non serve. Bubo lo rileva e lo spiega.
5. **1.0**: Copilot entra nella 1.0, sia per le Domande sia per le Sessioni (ADR 0012).
6. **Partnership con GitHub**: per ora no. Si rivaluta se il processo `copilot` per le Domande si dimostra troppo lento (misura nel ticket del bridge).
