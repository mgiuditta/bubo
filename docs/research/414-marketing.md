# Ricerca #414 — Piano per portare Bubo tra le app open source più consigliate

Ticket: [#414](https://github.com/mgiuditta/bubo/issues/414). Collegati: [#220](https://github.com/mgiuditta/bubo/issues/220) (certificato, chiavi e `bubo-releases`), [#229](https://github.com/mgiuditta/bubo/issues/229) (audit e `v0.1.0-beta.1`), [#188](https://github.com/mgiuditta/bubo/issues/188) (hosting delle release). Spec: [`docs/features/27-rifinitura-aggiornamenti.md`](../features/27-rifinitura-aggiornamenti.md).
Ricerca del 2026-10-02. Stelle GitHub lette con la ricerca di GitHub, punti di Hacker News con l'API di Algolia, installazioni Homebrew con `formulae.brew.sh` (30 giorni, 2026-09-02 → 2026-10-02), regole delle liste dai rispettivi `CONTRIBUTING.md` alla stessa data.

**Domanda.** Con quali canali, asset, tempi e metriche Bubo può entrare tra le app open source per Mac più consigliate (GitHub Trending, liste awesome, Homebrew, Hacker News, Reddit, reel), e che cosa manca prima di cominciare?

## In sintesi

- **Prima di qualsiasi lancio serve un DMG firmato e notarizzato** ([#220](https://github.com/mgiuditta/bubo/issues/220)). Show HN vieta i lanci di cose "non pronte da provare" [1]; Homebrew disattiva da settembre 2026 i cask che non passano Gatekeeper [5][6]; r/macapps e awesome-claude-code chiedono di poter installare senza barriere [8][3]. Oggi il README dice "Download: coming soon": nessun canale funziona finché resta così.
- **Un solo picco ben preparato vale più di dieci post.** I casi studio arrivano in cima con un post su Hacker News da 450–670 punti (Ice, Stats, Claudia), che porta GitHub Trending per giorni; poi liste awesome e Homebrew consolidano. Ice: 670 punti il 2024-06-07 e 2.328 stelle in 7 giorni [12][13].
- **Il mercato "GUI per Claude Code" è saturo nel 2026.** Le Show HN di app native per Claude Code di quest'anno hanno 1–2 punti (Poirot, AI Usage, Claude Rate Widget) [14]. Bubo non deve presentarsi come "un'altra GUI": il gancio è **l'Orb che parla e cambia forma** (visivo, da reel) più **"scritta da agenti Claude in 4 giorni, storia pubblica"** (da HN), più "nativa Swift/Metal, zero Electron".
- **Il racconto "costruita da agenti" è un'arma a doppio taglio.** Le linee guida di Show HN ora dicono "Don't post quickly-generated one-offs" [1]; r/macapps manda nel megathread chi non ha un anno di storia [8]. Va raccontata come metodo (ADR, 1.630 test, review umana di ogni merge), non come velocità.
- **Soglie da conoscere:** Homebrew ufficiale 225 stelle se lo propone il proprietario, 75 se lo propone un altro [4]; awesome-claude-code 14 giorni dal primo commit con sviluppo attivo **oppure** 100 stelle, e una proposta scritta da un umano nel modulo web [3]; r/macapps feed principale con 1+ anno di storia e 100+ stelle [8]; r/ClaudeAI feed con karma ≥ 50 [9].
- **Raccomandazione:** fase 0 (prerequisiti e asset) ora, in parallelo a #220; lancio di martedì o mercoledì con Show HN + video su X/reel lo stesso giorno; onde di Reddit, liste e Product Hunt nelle due settimane dopo; tap Homebrew proprio dal giorno 1, cask ufficiale a 225 stelle. Obiettivo realistico: 1.000 stelle e 1.500 download nei primi 30 giorni, 5.000 stelle a 6 mesi.

## Vincoli già decisi

- **Licenza e repository**: MIT, `mgiuditta/bubo` pubblico (verificato: `private: false`, 1 stella, nessuna descrizione, nessun topic, nessuna homepage, Discussions spente). La spec 27 dice ancora "Il codice resta privato in `mgiuditta/bubo`": è superata, da correggere.
- **Distribuzione** (spec 27): DMG Developer ID notarizzato, Sparkle 2, release e appcast nel repository pubblico `mgiuditta/bubo-releases`. **Homebrew Cask esce dalla v1**, rimandato "dopo la prima stabile, con `auto_updates true`". Questa ricerca propone di anticipare un **tap proprio** (sotto).
- **Requisiti utente**: macOS 26 su Apple Silicon e CLI `claude` installata e loggata (README). Restringe il pubblico ai Mac aggiornati e agli utenti Claude Code: va detto nel primo paragrafo di ogni post, per non bruciare il pubblico sbagliato.
- **Marchi** (brief, §1): niente loghi di Anthropic o altri; "Not affiliated with Anthropic" già nel README. Vale anche per thumbnail, reel e sito.
- **Locale per default**: nessuna telemetria. Le metriche di uso vengono solo da fonti pubbliche (stelle, download degli asset, analytics di Homebrew), non dall'app.
- **Quando** (#414): dopo la coda `ready-for-agent` costruibile dagli agenti. Oggi ne restano 41 aperti.

## Stato di partenza

| Voce | Oggi | Serve per il lancio |
|---|---|---|
| Release scaricabile | No ("coming soon") | DMG firmato e notarizzato (#220, #229) |
| README | Inglese, GIF dell'Orb renderizzata, tabella "Built by Claude agents" | Video vero (voce + Sessioni), riga di installazione, requisiti in alto |
| Metadati del repo | Nessuna descrizione, topic, homepage, social preview | Tutti e quattro |
| Sito | Nessuno | Una pagina (GitHub Pages va bene) |
| Nome e dominio | `bubo.app` è di un'altra azienda (gestione patrimoni); `bubo.dev` e `bubo.sh` rispondono | Dominio da scegliere o GitHub Pages |
| Community | Issue aperte, Discussions spente | Discussions, template di issue, `good first issue` |

## Casi studio

Stelle al 2026-10-02 [2]; installazioni Homebrew negli ultimi 30 giorni [7]; punti HN dall'API di Algolia [12].

| App | Stelle | Brew 30 gg | Come è arrivata in cima | Lezione per Bubo |
|---|---|---|---|---|
| **Ice** (menu bar) | 29,7k | 2.302 | Post HN "Ice – open source menu bar manager" 670 punti, 189 commenti (2024-06-07); +2.328 stelle in 7 giorni, GitHub Trending [12][13]. Archiviato nel 2025, non funziona su Tahoe [15] | Un solo post HN al momento giusto basta. Ma la manutenzione conta: abbandonato, perde il posto |
| **Thaw** (fork di Ice) | 11,7k in 8 mesi | 1.858 | Nato a gennaio 2026 per coprire il vuoto lasciato da Ice su macOS 26; stampa Mac (MacG, iFun), Product Hunt il 2026-09-03 [15][16] | "Funziona su Tahoe" è un argomento. Bubo è solo macOS 26: va detto come punto di forza |
| **Stats** | 42,3k | 5.717 | Anni di passaparola; post HN 450 punti (2025-01-30), poi un thread di critiche sulla privacy (dati inviati al server dello sviluppatore) [12] | Un dubbio sulla privacy diventa una notizia. Bubo deve spiegare cosa esce dal Mac prima che lo chieda qualcuno |
| **Maccy** | 21,8k | 4.751 | Show HN del 2019 con 8 punti; il post di un utente nel 2022 fa 134 punti [12] | La prima Show HN può andare a vuoto; il passaparola e un secondo post di terzi funzionano. Non si ripubblica la stessa Show HN |
| **AltTab** | 16,4k | 1.626 | Show HN 156 punti, 122 commenti (2019-10-14) [12] | Problema chiaro in una frase nel titolo |
| **Rectangle** | 30,0k | 5.026 | Successore dichiarato di Spectacle, abbandonato; scorciatoie compatibili al primo avvio [17] | "Sostituto di X" porta utenti già convinti |
| **Claudia / opcode** | 22,4k | 32 | Lanciata da Asterisk (YC S24) a giugno 2025, articoli (It's FOSS, AIM), HN 501 punti e 226 commenti (2025-08-17); rinominata opcode a ottobre 2025 [12][18] | Il primo GUI per Claude Code ha preso tutto. Brew quasi nullo: le stelle non sono installazioni |
| **CodexBar** | 22,1k | 2.279 | Nata a novembre 2025; autore con grande seguito su X (Peter Steinberger); HN quasi assente (1 punto) [12][19] | X da solo basta se l'autore ha pubblico; altrimenti serve HN |
| **Happy** (client Claude Code con voce) | 24,0k | — | Mobile e web, voce in tempo reale, cifratura [2] | La voce per Claude Code ha domanda vera |
| **Crystal → Nimbalyst** (Sessioni in worktree) | 3,1k + 1,8k | — | Show HN 4 punti (2025-06-26) [12] | Le "Sessioni in worktree" da sole non bastano più: sono la norma (Conductor, Nimbalyst, Vibeyard) |
| **Conductor** (Melty Labs, YC; chiuso) | — | 195 | App Mac per Claude Code in worktree paralleli; recensioni (The New Stack, Korben) [20] | Concorrente diretto sulle Sessioni, non open source |
| **Ollama app** | — | 4.253 | Post sul blog e HN 560 punti (2025-07-30) [12][21] | Un'azienda con pubblico lancia con un post; non è un modello per un singolo |
| **Kiro**, **Zed** | 91k (Zed) | 399 / 4.272 | HN 1.063 punti per Kiro (2025-07-14); Zed open source con aziende dietro [12] | Fuori scala: utili solo come riferimento di cosa fa un picco HN |
| **Raycast extensions** | 7,8k | 4.338 (Raycast) | Store dentro l'app, contributi via PR | Idea per dopo: estensione Raycast "Chiedi a Bubo" come canale |

Cosa emerge:

1. **HN è il moltiplicatore** per chi non ha già pubblico: tutti i casi sopra 15k stelle senza un'azienda dietro hanno un post HN sopra 150 punti.
2. **Il posto in cima si tiene con la manutenzione**: Ice (archiviato) è superato da Thaw; Spectacle da Rectangle.
3. **Le stelle non sono installazioni**: opcode ha 22k stelle e 32 installazioni brew al mese; Rectangle e Maccy ne hanno 5k.
4. **Il segmento Claude Code nel 2026** è affollato: awesome-claude-code ha una sezione "Session Monitors" e "Usage & Cost" con decine di app Mac native [3]. Bubo deve stare nella sezione "Alternative Clients" o "Remote Control, Notifications & Voice I/O", non tra i monitor.

## Canali

| Canale | Requisiti | Quando | Asset | Atteso (dai casi) |
|---|---|---|---|---|
| **Show HN** | Si prova subito, senza registrazione; il maker risponde nel thread; niente richieste di voto; non "quickly-generated one-offs" [1] | Giorno T, martedì–giovedì, mattina di New York (pratica comune, non regola) | Titolo descrittivo, link al repo (non a una landing), primo commento del maker | 0–670 punti; sopra 100 → Trending |
| **X** | — | Giorno T, poi a ogni release | Video 30–60 s con audio, thread "come l'hanno costruita gli agenti" | Dipende dal seguito; leva per CodexBar |
| **Reel** (Instagram, TikTok, YouTube Shorts) | Verticale 9:16 | Giorno T e ogni settimana | 15–30 s: Orb che ascolta, cambia forma, risponde | Richiesto dalla #414; poco misurato per app Mac |
| **r/ClaudeAI** | Karma ≥ 50 per il feed, altrimenti megathread "Built with Claude" (regola 7) [9] | T+1 | Video + spiegazione tecnica | Pubblico giusto, molto rumore |
| **r/macapps** | Feed principale: 1+ anno di storia e 100+ stelle, o sviluppatore App Store; sennò megathread "App Pile" in formato PCP (Problema, Confronto, Prezzo); le app di dettatura vanno sempre nel megathread [8] | T+2, nel megathread | Testo PCP, confronto con Claude desktop e Conductor | Basso finché Bubo è nuovo; il feed tra un anno |
| **Product Hunt** | Lancio alle 00:01 PT, giorni feriali [10] | T+7 (non lo stesso giorno di HN) | Galleria 1270×760, video, primo commento | Secondario: dominato da AI SaaS nel 2026 |
| **awesome-claude-code** (55k stelle) | 14 giorni dal primo commit con sviluppo attivo **o** 100 stelle; un solo suggerimento per volta; modulo web, scritto da un umano, niente PR, niente `gh`; descrizione in una riga, senza emoji né tono pubblicitario [3] | Dal 2026-10-13 (primo commit 2026-09-29) | Una riga descrittiva | Badge "Mentioned in Awesome Claude Code"; il curatore avverte che è un premio, non un canale |
| **awesome-mac** (115k) | PR, una frase, ordine alfabetico, voce sincronizzata in 4 README (en, zh, ja, ko) [11] | T+3 | Riga + icona open source | Traffico costante, basso |
| **open-source-mac-os-apps** (51k) | PR su `applications.json` con icona e screenshot; README in inglese; commit recenti; licenza [22] | T+3 | Icona, 2 screenshot, sito | Traffico costante, basso |
| **Homebrew tap proprio** (`mgiuditta/homebrew-tap`) | Nessuna soglia | Giorno T | `brew install --cask mgiuditta/tap/bubo` | Riga di installazione nel README da subito |
| **Homebrew cask ufficiale** | 225 stelle se lo propone il proprietario (75 se un altro); deve passare Gatekeeper; deve funzionare sull'ultima macOS [4][5]; `auto_updates true` con Sparkle | A 225 stelle | Cask con `depends_on macos: ">= :tahoe"`, `arch: arm64` (come Thaw [7]) | Installazioni misurabili in `formulae.brew.sh` |
| **Newsletter** (Console.dev, Changelog News, TLDR, iOS Dev Weekly, MacStories) | Console.dev: per sviluppatori, provabile in autonomia, mantenuto, nessun danno alla privacy [23] | T+3 → T+14 | Mail di 5 righe con video | 1–2 uscite realistiche |
| **Stampa Mac** (9to5Mac, MacG, iFun, Softpedia) | — | Dopo la prima stabile | Comunicato breve, screenshot | Thaw ci è arrivato [16] |
| **MacUpdate, AlternativeTo, Softpedia** | Scheda gratuita | T+7 | Scheda | SEO e coda lunga |
| **Post tecnico** ("Come 444 commit di agenti hanno costruito un'app Mac") | Normale submission HN, non Show HN | T+21 o più | Articolo con dati, ADR, errori | Secondo picco; Show HN non si ripete |

## Piano a fasi

### Fase 0 — Prerequisiti (da ora, in parallelo a #220)

- [ ] **Release**: #220 (Developer ID, chiavi, `bubo-releases`) → `v0.1.0-beta.1` (#229). Senza, niente fase 1.
- [ ] **Decisione su Homebrew**: tap proprio dal giorno T (oggi "fuori dalla v1" nella spec 27).
- [ ] **Metadati del repo**: descrizione ("Native Mac companion for Claude Code: a talking Metal orb, parallel agent sessions in git worktrees, a 3D galaxy of your project."), topic (`macos`, `swift`, `swiftui`, `metal`, `claude-code`, `voice-assistant`, `ai-agents`, `git-worktree`, `menubar-app`), homepage, social preview 1280×640.
- [ ] **README**: requisiti e "Install" sopra la piega (`brew install --cask …` e DMG); video di 30–60 s con voce e Sessioni dopo la GIF; una riga su cosa esce dal Mac (solo `claude` e i provider scelti); badge di release e licenza.
- [ ] **Sito**: una pagina su GitHub Pages con video, tre funzioni, installazione, privacy. Dominio da decidere (`bubo.app` è di altri).
- [ ] **Asset**: video orizzontale 60 s (X, sito, PH), reel verticale 20 s, 5 screenshot 2× (Orb, Panel, Sessioni con diff, Galassia, Impostazioni), galleria PH 1270×760, icona.
- [ ] **Community**: Discussions accese, template di issue (bug, idea), 10 issue `good first issue`, `CONTRIBUTING.md` breve in inglese, `SECURITY.md`.
- [ ] **Testi pronti**: titolo Show HN (es. "Show HN: Bubo – a native Mac voice companion for Claude Code, built by Claude agents"), primo commento del maker (perché, come, cosa non fa, requisiti), thread X, testo PCP per r/macapps, riga per le liste.
- [ ] **Prova a freddo**: 5 persone installano dal DMG su un Mac pulito e arrivano alla prima risposta (misura dei 60 secondi, #205). Gli intoppi vanno chiusi prima del giorno T.

### Fase 1 — Semina (T−14 → T−1)

- [ ] 5–10 beta tester da X e Discord di Claude Code; issue e feedback pubblici.
- [ ] Build in public su X: 3–4 post brevi (clip dell'Orb, una forma per volta; la tabella dei commit).
- [ ] Karma Reddit dell'account ≥ 50 con partecipazione vera a r/ClaudeAI e r/macapps (non promozione).
- [ ] Controllo di nomi e marchi: nessun "Claude" nel nome dell'app né nelle icone; "for Claude Code" va bene nel testo.

### Fase 2 — Lancio (giorno T, martedì o mercoledì)

- [ ] Release `v0.1.0` (o beta pubblica dichiarata) e tap Homebrew attivi la sera prima.
- [ ] Show HN alle 8–9 di New York (14–15 in Italia); primo commento subito; risposte per tutta la giornata.
- [ ] Video su X e reel nello stesso momento, con link al repo.
- [ ] Nessuna richiesta di voto, a nessuno [1].
- [ ] Monitorare issue: correzioni rapide con release `0.1.1` entro 48 ore se servono.

### Fase 3 — Onde (T+1 → T+14)

| Giorno | Azione |
|---|---|
| T+1 | r/ClaudeAI (feed se karma ≥ 50, altrimenti megathread) |
| T+2 | r/macapps, megathread "App Pile", formato PCP |
| T+3 | PR su awesome-mac e open-source-mac-os-apps; mail a Console.dev, Changelog, TLDR |
| T+7 | Product Hunt (00:01 PT); MacUpdate, AlternativeTo |
| ≥ 2026-10-13 | awesome-claude-code dal modulo web, a mano |
| a 225 stelle | PR del cask in `Homebrew/homebrew-cask` |

### Fase 4 — Sostegno (mese 2 →)

- [ ] Release ogni 2–4 settimane con note leggibili e una clip per release.
- [ ] Post tecnico su "come gli agenti hanno costruito Bubo" (dati, ADR, errori, review) come submission normale su HN e su blog.
- [ ] Un reel a settimana: una forma dell'Orb, una domanda vera, un caso d'uso.
- [ ] Rispondere alle issue entro 48 ore; etichette di triage già pronte.
- [ ] Estensione Raycast o Comando rapido come canali secondari.
- [ ] Rivalutare r/macapps feed principale a 1 anno di storia.

## Metriche

| Metrica | Fonte | T+7 | T+30 | T+180 |
|---|---|---|---|---|
| Stelle | GitHub | 300 | 1.000 | 5.000 |
| Punti Show HN | HN | ≥ 100 (Trending) | — | — |
| Giorni in GitHub Trending (Swift, giornaliero) | github.com/trending/swift | ≥ 2 | ≥ 3 | — |
| Download DMG | `download_count` degli asset di `bubo-releases` (API REST) | 500 | 1.500 | 10.000 |
| Installazioni brew | `formulae.brew.sh` (solo cask ufficiale) | — | — | ≥ 500 al mese |
| Issue aperte da terzi / PR esterne | GitHub | 20 / 2 | 50 / 10 | — |
| Liste awesome | — | 1 | 3 | 3 |
| Rapporto download/stelle | calcolato | ≥ 1 | ≥ 1,5 | ≥ 2 |

Il rapporto download/stelle distingue l'interesse dall'uso (opcode: 22k stelle, 32 installazioni brew al mese). I numeri di T+30 stanno sotto Ice (2.328 stelle in 7 giorni) e sopra i lanci falliti del 2026 (1–2 punti): sono un obiettivo, non una previsione.

## Rischi

- **Lancio senza release**: un repo con "coming soon" brucia HN e Reddit per sempre (Show HN non si ripete [1]). Niente fase 2 prima di #220.
- **Reazione a "costruita da agenti"**: su HN e r/macapps l'etichetta "vibe-coded" affonda un post. Parlare di metodo (spec, ADR, 1.630 test, review), mostrare errori e decisioni umane, non solo numeri di velocità.
- **Saturazione Claude Code**: chi legge "GUI per Claude Code" pensa a opcode, Conductor, Nimbalyst. Il titolo deve dire voce e Orb, non Sessioni.
- **Pubblico ristretto**: macOS 26 + Apple Silicon + `claude` loggato. Detto in alto evita commenti "non parte".
- **Primo avvio che fallisce** (CLI mancante, permessi del microfono, Gatekeeper): un solo bug di installazione domina il thread. Prova a freddo con 5 persone.
- **Privacy e voce**: microfono e accesso a file attirano domande (vedi Stats). Pagina "cosa esce dal Mac" pronta.
- **Marchi e termini di Anthropic**: niente logo, niente "Claude" nel nome; uso dell'abbonamento solo tramite la CLI ufficiale (già nel README).
- **Nome**: `bubo.app` è di un'altra azienda; Bubo è un nome già usato (BuboGPT, bubo-rss). Cercare "Bubo Mac" deve portare al repo: sito e topic aiutano.
- **Carico di supporto dopo il picco**: decine di issue in due giorni. Template, etichette e risposte rapide; gli agenti possono fare il triage, la risposta resta umana.
- **Manutenzione**: Ice ha perso il posto quando si è fermato. Il piano vale solo con release regolari.
- **Tempi di Apple**: notarizzazione oltre i 15 minuti o certificato non pronto spostano il giorno T; non annunciare una data prima della release in mano.

## Domande per il fondatore

1. Il giorno T dipende da #220: quando puoi fare il certificato Developer ID e le chiavi?
2. Lanci una **beta pubblica** (`0.1.0-beta`) o aspetti la prima stabile? Show HN accetta lavori presto ma usabili [1].
3. **Homebrew**: tap proprio dal giorno T al posto di "fuori dalla v1"?
4. **Volto e voce**: ci sei tu nel video e nel reel, o solo l'app? I lanci con il maker in prima persona vanno meglio su HN e X.
5. **Account**: quale account X usi, quanti follower ha? Hai karma Reddit ≥ 50?
6. **Dominio e sito**: compri un dominio (quale?) o resta GitHub Pages?
7. **Racconto**: il gancio principale è "l'Orb che parla" o "costruita da agenti"? Questa ricerca propone il primo nel titolo e il secondo nel primo commento.
8. **Product Hunt**: lo vuoi? Costa una giornata intera di risposte.
9. **Budget**: zero (solo canali organici) o qualcosa per video e dominio?
10. **Donazioni**: GitHub Sponsors sì o no al lancio?
11. Lingua dei canali: tutto in inglese, con un post italiano (r/italy, X italiano) come extra?

## Ticket che ne derivano (da aprire dopo le risposte)

- Metadati del repo: descrizione, topic, homepage, social preview (`ready-for-human`, impostazioni GitHub).
- README per il lancio: Install, requisiti in alto, video, privacy (`ready-for-agent` dopo #220).
- Video dimostrativo e reel: registrazione reale di voce e Sessioni (`ready-for-human`).
- Sito su GitHub Pages (`ready-for-agent`).
- Tap Homebrew `mgiuditta/homebrew-tap` e cask aggiornato dal workflow di release (`ready-for-agent`, dopo #221).
- Community: Discussions, template di issue, `CONTRIBUTING.md`, `SECURITY.md`, `good first issue` (`ready-for-agent`).
- Correggere la spec 27 ("codice privato" non vale più) (`ready-for-agent`).
- Kit di lancio: testi di Show HN, X, PCP, liste (`ready-for-agent`, revisione umana).
- Cask ufficiale Homebrew a 225 stelle (`ready-for-human`).

## Fonti

Regole dei canali
1. Hacker News, "Show HN Guidelines" — https://news.ycombinator.com/showhn.html ; "Hacker News Guidelines" — https://news.ycombinator.com/newsguidelines.html
2. GitHub, ricerca repository (stelle e date di creazione al 2026-10-02) — https://github.com/search?type=repositories
3. awesome-claude-code, `CONTRIBUTING.md` e `README.md` (sezioni "Alternative Clients", "Remote Control, Notifications & Voice I/O", "Session Monitors") — https://github.com/hesreallyhim/awesome-claude-code/blob/main/CONTRIBUTING.md
4. Homebrew, "Package Acceptance Policy", Notability — https://docs.brew.sh/Package-Acceptance-Policy
5. Homebrew, "Acceptable Casks" — https://docs.brew.sh/Acceptable-Casks
6. Homebrew 5.0.0, note di rilascio (cask senza firma e notarizzazione deprecati, disattivati a settembre 2026) — https://brew.sh/2025/11/12/homebrew-5.0.0 ; Workbrew, "What Homebrew 5.0.0 means for your Mac fleet" — https://workbrew.com/blog/what-homebrew-5-0-0-means-for-your-mac-fleet
7. Homebrew, analytics delle installazioni dei cask a 30 giorni — https://formulae.brew.sh/api/analytics/cask-install/30d.json ; cask di Thaw — https://formulae.brew.sh/api/cask/thaw.json
8. r/macapps, megathread "The App Pile" (giugno 2026) e regole Trust/Transparency, via mirror Redlib — https://www.reddit.com/r/macapps/
9. r/ClaudeAI, "Built with Claude — Project Showcase Megathread" e regola 7 (aprile 2026), via mirror Redlib — https://www.reddit.com/r/ClaudeAI/
10. Corbado, "How to launch a developer tool on Product Hunt" — https://www.corbado.com/blog/launch-developer-tool-product-hunt ; Pinggy, "Best Product Hunt alternatives 2026" — https://pinggy.io/blog/best_producthunt_alternatives/
11. awesome-mac, `docs/CONTRIBUTING.md` — https://github.com/jaywcjlove/awesome-mac/blob/master/docs/CONTRIBUTING.md

Casi studio
12. Hacker News via API Algolia (punti e commenti): Ice https://news.ycombinator.com/item?id=40605532 ; Stats https://news.ycombinator.com/item?id=42881342 ; Maccy 2019 https://news.ycombinator.com/item?id=20769814 e 2022 https://news.ycombinator.com/item?id=31867121 ; AltTab https://news.ycombinator.com/item?id=21253850 ; Claudia https://news.ycombinator.com/item?id=44933255 ; Crystal https://news.ycombinator.com/item?id=44388269 ; CodexBar https://news.ycombinator.com/item?id=49596393 ; Ollama app https://news.ycombinator.com/item?id=44739632 ; Kiro https://news.ycombinator.com/item?id=44560662
13. GitTrends, 9 giugno 2024 (Ice +2.328 stelle in 7 giorni) — https://gitstars.substack.com/p/gittrends-june-9-2024
14. Show HN di app native per Claude Code nel 2026: Poirot https://news.ycombinator.com/item?id=47165573 ; AI Usage https://news.ycombinator.com/item?id=49080227 ; Claude Rate Widget https://news.ycombinator.com/item?id=47034148
15. Mac Power Users, "Is anyone else having trouble with the Ice menu bar manager?" — https://talk.macpowerusers.com/t/is-anyone-else-having-trouble-with-the-ice-menu-bar-manager/45789 ; Thaw — https://github.com/thaw-app/Thaw
16. MacG, "Thaw, un nouvel utilitaire…" (febbraio 2026) — https://www.macg.co/logiciels/2026/02/thaw-un-nouvel-utilitaire-pour-desencombrer-la-barre-des-menus-de-macos-306843 ; iFun, "Thaw 2.0 ist da" — https://www.ifun.de/thaw-2-0-ist-da-freier-menueleistenmanager-fuer-macos-26-288052/
17. Rectangle, sito ufficiale — https://rectangleapp.com/
18. It's FOSS, "Claudia: An Open Source GUI for Claude AI Code Development" — https://itsfoss.com/news/claudia/ ; Analytics India Magazine, "YC startup unveils open source graphical interface for Claude Code" — https://analyticsindiamag.com/ai-news-updates/yc-startup-unveils-open-source-graphical-interface-for-claude-code
19. CodexBar — https://github.com/steipete/CodexBar ; RuntimeWire, "CodexBar expands to 80 AI providers" (settembre 2026) — https://runtimewire.com/article/codexbar-expands-to-80-ai-providers
20. Y Combinator, Conductor — https://ycombinator.com/companies/conductor ; The New Stack, "A hands-on review of Conductor" — https://thenewstack.io/a-hands-on-review-of-conductor-an-ai-parallel-runner-app/
21. Ollama, "Ollama's new app" (30 luglio 2025) — https://ollama.com/blog/new-app
22. open-source-mac-os-apps, `CONTRIBUTING.md` — https://github.com/serhii-londar/open-source-mac-os-apps/blob/master/CONTRIBUTING.md
23. Console.dev, "Selection Criteria" — https://console.dev/selection-criteria

Repository Bubo
- `README.md`, `docs/brief.md`, `CONTEXT.md`, `docs/features/INDEX.md`, `docs/features/27-rifinitura-aggiornamenti.md` (stato al commit `5f0de80`).
