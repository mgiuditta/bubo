# Copilot CLI come secondo motore di Sessione

**Stato: Accettato** (2026-10-03, richiesta del fondatore). Sostituisce in parte [ADR 0011](0011-copilot-solo-per-le-domande.md). Ricerca: [486 — insieme o uno solo](../research/486-copilot-insieme-o-uno.md).

Il fondatore vuole usare Copilot CLI come oggi si usa Claude Code, e vuole che l'utente scelga il modello sia con Claude sia con Copilot. Quindi una **Sessione** può girare su uno di due motori: `claude`, che resta il predefinito, oppure `copilot`. L'utente sceglie motore e modello per ogni Sessione, e può fissare un predefinito per Progetto. Le Domande via Copilot di ADR 0011 restano valide.

- **Come.** Il Copilot SDK nel bridge Node lancia il `copilot` dell'utente: `createSession` sul worktree che crea Bubo, streaming, richieste di permesso con `onPermissionRequest`, poi `abort` e `resumeSession`. Login e binario sono dell'utente, come in ADR 0003. `GH_TOKEN` e `GITHUB_TOKEN` vengono tolti dall'ambiente del figlio. I messaggi verso Swift sono quelli neutri del bridge.
- **Cosa non c'è su Copilot.** Quota, Memoria di Progetto, Plugin, Agenti e Sandbox (ADR 0005) restano solo di Claude. In una Sessione Copilot queste parti dicono «Non disponibile con Copilot», non restano vuote in silenzio. Il costo è Spesa stimata in crediti.
- **Conversazioni.** Bubo le conserva anche per Copilot (ADR 0006), nello stesso formato neutro.
- **Quando.** Milestone 1.1. In 1.0 Copilot compare come «Arriverà presto».

Rischio accettato: ogni spec di Sessione riceve un ramo "e con Copilot?". Il Copilot SDK cambia spesso, quindi la versione si fissa e si aggiorna con CI (#226).
