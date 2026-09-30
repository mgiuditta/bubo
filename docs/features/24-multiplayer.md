# 24 — Multiplayer (v2)

Stato: **v2**. In v1 non c'è lavoro nuovo per questa feature: compare solo come **In arrivo** in Impostazioni › Aggiornamenti.

Ticket: [#234](https://github.com/mgiuditta/bubo/issues/234) (ricerca), [#237](https://github.com/mgiuditta/bubo/issues/237) (decisioni). Mappa: [#231](https://github.com/mgiuditta/bubo/issues/231).
Ricerca del 2026-09-30 con CLI `claude` **2.1.285**. Ricerca completa: [`24-multiplayer.md`](https://github.com/mgiuditta/bubo/blob/research/multiplayer/docs/features/research/24-multiplayer.md) sul branch `research/multiplayer`.

In sintesi: il multiplayer di Bubo è la **consegna** di una Sessione (conversazione più ramo) a un altro utente Bubo che la riprende col proprio account, più le **risorse di squadra** di Bubo nel repo (Automazioni, Regole di permesso). Tecnicamente si può: un JSONL copiato si riprende altrove. Ma non c'è una consegna ufficiale tra account, il transcript porta email, organizzazione e ogni output in chiaro, e CloudKit condiviso è end-to-end solo se tutti hanno ADP. Tanto rischio, poco valore per l'utente singolo della v1: tutta la feature va in v2.

## Ricerca (sintesi)

- **Il transcript viaggia**: un JSONL copiato si riprende con tutto il contesto, per ID (sotto `~/.claude/projects/`) o per percorso assoluto (`claude --resume /percorso/file.jsonl`). Verificato. Se lo stesso ID compare in due progetti, `--resume <id>` risponde not-found.
- **Nessuna consegna ufficiale tra account**: solo il link in lettura alle sessioni cloud (Team o Public, senza aggiornamento dal vivo); `--teleport` vuole lo stesso account. La ripresa su un altro account non è documentata né provata.
- **Cosa si perde col solo JSONL**: file-history, transcript dei subagent, Memoria di Progetto (machine-local), concessioni di sessione, flag di lancio. Il codice va consegnato come ramo; il JSONL porta la riga `pr-link`.
- **Il JSONL non è neutro**: email, `organizationUuid`, percorsi assoluti, output degli strumenti in chiaro. Formato interno, cambia tra versioni. ~1 MB in media, fino a ~5 MB.
- **`sessionStore`**: chiave derivata dalla cwd; niente file-history; chi riprende usa le proprie credenziali.
- **Risorse di squadra**: `CLAUDE.md`, `.claude/settings.json`, `agents/`, `skills/`, `rules/`, `agent-memory/`, `.mcp.json` vanno nel repo. Le `allow`, i marketplace e gran parte di `env` valgono solo dopo la fiducia del collega; `deny` e `ask` subito. Le Regole del Progetto di Bubo stanno in `settings.local.json` (fuori da git); Automazioni e Regole "in questa Automazione" stanno in Bubo.
- **CKShare**: fino a 100 partecipanti, spazio del proprietario, record ≤ 1 MB (transcript come `CKAsset`); end-to-end solo con ADP per tutti, mai con "chiunque abbia il link".
- **SharePlay**: end-to-end, ma solo durante una chiamata FaceTime; allegati ≤ 100 MB che spariscono quando tutti escono.
- **Concorrenti**: Cursor, Conductor, Devin e Claude Code cloud consegnano dal proprio server; il turno del collega usa le credenziali del creatore. Solo **Cursor "Fork to Cursor"** fa copia più continuazione col proprio account. Zed e Tuple condividono editor o schermo, non la conversazione.

## Decisioni

Fonte: [#237](https://github.com/mgiuditta/bubo/issues/237).

1. **Tutta la 24 in v2**: consegna di una Sessione, risorse di squadra di Bubo nel repo (Automazioni, Regole di permesso), condivisione dal vivo.
2. **Già in v1 senza lavoro nuovo**: ciò che il repo porta da sé e Bubo legge con la 04 (`CLAUDE.md`, `.claude/agents`, `skills`, `settings.json`). Automazioni e Regole in repo restano in v2, perché aprono la stessa questione di fiducia della consegna (regole `allow` scritte da altri).
3. **In arrivo** (glossario): nell'app le funzioni v2 compaiono in **Impostazioni › Aggiornamenti**, sotto la versione, come elenco statico nel bundle: nome e una riga, senza date, aggiornato a ogni release. Niente elenco remoto, niente segnaposto o bottoni grigi nell'HUD.
4. **Contenuto di In arrivo** oggi: **Consegna di una Sessione** e **Risorse di squadra nel repo**. Le cose escluse o condizionate a terzi (wake word, invio di Sessioni nel cloud, Homebrew Cask) non compaiono.
5. **Fuori anche in v2**: la co-guida simultanea della stessa Sessione, perché ogni turno consuma l'account di chi lo manda e la credenziale non si condivide.

## Cosa si farà in v2

- **Consegna di una Sessione**: il mittente sceglie "Consegna…", Bubo pusha il ramo, prepara il transcript ripulito (email, organizzazione, percorsi) e lo manda al destinatario su un canale dell'utente; il destinatario lo riprende col proprio account in una copia isolata, come una **Bozza** che deve avviare lui. Niente credenziali condivise, niente server di Bubo.
- **Risorse di squadra nel repo**: un formato versionato per Automazioni e Regole di permesso di Bubo nel repo, con un passo di fiducia esplicito per ogni `allow` o Automazione scritta da altri, come fa Claude Code con le cartelle.
- **Condivisione dal vivo**: solo se un trasporto dell'utente lo consente senza server (oggi SharePlay durante FaceTime); in sola lettura per il destinatario.

## Domande aperte per la mappa v2

- **Accoppiamento del destinatario**: come si scambiano chiavi due utenti Bubo con Apple ID diversi, senza server (CKShare a invito, file firmato, QR di persona)?
- **Canale di consegna**: CKShare (E2E solo con ADP), un file cifrato da mandare con qualunque mezzo, o il repo stesso (ramo + file cifrato)?
- **Ripresa su un altro account**: funziona davvero un JSONL di un altro account o di un'altra organizzazione? Cosa fa la CLI con `organizationUuid` diverso?
- **Pulizia del transcript**: cosa si toglie senza rompere la ripresa (email, `organizationUuid`, percorsi assoluti, output degli strumenti con segreti)?
- **Prototipo del foglio di consegna**: mittente, destinatario, anteprima di cosa esce, ricevuta.
- **Formato delle risorse di squadra**: dove nel repo, come si firma o si fida, come convive con `.claude/settings.json`.

## Fonti

Le fonti complete sono nel file di ricerca. Principali:

1. Claude Code, *Sessions* — https://code.claude.com/docs/en/sessions
2. Claude Code, *The .claude directory* — https://code.claude.com/docs/en/claude-directory
3. Claude Code, *Memory* — https://code.claude.com/docs/en/memory
4. Claude Code, *Settings* — https://code.claude.com/docs/en/settings
5. Claude Code, *Use Claude Code in the cloud* — https://code.claude.com/docs/en/claude-code-on-the-web
6. Agent SDK, *Session storage* — https://code.claude.com/docs/en/agent-sdk/session-storage
7. Apple, `CKShare` e *Shared records* — https://developer.apple.com/documentation/cloudkit/ckshare
8. Apple, Protezione avanzata dei dati — https://support.apple.com/en-us/102651
9. Apple, GroupActivities — https://developer.apple.com/documentation/groupactivities
10. Cursor, *Shared transcripts* — https://cursor.com/help/ai-features/shared-transcripts
