# 23 — Sessioni remote via SSH e sessioni cloud

Ticket: [#233](https://github.com/mgiuditta/bubo/issues/233) (ricerca), [#236](https://github.com/mgiuditta/bubo/issues/236) (decisioni), [#242](https://github.com/mgiuditta/bubo/issues/242) (prototipo di Macchina e connessione). Mappa: [#231](https://github.com/mgiuditta/bubo/issues/231).
Ricerca del 2026-09-30 con CLI `claude` **2.1.285** e Agent SDK TS **0.3.285** (`sdk.d.ts` letto in locale). Ricerca completa: [`23-sessioni-remote.md`](https://github.com/mgiuditta/bubo/blob/research/sessioni-remote/docs/features/research/23-sessioni-remote.md) sul branch `research/sessioni-remote`. Prototipo (da buttare): [`prototypes/macchina.html`](https://github.com/mgiuditta/bubo/blob/prototype/macchina/prototypes/macchina.html) sul branch `prototype/macchina`.

> **Nota sulla ricerca.** È scritta prima delle decisioni. Il turno che sopravvive alla caduta (engine persistente, `tmux`) non entra in v1: la caduta perde il turno in corso e si riprende con `--resume`. Delle sessioni cloud entra solo l'ingresso ("Porta in Bubo"), non l'invio né l'elenco. Valgono la Mappa e la Specifica qui sotto.

In sintesi: un Progetto può stare su una **Macchina** diversa dal Mac, cioè un computer dell'utente raggiunto via SSH. Le sue Sessioni girano lì, con il `claude` e il login dell'host, e Bubo le guida come quelle locali: l'Agent SDK accetta qualunque processo con stdin e stdout, e `ssh host -- claude …` lo è. Bubo usa l'OpenSSH di sistema e `~/.ssh/config`, non conserva chiavi né password e non ha una sua lista di fiducia. Dal cloud di Claude Code entra solo "Porta in Bubo": un link di claude.ai/code diventa una Sessione in una copia isolata del Progetto. Claude Desktop ha già le sessioni SSH e resta il riferimento; Bubo lo supera su permessi, diff, Terminale e Anteprima remoti, sulla caduta di rete e sulla Memoria che funziona anche a Macchina spenta.

## Ricerca

Riassunto; dettagli, prove e fonti complete nel file di ricerca.

### Trasporto SSH con l'Agent SDK

- **`spawnClaudeCodeProcess`** [1] sostituisce lo spawn locale: "Use this to run Claude Code in VMs, containers, or remote environments". Serve un processo con `stdin`, `stdout`, `kill`, `exitCode` ed eventi `exit`/`error`: un `ChildProcess` che lancia `ssh` basta.
- **Protocollo**: stream-json su stdio. Vanno sostituiti `command` (percorso locale del binario dell'SDK), `cwd` (con un `cd`) ed `env` (con `env K=V`, perché SSH non inoltra le variabili). Verificato in locale con `/bin/sh -c`; un vero `ssh` non è stato provato.
- **Stato sull'host** [2]: transcript, CLAUDE.md, skill, settings, login, git e worktree stanno sull'host. `listSessions()` e `getSessionMessages()` letti da Bubo vedono il disco locale.
- **Caduta** [3]: un `claude` figlio di `ssh` muore con la connessione. Anthropic consiglia `tmux` o `screen`; con `--resume <id>` sullo stesso host si riprende la conversazione.
- **Spare** [1]: `prewarm()` con uno spawn remoto richiede una `cwd` che esista sull'host; ogni spare occupa ~230–260 MB.

### Claude Desktop con SSH

- OpenSSH di sistema, `~/.ssh/config`, `known_hosts` con conferma dell'impronta, passphrase chiesta nell'app [4][5].
- Connessioni in `sshConfigs` di `~/.claude/settings.json`; `sshHostAllowlist` per le aziende, verificata dopo `ssh -G`.
- Installa Claude Code sull'host da solo; engine in `~/.claude/remote/` che sopravvive a disconnessione e stop; alla riapertura riparte dal transcript e interrompe il turno in corso.
- Permessi, connector, plugin e MCP supportati; niente `/resume` delle sessioni CLI né "Continue in → cloud".

### Sessioni cloud di Claude Code

- VM Anthropic legate all'account claude.ai e a GitHub; Pro, Max, Team, Enterprise; niente API key, provider terzi o ZDR [6].
- **Da un'app terza** [6][7]: creare (`claude --cloud "<task>"`), accodare un messaggio (`claude -p "<msg>" --cloud <id> --output-format json`), portare in locale (`claude --teleport <id>`).
- **Nessuna API né CLI non interattiva per elencare** le sessioni cloud, leggerne lo stato o seguirne lo stream.
- **Teleport**: stesso repo, working tree pulito, stesso account, branch pushato. Porta branch e cronologia; poi la copia locale diverge. Solo dal cloud al locale.

### Concorrenti

| Prodotto | Dove gira | Trasporto | Porte | Caduta | Elenco e API |
|---|---|---|---|---|---|
| **Claude Desktop** [4][5] | host SSH, engine in `~/.claude/remote/` | OpenSSH di sistema | — | engine sopravvive, turno interrotto | nessuna |
| **Zed** [8] | server remoto, UI e LLM sul Mac | ControlMaster per progetto | `-L` configurabile | daemon, modifiche locali conservate | nessuna |
| **VS Code Remote-SSH** [9] | VS Code Server | tunnel SSH | "Forward a Port" | non documentata | — |
| **Codex** [10][11] | `codex app-server` sull'host, o cloud | OpenSSH, alias del config | — | handoff tra host | `codex cloud list --json` |
| **Cursor** [12] | VM di Cursor | clone | — | — | `GET /v1/agents`, SSE |
| **Conductor** [13] | sandbox Linux del loro cloud | "Open via SSH" | manuale | processi persi | REST + CLI JSON |

## Il meglio da battere

Il riferimento è **Claude Desktop con SSH**: config di sistema, fiducia di OpenSSH, installazione automatica, engine che sopravvive. Non ha però Richieste di permesso con livelli, revisione del diff per blocco, Terminale e Anteprima con porte inoltrate, né una Memoria consultabile a host spento. **Zed** e **VS Code** hanno l'inoltro delle porte ma non guidano un agente Claude. **Codex** ha il cloud elencabile, che Claude Code non ha.

## Rischi e casi limite

- **Vero `ssh` mai provato**: latenza, riconnessione e segnali vanno misurati. Per questo il primo ticket è un cancello con uno spawn reale.
- **Caduta = processo morto**: il turno in corso si perde; un comando lasciato a metà sull'host resta com'è.
- **Stato sull'host**: tutto ciò che Bubo legge oggi dal disco (diff, file, Stato, transcript) deve passare dal canale SSH.
- **Chiave dell'host cambiata**: può essere un attacco; non si scavalca.
- **`claude` mancante o non loggato** sull'host.
- **Account diverso** sull'host rispetto al Mac: Quota e Spesa di un altro account.
- **Host lento o su rete mobile**: primo token più lento.
- **Porte**: un server sull'host non è raggiungibile dal Mac senza inoltro.
- **Teleport** su un Progetto con modifiche non committate: il teleport vuole un working tree pulito.
- **Host Windows**: la CLI funziona, ma i comandi di Bubo (shell POSIX, `git worktree`, percorsi) no.
- **Sandbox sull'host Linux**: bubblewrap può mancare.

## Mappa

Architettura comune in [INDEX.md](INDEX.md). Si appoggia sul ponte agente con disclaim (ADR 0005), Sessioni in worktree (01), diff e merge (02), account (03), Richieste e Regole (05), Attività e Fase (06), Memoria, Indice e copia a specchio (13, 14, ADR 0006), Terminale e Anteprima (15), Costi e Budget (18), Automazioni (19), Sandbox (22), onboarding di `claude` (26).

### Macchina e Progetto (deciso)

Fonte: [#236](https://github.com/mgiuditta/bubo/issues/236), glossario: **Macchina**.

- Un Progetto sta su una sola Macchina (il Mac o un host SSH) e tutte le sue Sessioni girano lì.
- **Host da `~/.ssh/config`**, con l'OpenSSH di sistema, `ssh-agent` e `UseKeychain`. Bubo non legge né conserva chiavi o password.
- **Host macOS e Linux**, niente Windows.
- **`claude` mancante**: Bubo mostra il comando ufficiale e lo esegue solo dopo una conferma.
- **Login sull'host**: nel Terminale di Bubo aperto su quella Macchina (ADR 0003, 26).
- **Account dell'host** letto con `claude auth status --json` e mostrato nella Sessione. La Spesa si conta dai risultati dell'SDK, la Quota per account, il Budget del Progetto vale uguale. Nessun obbligo di usare lo stesso account del Mac.

### Fiducia e revoca (deciso)

- **Prima connessione**: impronta dell'host e conferma. Mai `StrictHostKeyChecking=no`.
- **Chiave dell'host cambiata**: blocco senza scavalcamento.
- **Rimuovi Macchina**: chiude le connessioni e toglie i Progetti. Le copie locali dei transcript restano finché l'utente non le elimina.
- Niente allowlist aziendale in v1.

### Connessione caduta (deciso)

- **Keepalive e ControlMaster.** Quando cade, la Sessione va in Errore "Macchina irraggiungibile".
- **Riconnessione automatica** con `claude --resume` sull'host, più un pulsante **Riprendi**.
- Il turno in corso si perde, la conversazione no. Il turno che sopravvive (`tmux` o fifo) è un'evoluzione possibile, fuori v1.

### Cosa funziona su una Sessione remota (deciso)

- **Uguale al locale**: Richieste e Regole di permesso (via stdio), Attività e Fase, Memoria, Indice e Galassia (transcript copiati in locale con `sessionStore`, ADR 0006), Telecomando (21), voce.
- **Via SSH**: worktree e diff/merge con git sull'host; Terminale con `ssh -t`; Anteprima con `-L` automatico sulla porta rilevata; Allegati copiati in una cartella temporanea della Sessione sull'host.
- **Sandbox**: quella di Claude Code sull'host (bubblewrap o Seatbelt), stesso preset, `failIfUnavailable`.
- **Automazioni** ammesse. Se la Macchina non risponde, l'Esecuzione è **Saltata** con motivo.
- **Fuori v1**: riavvolgimento sui file, apertura dei file nell'editor del Mac.

### Sessioni cloud (deciso)

- Solo **"Porta in Bubo"**: si incolla un link o un ID di claude.ai/code.
- Bubo cerca il Progetto con lo stesso remote GitHub e fa il teleport in una **nuova copia isolata** (quindi pulita), anche su un Progetto remoto, con il teleport eseguito sull'host.
- Nessun Progetto corrispondente → proposta di clonare il repo o di aggiungere una cartella esistente.
- Etichetta **"Dal cloud"** con il link.
- **Niente "Manda nel cloud"**: senza API di elenco sarebbe una Sessione cieca. Si riapre se Anthropic la pubblica.

### Interfaccia (deciso)

Fonte: [#242](https://github.com/mgiuditta/bubo/issues/242), vince la variante **A, Selettore**, con due pezzi della B.

- **Aggiungi Progetto**: campi Macchina (menu) e Cartella. Menu: Questo Mac, separatore "Da ~/.ssh/config", un host per riga con `utente@hostname` e "nuova" accanto agli host mai connessi. Con una Macchina remota, "Sfoglia…" elenca le cartelle via `ssh ls` e compare la nota "Le Sessioni gireranno su <host> con il suo claude". Con solo il Mac e `~/.ssh/config` vuoto il menu non compare.
- **Prima connessione**: foglio con `utente@hostname`, impronta della chiave che l'host presenta (di solito ED25519) in monospazio, come verificarla sull'host (`ssh-keygen -lf …`), Annulla e "Mi fido, connetti". La chiave va in `~/.ssh/known_hosts`, lo stesso file di OpenSSH: nessuna seconda lista di fiducia.
- **Manca `claude`**: foglio con il comando ufficiale in chiaro, "Lo installo io" e "Installa su <host>" (nella cartella utente, senza sudo). Host senza account → "Accedi a Claude su <host>", che apre il Terminale di Bubo sull'host con `claude /login`.
- **Stato**: etichetta dell'host sul Progetto nella barra laterale con un punto: Connessa in `textSecondary` pieno; Riconnessione in `textSecondary` che pulsa (fermo con Riduci movimento); Irraggiungibile (anello) e Bloccata (croce) in `danger`. Ogni stato ha una forma sua e VoiceOver lo legge con il nome. Lo stesso punto sulla riga della Sessione. Nella testata: Progetto, host e account dell'host.
- **Riconnessione**: banner acromatico (vetro, filo `lineStrong`, `LoadingLabel`) "Riconnessione a <host>… Il turno in corso può essere perso, la conversazione no". Al ritorno, `--resume` automatico e nota "Ripresa dopo la caduta: rimanda l'ultimo turno se serve".
- **Irraggiungibile** (dopo 30 s): banner in `danger` "<host> non risponde. Riprovo ogni minuto" con **Riprendi**. Il campo di scrittura resta attivo con il segnaposto "Il messaggio parte quando la Macchina torna".
- **Chiave cambiata**: banner in `danger` con Dettagli → foglio con impronta attesa e ricevuta, senza pulsante per procedere; solo "Copia comando" con `ssh-keygen -R <hostname>`. Anche Riprendi e Porta in Bubo portano lì.
- **Porta in Bubo**: dalla barra degli strumenti o dal menu File; campo per link o ID; errore in linea "Non è un link di claude.ai/code né un ID di sessione"; senza Progetto corrispondente, "Clona in ~/dev/<repo> e porta" oppure "Aggiungi cartella esistente…".
- **Da B**: Impostazioni › Macchine (elenco con `utente@hostname`, sistema, versione di `claude`, account, stato, impronta, Progetti, **Rimuovi Macchina…**); clic destro sull'etichetta dell'host → "Dettagli Macchina" e "Aggiungi Progetto su <host>…".

### Cancello (deciso)

Primo ticket di costruzione: spawn reale via SSH verso un host Linux, con misura dei criteri 1, 2 e 7. Se non passa, i criteri si ricalibrano e la strada resta questa.

### Dettagli di costruzione

Scelti scrivendo la spec, non nelle issue. Si possono cambiare senza toccare le decisioni sopra.

- **Un ControlMaster per Macchina**: `ssh -o ControlMaster=auto -o ControlPath=~/.ssh/bubo/%C -o ControlPersist=600 -o ServerAliveInterval=10 -o ServerAliveCountMax=3`. Tutto passa dalla stessa connessione: spawn di `claude`, git, lettura di file, Terminale, inoltri. `ssh -O check` dà lo stato.
- **Scoperta degli host**: `ssh -G` risolve un alias ma non li elenca. Bubo legge solo i nomi delle righe `Host` di `~/.ssh/config` e dei file `Include` (glob in ordine lessicale, relativi a `~/.ssh`), scarta i pattern con `*`, `?` o `!`, e risolve ogni alias con `ssh -G <alias>`, come fa Codex.
- **Prima connessione e fiducia**: Bubo passa sempre `-o StrictHostKeyChecking=ask` (connessioni chieste dall'utente) o `=yes` (le altre), così un `no` nel config dell'utente non scavalca il blocco. La domanda di OpenSSH con l'impronta arriva a un helper `SSH_ASKPASS` (`SSH_ASKPASS_REQUIRE=force`), che funziona anche con `ProxyJump`; la risposta passa da una FIFO, mai da un file, e `known_hosts` lo scrive ssh. Il socket del ControlMaster resta entro i 104 byte di macOS (cartella corta sotto `~/.ssh`).
- **Spawn**: `ssh -T <alias> -- 'cd <cwd> && exec env <K=V…> <claude remoto> <args>'`, con quoting POSIX calcolato da una funzione pura testata. Il `claude` remoto si trova una volta con `command -v claude` in una login shell e si salva per Macchina.
- **`env` remoto**: solo le variabili che Bubo passa anche in locale (sessione, emissione degli stati). Mai l'API key del Mac: sull'host vale il login dell'host.
- **Operazioni git e file** dietro un protocollo `MachineShell` con due implementazioni, locale e SSH. Diff, merge, worktree, FSEvents: sul remoto lo stato si ricalcola alla fine di ogni turno e su richiesta, niente watcher remoto in v1.
- **Worktree sull'host** nella stessa posizione relativa che usa 01 sul Mac, sotto la home dell'host.
- **Copia a specchio**: `sessionStore` di Bubo riceve le righe dal ponte come per le Sessioni locali; Memoria, Indice e Galassia leggono solo la copia locale.
- **Riconnessione**: backoff 1 s, 2 s, 4 s, 8 s, 15 s, poi ogni 60 s. "Irraggiungibile" dopo 30 s dalla caduta. Al ritorno, `claude --resume <id>` con la stessa `cwd` sull'host.
- **Messaggi scritti durante la caduta**: in coda nella Sessione, inviati come nuovo turno dopo il `--resume`; mai più di uno in coda (l'ultimo sostituisce i precedenti, con conferma).
- **Terminale**: `ssh -t <alias> -- 'cd <worktree> && exec $SHELL -l'` nella stessa finestra della 15.
- **Anteprima**: la porta rilevata dalla 15 sull'host (lettura dell'output e `ss -ltnp` o `lsof -iTCP -sTCP:LISTEN` via SSH) → `ssh -O forward -L <porta locale>:localhost:<porta remota>` sul ControlMaster; porta locale dal `PortAllocator`. L'etichetta mostra `localhost:<porta locale> ← <host>:<porta remota>`.
- **Allegati**: `scp` via ControlMaster in `~/.cache/bubo/<sessione>/` sull'host; cancellati alla chiusura della Sessione.
- **Installazione di `claude`**: il comando ufficiale dello script di installazione nativo, eseguito in una login shell dopo la conferma, con l'output nel foglio. Nessun `sudo`.
- **Sandbox Linux**: `failIfUnavailable` fa fallire la Sessione se bubblewrap manca; il messaggio dice il pacchetto da installare (`bubblewrap`).
- **Teleport**: `claude --teleport <id>` in una copia isolata nuova (stesso meccanismo del worktree di 01), eseguito in un PTY perché è interattivo; al termine Bubo apre la Sessione con `--resume` sul transcript creato. Su un Progetto remoto tutto gira sull'host.
- **Account dell'host**: `claude auth status --json` alla connessione e a ogni riconnessione; se cambia, una riga nella Sessione.
- **Automazioni**: prima dell'Esecuzione, `ssh -O check` o una connessione con timeout 10 s; fallita → Saltata "Macchina irraggiungibile".
- **Impostazioni › Macchine** legge i dati da `ssh -G`, `uname -sr`, `claude --version` e `claude auth status --json`, aggiornati alla connessione.

### Moduli

Architettura comune in [INDEX.md](INDEX.md). Moduli nuovi:

- `Machines/MachineStore`: Macchine usate, `claude` remoto, impronta confermata (solo come promemoria: la fiducia sta in `known_hosts`).
- `Machines/SSHConfigReader`: alias concreti via `ssh -G`.
- `Machines/SSHConnection`: ControlMaster, stato, keepalive, riconnessione, inoltri.
- `Machines/HostKeyGate`: prima connessione e chiave cambiata.
- `Machines/MachineShell`: protocollo per comandi, file e git; `LocalShell` e `SSHShell`.
- `Machines/RemoteClaudeInstaller`: rilevamento, installazione, login.
- `Cloud/TeleportController`: link o ID → Progetto → copia isolata → teleport → Sessione "Dal cloud".
- `HUD/MachineBadge`, `HUD/ConnectionBanner`, `Settings/MachinesPane`, `Projects/AddProjectSheet` esteso.
- Estensioni: `Agent/ProcessSpawner` (spawn via SSH per `spawnClaudeCodeProcess`), `Git/` e `Sessions/WorktreeManager` sopra `MachineShell`, `Terminal/` e `Servers/` (SSH e inoltri), `Automations/ExecutionRunner` (Saltata per Macchina irraggiungibile), `Sandbox/SandboxPolicy` (host Linux).

### Flusso

1. **Aggiungi Progetto su un host**: menu Macchina → host "nuova" → foglio della prima connessione → "Mi fido, connetti" → `known_hosts` → `command -v claude` → se manca, foglio di installazione → `claude auth status` → se manca il login, Terminale sull'host → Sfoglia via `ssh ls` → Progetto aggiunto con l'etichetta dell'host.
2. **Nuova Sessione**: worktree sull'host via `MachineShell` → spawn via SSH → stream-json → Sessione uguale a una locale.
3. **Caduta**: ControlMaster perso → Errore "Macchina irraggiungibile", banner di Riconnessione → backoff → connessione tornata → `--resume` → nota nella conversazione → Attende te.
4. **Anteprima**: server rilevato sull'host → inoltro `-L` → Anteprima su `localhost:<porta locale>`.
5. **Porta in Bubo**: link → ID → Progetto con lo stesso remote → copia isolata → `--teleport` → Sessione "Dal cloud".

### Casi limite

- **Due Progetti sulla stessa Macchina**: un solo ControlMaster; una caduta li tocca tutti.
- **Host con `ProxyJump`**: funziona perché passa da OpenSSH; il tempo della prima Sessione può superare il criterio 1, che vale in LAN.
- **Chiave con passphrase senza `ssh-agent`**: OpenSSH la chiede; Bubo usa `SSH_ASKPASS` con un piccolo helper che mostra un foglio nativo e non conserva la risposta.
- **`claude` sull'host troppo vecchio**: stessa versione minima della 27; la Sessione non parte e il foglio propone di aggiornarlo.
- **Account dell'host con API key**: Porta in Bubo non funziona su quell'host (serve un abbonamento); il foglio lo dice.
- **Teleport di un repo che non è su GitHub**: non si può; errore in linea.
- **Teleport con account diverso** da quello della sessione cloud: errore della CLI, mostrato così com'è con "Serve lo stesso account di claude.ai".
- **Porta già occupata sul Mac**: il `PortAllocator` ne sceglie un'altra.
- **Macchina rimossa con Sessioni aperte**: conferma che le elenca; poi `ssh -O exit`.
- **Automazione su una Macchina spenta**: Saltata con motivo; nessun nuovo tentativo automatico oltre a quelli già previsti dalla 19.
- **Galassia di un Progetto remoto**: usa l'albero dei file letto via `MachineShell` alla prima apertura e dopo ogni turno.
- **Sessione remota e Telecomando**: la card mostra anche il nome dell'host.

### Test

- **Cancello**: host Linux reale in LAN; tempo da voce di `~/.ssh/config` alla prima Sessione (criterio 1), caduta simulata con `iptables` o spegnimento dell'interfaccia (criterio 2), primo token remoto contro locale su 20 turni (criterio 7).
- `SSHConfigReader` con config di prova (alias concreti, pattern, `Include`).
- **Quoting** del comando remoto: tabella di `cwd` ed `env` con spazi, apici, `$`, caratteri unicode → comando eseguito identico.
- `MachineShell` locale e SSH con la stessa suite (diff, merge, worktree, lettura di file) su un container Linux in CI.
- **Fiducia**: host nuovo → foglio; chiave cambiata → blocco e 0 connessioni; nessun `StrictHostKeyChecking=no` negli argomenti (test sugli argomenti).
- **Nessun segreto**: ricerca di chiavi o password nello store di Bubo dopo i test → 0.
- **Memoria e Indice a Macchina spenta**: host fermato → ricerca e Memoria del Progetto funzionano (criterio 6).
- **Porta in Bubo** con una sessione cloud di prova: su Progetto locale, su Progetto remoto, link non valido.
- Accessibilità: audit SwiftUI e AppKit del foglio Aggiungi Progetto, dei banner, del punto di stato e di Impostazioni › Macchine.

### Ordine di costruzione

1. **Cancello con spawn reale via SSH**: `SSHConnection` minimo, spawn di `claude` sull'host, una Sessione senza diff né Terminale, misura dei criteri 1, 2 e 7. Esito nel ticket. Dipende dal ponte agente ([#66](https://github.com/mgiuditta/bubo/issues/66)).
2. **Macchina nel Progetto**: `SSHConfigReader`, foglio Aggiungi Progetto con il menu, prima connessione, `known_hosts`, `HostKeyGate` con chiave cambiata, `MachineStore`, etichetta dell'host, Impostazioni › Macchine e Rimuovi Macchina. Dipende da 1.
3. **`claude` sull'host**: rilevamento, installazione con conferma, login nel Terminale, account dell'host nella Sessione e nei costi. Dipende da 2, da 15 (Terminale) e da 26 ([#201](https://github.com/mgiuditta/bubo/issues/201)).
4. **Worktree, diff e merge remoti**: `MachineShell`, git sull'host, copia a specchio dei transcript. Dipende da 2, da 01 e 02.
5. **Caduta e ripresa**: stati Riconnessione e Irraggiungibile, banner, `--resume`, messaggio in coda, Riprendi. Dipende da 4.
6. **Terminale, Anteprima e Allegati remoti**: `ssh -t`, inoltri `-L`, copia degli Allegati. Dipende da 4 e da 15.
7. **Sandbox e Automazioni remote**: Sandbox sull'host Linux e macOS, Esecuzione Saltata per Macchina irraggiungibile. Dipende da 4, 19 e 22.
8. **Porta in Bubo**: `TeleportController`, foglio, etichetta "Dal cloud", clone o cartella esistente. Dipende da 01 e, per i Progetti remoti, da 4.

## Specifica "migliore di"

Migliori concorrenti: **Claude Desktop con SSH** (config di sistema, installazione automatica, engine che sopravvive, ma niente livelli di rischio, diff per blocco, porte, Memoria), **Zed** e **VS Code Remote-SSH** (inoltro delle porte, ma nessun agente Claude), **Codex** (SSH e cloud elencabile).
Bubo li supera così:

1. **Veloce da configurare**: da una voce di `~/.ssh/config` alla prima Sessione in **≤ 60 s**, con `claude` già installato.
2. **Caduta senza danni**: caduta di rete **≤ 30 s** → la Sessione torna in Attende te **da sola**, con la conversazione intatta.
3. **Tutto funziona**: Richieste di permesso, diff/merge, Terminale e Anteprima su una Sessione remota (**4 su 4**).
4. **Teleport in 1 azione**, sempre in una copia isolata.
5. **Nessun segreto**: **0** chiavi o password nello store di Bubo.
6. **Memoria e Indice** funzionano con la Macchina **spenta**.
7. **Latenza**: primo token di un turno remoto **≤ locale + 150 ms**, in LAN.

### Dove perdiamo

- **Turno perso** quando la connessione cade (Claude Desktop tiene vivo l'engine).
- **Niente riavvolgimento** sui file di una Sessione remota.
- **Niente host Windows.**
- **Niente invio nel cloud** né elenco delle sessioni cloud.

## Fonti

1. `@anthropic-ai/claude-agent-sdk` 0.3.285, `sdk.d.ts` (`spawnClaudeCodeProcess`, `SpawnOptions`, `SpawnedProcess`, `prewarm`, `SessionStore`) — https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk
2. Agent SDK, *Hosting* — https://code.claude.com/docs/en/agent-sdk/hosting
3. Claude Code, *Remote Control* (limiti, `tmux`) — https://code.claude.com/docs/en/remote-control
4. Claude Code, *Desktop — SSH sessions* — https://code.claude.com/docs/en/desktop#ssh-sessions
5. Claude Desktop, *SSH remote sessions* — https://claude.com/docs/third-party/claude-desktop/ssh-remote-sessions
6. Claude Code, *Use Claude Code in the cloud* — https://code.claude.com/docs/en/claude-code-on-the-web
7. Claude Code, *CLI reference* e *Routines* — https://code.claude.com/docs/en/cli-reference , https://code.claude.com/docs/en/routines
8. Zed, *Remote development* — https://zed.dev/docs/remote-development
9. VS Code, *Remote development using SSH* — https://code.visualstudio.com/docs/remote/ssh
10. OpenAI Codex, *Remote connections* — https://learn.chatgpt.com/docs/remote-connections
11. OpenAI Codex, *Cloud* e *CLI* — https://learn.chatgpt.com/docs/cloud
12. Cursor, *Cloud agents* e API — https://cursor.com/docs/cloud-agent
13. Conductor, *Cloud* e API — https://conductor.build/docs/cloud
14. Claude Code, *Agent view* — https://code.claude.com/docs/en/agent-view
15. Claude Code, *Self-hosted environments* — https://code.claude.com/docs/en/self-hosted-environments
