# 27 — Rifinitura premium e aggiornamenti automatici

Ticket: [#183](https://github.com/mgiuditta/bubo/issues/183) (ricerca), [#188](https://github.com/mgiuditta/bubo/issues/188) (decisioni), [#186](https://github.com/mgiuditta/bubo/issues/186) (budget di prestazioni), [#187](https://github.com/mgiuditta/bubo/issues/187) (onboarding). Mappa: [#178](https://github.com/mgiuditta/bubo/issues/178).
Ricerca del 2026-09-30 su Sparkle **2.10.0** (13/09/2026), App Store Review Guidelines e documentazione Apple alla stessa data, Agent SDK TS **0.3.285**, CLI `claude` **2.1.285**, runner GitHub `macos-26-arm64` **20260907.0351.1**. Misure su macOS 26.7, Xcode 26.6, Bun 1.3.10. Ricerca completa: [`27-distribuzione.md`](https://github.com/mgiuditta/bubo/blob/research/27-distribuzione/docs/features/research/27-distribuzione.md) sul branch `research/27-distribuzione`.

> **Nota sulla ricerca.** È scritta prima delle decisioni e in alcuni punti è superata. Il repository privato non è più un problema: release e appcast stanno in un repository pubblico separato, `mgiuditta/bubo-releases`, e l'appcast sta su GitHub Pages, non in una release fissa né nel repository del codice ([#188](https://github.com/mgiuditta/bubo/issues/188)). Sparkle non chiede il permesso al secondo avvio: il controllo automatico è acceso senza chiedere. Niente finestre di Sparkle per gli aggiornamenti trovati da soli: un promemoria nell'HUD. Il ponte parte dal solo `cs.allow-jit`, non dai cinque entitlement della guida di Bun né dai tre del `claude` di Anthropic. Per il `claude` dell'utente c'è una versione minima dichiarata da Bubo e nessuna massima. Homebrew Cask esce dalla v1. Valgono la Mappa e la Specifica qui sotto.

In sintesi: Bubo si distribuisce fuori dal Mac App Store, che è escluso da quattro regole indipendenti. Il formato è un DMG firmato Developer ID, notarizzato e graffato, costruito in CI a ogni tag. Gli aggiornamenti passano da **Sparkle 2**: firma EdDSA, delta, un solo appcast con la stabile e la beta, rilascio graduale in una settimana. Bubo non interrompe mai il lavoro: scarica in background, installa all'uscita e, se l'utente vuole riavviare subito, aspetta che nessuna Sessione lavori. Il rischio vero non è Sparkle ma il `claude` dell'utente, che si aggiorna da solo 27 volte al mese: Bubo dichiara una versione minima, attiva le funzioni in base alle `capabilities` e ogni notte prova il ponte contro l'ultimo `claude`. La "rifinitura premium" non è una sensazione: è una checklist di otto criteri misurabili, parte della definizione di "fatto" di ogni ticket con interfaccia, più un audit completo prima della prima beta.

## Ricerca

### Mac App Store: escluso

| Regola | Testo | Cosa tocca in Bubo |
|---|---|---|
| **2.4.5(i)** [1] | "They must be appropriately sandboxed" | Tutta l'app: i figli ereditano la sandbox (sotto). |
| **2.4.5(vii)** [1] | "They must use the Mac App Store to distribute updates" | Sparkle. |
| **2.4.5(iv)**, **2.5.2** [1] | Niente codice scaricato che aggiunge o cambia funzioni | Plugin (feature 20), MCP scaricati, `claude` stessa. |
| **2.5.1** [1] | "Apps may only use public APIs" | Il disclaim di [ADR 0005](../adr/0005-claude-senza-i-permessi-tcc-di-bubo.md) è una SPI privata. |

Un processo in sandbox che avvia un figlio gli passa sempre la sua sandbox [2][3]. `claude`, le shell e i dev server girerebbero nella sandbox di Bubo: niente scrittura nel Progetto senza segnalibri, niente `~/.claude`. Basterebbe uno solo dei quattro motivi. Claude desktop e Cursor sono Electron e si aggiornano con **Squirrel.framework** fuori dallo Store (verificato nei bundle installati).

### Sparkle 2

- **Stato** [4]. 2.10.0 del 13/09/2026, rilasci mensili, sei correzioni di sicurezza tra maggio e agosto 2026 (symlink nei delta, connessione all'installer, pacchetti con firma non valida). Da 2.10 serve macOS 12+. Si installa con SPM [5].
- **Swift 6** [6]. Dalla 2.9 `SPUUpdater` e `SPUStandardUpdaterController` sono `NS_SWIFT_UI_ACTOR`, cioè `@MainActor` in Swift. Si sposa con `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` di `project.yml`. L'esempio ufficiale usa `ObservableObject` e KVO su `canCheckForUpdates` [7].
- **macOS 26** [8]. Unico bug noto: bundle ID che finiscono in `.app`, corretto in 2.9.3. `com.mgiuditta.bubo` non ricade nel caso.
- **Firma EdDSA** [5][9][10][11]. `generate_keys` mette la chiave privata nel Portachiavi; `-x` la esporta. La pubblica va in `SUPublicEDKey`. In CI la privata passa da stdin (`--ed-key-file -`). Con lo stesso Developer ID si può cambiare chiave in un passaggio. Dal 2.6.4 Sparkle fa anche una scansione Gatekeeper dell'aggiornamento [12].
- **Delta** [13][10]. `generate_appcast` crea 5 delta per default e tiene 3 versioni per ramo. Se il delta non si applica, Sparkle scarica il pacchetto completo.
- **Canali** [9][6]. `<sparkle:channel>beta</sparkle:channel>` sull'`<item>`; l'updater vede solo i canali di `allowedChannels(for:)`, più il predefinito. Un solo appcast per stabile e beta.
- **Altri controlli dell'appcast** [9]: `phasedRolloutInterval` (7 gruppi, non vale per i critici né per il controllo manuale), `criticalUpdate`, `minimumSystemVersion`, `hardwareRequirements` (`arm64`, 2.9+), `minimumAutoupdateVersion`, note in Markdown (2.9+), feed firmato (`SURequireSignedFeed`, 2.9+).
- **Installazione con l'app aperta** [16][6][17]. `SUAutomaticallyUpdate` scarica in background e installa all'uscita. `updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)` dà all'app il blocco per installare quando vuole. `updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)` ritarda il riavvio. I "gentle reminders" (`supportsGentleScheduledUpdateReminders`) lasciano all'app il promemoria.
- **Senza sandbox niente XPC** [18]. I servizi XPC di Sparkle si tolgono dal framework.

### Alternative

| Opzione | Esito |
|---|---|
| Squirrel.Mac | Ultima release 0.3.2 del 2017 [19]. Ha senso solo dentro Electron. |
| Homebrew Cask | Canale di installazione, non updater. Con `auto_updates true` convive con Sparkle [20]. |
| Updater fatto in casa | Rifarebbe firma, verifica, sostituzione atomica e riavvio: tutto ciò che Sparkle 2.9.x ha appena irrobustito. |

### Firma e notarizzazione in CI

- **Requisiti** [15]: Developer ID su ogni eseguibile, hardened runtime, timestamp sicuro, niente `get-task-allow`. `project.yml` ha già `ENABLE_HARDENED_RUNTIME: YES` e `Developer ID Application` in Release.
- **Ordine** [21][22][14]: niente `--deep`; si firma dall'interno verso l'esterno, ogni eseguibile con i suoi entitlement; gli strumenti vanno in `Contents/MacOS/` o `Contents/Helpers/`; si notarizza **solo il contenitore esterno** (il DMG) e lo si graffa.
- **Comandi** [15][14]: `codesign … --timestamp` sul DMG, `xcrun notarytool submit … --key/--key-id/--issuer --wait`, `notarytool log` (anche se riesce), `xcrun stapler staple`. Il 98% delle notarizzazioni finisce entro 15 minuti; limite di 75 al giorno.
- **DMG** [14][15]: UDIF sola lettura UDZO, firmato Developer ID; niente compressione spinta.
- **Sparkle dopo lo stapling**: lo stapling cambia il file, quindi la firma EdDSA si calcola dopo (deduzione dall'ordine delle operazioni).
- **Runner** [23][24]: `macos-26` con Xcode 26.6 predefinito; Bun e XcodeGen vanno installati nel job. Il certificato `.p12` si importa in un portachiavi temporaneo. Un'app Developer ID senza capacità speciali non ha bisogno di profilo di provisioning.

### GitHub Releases come host

- `releases/latest/download/<file>` punta sempre all'ultima release **non prerelease** [25][26]: un appcast a canali non può stare lì.
- Fino a 1.000 asset per release, 2 GiB per file, nessun tetto di traffico [27].
- Gli asset di un repository privato non si scaricano senza autenticazione.

### Il ponte `bun`

Il ponte (`bun build --compile`, ~61 MB) sta nel bundle e si aggiorna con l'app. Sotto hardened runtime, **senza `cs.allow-jit`** non va in crash ma è **~50 volte più lento** (misura: 1,47 s contro 0,03 s su 5×10⁷ iterazioni) [28][29][30]. È un guasto silenzioso. Il `claude` di Anthropic, anch'esso un binario Bun, ha `allow-jit`, `allow-unsigned-executable-memory` e `disable-library-validation`. `allow-unsigned-executable-memory` espone a vulnerabilità note [31]. Il ponte non deve includere i ~224 MB del `claude` incorporato nell'SDK: Bubo usa quello dell'utente ([ADR 0003](../adr/0003-login-con-la-cli-claude-dell-utente.md), `pathToClaudeCodeExecutable`) [33].

### Il `claude` dell'utente

- L'SDK segue il binario che incorpora (0.3.285 ↔ 2.1.285) e **non documenta** compatibilità con un `claude` di versione diversa [33][34].
- Il `claude` nativo si aggiorna da solo in background; il nuovo binario vale al prossimo avvio. Canali `latest` e `stable` [35].
- Ritmo misurato: **27 rilasci** di `claude` e 27 dell'SDK dal 31/08 al 29/09/2026.
- Strumenti: `system/init` porta `claude_code_version` e `capabilities` ("feature-detect instead of version-sniffing", insieme aperto, assente sulle CLI vecchie) [34]. `claude --version` risponde in ~0,01 s ([#182](https://github.com/mgiuditta/bubo/issues/182)).

## Il meglio da battere

Nessun concorrente è un'app nativa con lo stesso lavoro: Claude desktop e Cursor sono Electron con Squirrel, un updater fermo al 2017. Le app native fuori dallo Store usano quasi tutte Sparkle con la sua interfaccia standard: una finestra "È disponibile una nuova versione" che compare mentre si lavora. Nessuno dichiara quale versione minima della CLI serve, né cosa succede se la CLI si aggiorna sotto l'app. Criteri candidati usciti dalla ricerca (quelli decisi sono nella Specifica):

1. **Mai interrotto**: nessuna finestra non chiesta, nessun riavvio con una Sessione al lavoro.
2. **Sempre verificabile**: ogni release firmata, notarizzata, graffata e firmata EdDSA; appcast firmato.
3. **Ritiro rapido**: una versione difettosa smette di arrivare in pochi minuti, senza downgrade forzati.
4. **CLI dell'utente sotto controllo**: una versione troppo vecchia si dice prima di partire; una troppo nuova che rompe il ponte si scopre in una notte.
5. **Ponte veloce anche firmato**: il rallentamento di 50× non passa inosservato.
6. **Rifinitura misurata**: stati, errori, animazioni, icona, menu, accessibilità, stringhe e prestazioni controllati con criteri numerici, non a occhio.

## Rischi e casi limite

- **Ponte lento in silenzio**: basta un entitlement perso in una modifica della firma. Serve un test di velocità, non solo di funzionamento.
- **`claude` più nuovo che cambia il protocollo**: 27 rilasci al mese e nessuna compatibilità dichiarata [33][34].
- **URL sbagliati nell'appcast**: `generate_appcast` usa un solo `--download-url-prefix`, ma ogni versione sta nella sua release. Le voci vecchie vanno riscritte con il loro tag.
- **Firma EdDSA prima dello stapling**: la firma non vale più e Sparkle rifiuta l'aggiornamento.
- **Chiave EdDSA persa**: senza, nessun aggiornamento futuro è installabile. Serve una copia fuori dalla CI; con lo stesso Developer ID si ruota [11].
- **Token di pubblicazione rubato**: chi lo ha può riscrivere l'appcast. Feed firmato ed EdDSA sui pacchetti fanno sì che non possa far installare niente.
- **Certificato Developer ID scaduto o revocato**: le release si fermano; le copie già installate restano valide.
- **Limite di 75 notarizzazioni al giorno** e code di Apple oltre i 15 minuti.
- **Immagine del runner che cambia Xcode**: `macos-latest` migra in 1–2 mesi [23].
- **Riavvio con una Sessione al lavoro o un'Esecuzione in corso** (feature 19): il lavoro si interromperebbe.
- **Utente che esce dalla beta**: non deve mai ricevere una versione più vecchia di quella che ha.
- **Downgrade a mano** con un DMG vecchio: uno store con uno schema più nuovo non deve corrompersi.
- **App avviata dal DMG montato o dalla cartella Download** (traslocazione di Gatekeeper): Sparkle non può sostituirla.
- **Utente senza diritti di scrittura su `/Applications`**: l'installer di Sparkle chiede la password di un amministratore.
- **Rilascio graduale e controllo manuale**: chi preme "Controlla aggiornamenti…" riceve subito la versione, anche se il suo gruppo non è ancora partito [9].
- **Promemoria durante l'onboarding**: un avviso prima della prima risposta ruba i 60 secondi della feature 26.
- **Rifinitura a fine progetto**: se la checklist arriva solo alla fine, genera cento ticket. Va nella definizione di "fatto" di ogni ticket con interfaccia.

## Mappa

Architettura comune in [INDEX.md](INDEX.md). Si appoggia sul ponte agente con disclaim ([#66](https://github.com/mgiuditta/bubo/issues/66)), sul rilevamento di `claude` dell'onboarding (26, [#187](https://github.com/mgiuditta/bubo/issues/187)), sulle Sessioni (01), sulle Automazioni (19), sulla Palette (14) e sui budget di prestazioni (25, [#186](https://github.com/mgiuditta/bubo/issues/186)).

### Distribuzione e firma (deciso)

Fonte: mappa [#178](https://github.com/mgiuditta/bubo/issues/178), ricerca [#183](https://github.com/mgiuditta/bubo/issues/183).

- **Fuori dal Mac App Store**, per i quattro motivi della ricerca.
- **Developer ID + hardened runtime + notarizzazione + DMG**, costruito solo in CI su runner `macos-26`.
- **Firma dall'interno verso l'esterno**, senza `--deep`: ponte e lanciatore del terminale (ADR 0005) con i loro entitlement, Sparkle, app, DMG. Si notarizza il solo DMG, lo si graffa, poi si firma con EdDSA.
- **Sparkle 2.10** via SPM, senza servizi XPC (app non in sandbox).

### Hosting e Canali (deciso)

Fonte: [#188](https://github.com/mgiuditta/bubo/issues/188).

- **Repository pubblico separato `mgiuditta/bubo-releases`**. Il codice resta privato in `mgiuditta/bubo`.
  - Ogni versione è una GitHub Release con tag `vX.Y.Z` (o `vX.Y.Z-beta.N`): DMG e delta come asset.
  - `appcast.xml` a URL fisso su GitHub Pages dello stesso repository. Non su `releases/latest`, che non punta mai a una beta.
  - Il CI di `bubo` pubblica con un token dedicato, valido solo su `bubo-releases`.
- **Un solo appcast** con la stabile e le voci `sparkle:channel beta`.
- **Canale** (glossario): in Impostazioni › Aggiornamenti c'è "Ricevi le beta", spento di default. Acceso, l'updater ammette il canale `beta`. Chi lo spegne resta sulla versione che ha e aspetta la stabile successiva: nessun downgrade.

### Controllo, installazione e riavvio (deciso)

- **Controllo automatico acceso senza chiedere**, ogni 24 ore (`SUEnableAutomaticChecks` YES, `SUScheduledCheckInterval` 86.400).
- **Download in background e installazione all'uscita** (`SUAutomaticallyUpdate` YES). Controllo e download si spengono in Impostazioni › Aggiornamenti.
- **Nessuna finestra di Sparkle per ciò che trova da solo.** Un promemoria discreto nell'HUD: "Aggiornamento pronto · Riavvia".
  - Contenitore acromatico (ADR 0004): testo `textPrimary`, filo `lineStrong`. Mai `attention`, che è riservato ad "Attende te" e alle Richieste di permesso.
- **Riavvia aspetta il lavoro**: se una Sessione è in Attività Lavora o un'Esecuzione è in corso, il riavvio si rimanda (`shouldPostponeRelaunch`) e parte da solo quando l'ultima finisce.
- **Nessun avviso prima della prima risposta** (onboarding, feature 26). Il controllo gira, il promemoria no.

### Gradualità e ritiro (deciso)

- **Stabile**: `phasedRolloutInterval` di 1 giorno, cioè 7 gruppi in una settimana.
- **Beta**: senza gradualità.
- **`criticalUpdate`** solo per le correzioni di sicurezza.
- **Solo in avanti**:
  - la versione difettosa si toglie dall'appcast; questo ferma anche i gruppi del rilascio graduale non ancora partiti;
  - esce una correzione con numero più alto;
  - i DMG precedenti restano scaricabili a mano da `bubo-releases`;
  - le migrazioni degli store sono **solo additive**: un downgrade a mano non corrompe i dati.
- Downgrade dall'app: fuori dalla v1.

### Versioni e note di rilascio (deciso)

- **`CFBundleShortVersionString`** in semver (`1.2.0`). Il suffisso `-beta.N` sta solo nel tag e nel nome della release.
- **`CFBundleVersion`** = numero monotono del CI. È quello che Sparkle confronta.
- **Il tag `vX.Y.Z` avvia il workflow di release**; `vX.Y.Z-beta.N` fa una release beta.
- **Fonte delle note**: `CHANGELOG.md`. `generate_appcast` le incorpora nell'appcast in Markdown.
- **Scheda "Novità"** nell'HUD al primo avvio dopo un aggiornamento: al massimo 3 punti, chiudibile.
- **Lingue**: quelle del String Catalog.

### Compatibilità con il `claude` dell'utente (deciso)

- **Versione minima** dichiarata da Bubo, confrontata con `claude_code_version` dell'`init`.
- **Sotto la minima**: riquadro "Aggiorna Claude Code" con il comando; la Sessione non parte.
- **Nessuna massima**: le funzioni si attivano in base a `capabilities`.
- **CI notturno**: smoke test del ponte contro l'ultimo `claude`. Se si rompe, esce una patch.
- **SDK aggiornato a ogni release** di Bubo.

### Entitlement del ponte (deciso)

- Si parte dal solo **`cs.allow-jit`**. Un entitlement in più entra solo quando un test dimostra che il ponte reale fallisce senza.
- Il CI controlla gli entitlement del bundle firmato (`codesign -d --entitlements`).
- Un **test di velocità** del ponte protegge dal rallentamento silenzioso di ~50×.
- La lista finale esce dalla costruzione.

### Audit di rifinitura (deciso)

Otto criteri, schermata per schermata:

1. Stati vuoto, caricamento ed errore disegnati; nessuno spinner oltre 1 s senza testo.
2. Ogni errore dice cosa è successo e cosa fare, con un'azione.
3. Animazioni Notte rispettate (contenitore 150–250 ms, solo l'Orb respira) e Riduci movimento onorato ([design-system.md](../design-system.md)).
4. Icona in tutte le misure, più il glifo della barra dei menu.
5. Menu dell'app completi, scorciatoie senza conflitti.
6. VoiceOver, tastiera e contrasto AA.
7. 0 stringhe fuori dal String Catalog, 0 traduzioni mancanti.
8. Budget di [Prestazioni: soglie e misura](https://github.com/mgiuditta/bubo/issues/186) rispettati.

Quando:

- la checklist fa parte della **definizione di "fatto"** di ogni ticket di costruzione con interfaccia;
- un **audit completo** come `task` prima della prima beta, insieme alla profilazione della 25, che genera i ticket di correzione.

### Scelte di scrittura

Non decise nelle issue; facili da cambiare.

- **Solo Apple silicon**: build `arm64`, `sparkle:hardwareRequirements arm64`, `minimumSystemVersion` 26.0 (ADR 0001; il brief parla di 60 fps su Apple Silicon).
- **Feed firmato** (`SURequireSignedFeed` YES): un token rubato non basta a riscrivere l'appcast.
- **Nessun dato inviato con il controllo**: `SUEnableSystemProfiling` resta spento. È l'unica chiamata di rete della feature, oltre al CI.
- **Aggiornamenti spenti nelle build Debug** e nelle build non firmate Developer ID.
- **Numero di build** = `github.run_number` del workflow di release.
- **Nome della release nel bundle**: chiave `BuboReleaseName` nell'Info.plist (`1.2.0-beta.3`), mostrata in Impostazioni › Aggiornamenti e in Informazioni su Bubo.
- **Verifica della minima anche prima dell'`init`**: il rilevamento della 26 (`Account/ClaudeReadiness`) legge già `claude --version` e ha l'esito "vecchia"; lo stesso numero blocca la Sessione prima che parta il prompt. L'`init` conferma a ogni Conversazione dell'agente, perché `claude` si aggiorna mentre Bubo è aperto.
- **Minima in un solo file**: `bridge/compat.json` (`minimumClaudeVersion`), letto dal ponte, dall'app e dallo smoke test. Si alza solo quando il ponte usa qualcosa di nuovo.
- **Riquadro = variante "vecchia" di `Onboarding/FixCard`** (26), usata anche fuori dall'onboarding. Comando scelto dal percorso di `claude`: `claude update` (installazione nativa, come nella 26), `brew upgrade claude-code` (Homebrew), `npm install -g @anthropic-ai/claude-code` (npm). Pulsante "Copia e apri Terminale" come nella 26. Bubo osserva il binario con FSEvents e riparte da solo; la domanda non si perde.
- **Smoke notturno** su `macos-26` con `claude` installata dall'installer nativo (ultima) e da npm (minima); un turno reale con Haiku su un repository finto. Se fallisce, apre un'issue `needs-triage` con versione e log, una sola per versione di `claude`.
- **Freschezza dell'SDK**: il workflow di release si ferma se l'SDK del ponte è indietro di più di 7 giorni rispetto all'ultimo pubblicato su npm. `scripts/bump-sdk.sh` lo aggiorna prima del tag.
- **Sezioni del CHANGELOG**: `## X.Y.Z — AAAA-MM-GG`, poi `### Novità` (al massimo 3 punti, gli stessi della scheda), `### Correzioni`, `### Sicurezza`. Una sezione Sicurezza non vuota marca l'`item` come `criticalUpdate`.
- **Un CHANGELOG per lingua**: `CHANGELOG.md` (italiano, lingua di sviluppo) e `CHANGELOG.<lingua>.md` per le altre lingue del String Catalog. La release si ferma se una lingua non ha la sezione della versione. Le note vanno nell'appcast con `xml:lang`; la scheda Novità le legge dal bundle, non dalla rete.
- **Più versioni saltate**: la scheda mostra solo i punti della versione installata, più il link "Tutte le novità" alla pagina delle release.
- **Aggiornamento critico**: stesso promemoria, con "Aggiornamento di sicurezza" nel testo e senza "Più tardi". Nessun colore di `danger`: non è un errore.
- **Promemoria anche nella barra dei menu**: voce "Riavvia per aggiornare" nel menu dell'icona, oltre alla riga nell'HUD.
- **App traslocata o avviata dal DMG**: riquadro "Sposta Bubo in Applicazioni" con il Finder aperto sulla cartella; gli aggiornamenti restano in pausa finché non si sposta.
- **Store additivi controllati**: a ogni release si salva un'istantanea dello schema di ogni store in `BuboTests/Fixtures/Schema/`; un test fallisce se una tabella, una colonna o un campo spariscono o cambiano tipo.
- **Controlli automatici della rifinitura** in `scripts/polish-check.sh`, chiamato da `scripts/check.sh` (vedi Test).

### Fuori dalla v1

- Homebrew Cask: dopo la prima stabile, con `auto_updates true`.
- Downgrade dall'app.
- Mac App Store.

### Moduli

Architettura comune in [INDEX.md](INDEX.md). Moduli nuovi:

- `Updates/UpdateController`: `@MainActor`, avvolge `SPUStandardUpdaterController`. Delegate: `allowedChannels(for:)` (beta), `willInstallUpdateOnQuit` (conserva il blocco di installazione immediata), `shouldPostponeRelaunch`, promemoria gentili. Espone lo stato osservabile: nessuno, disponibile, pronto, critico.
- `Updates/UpdatePreferences`: le tre scelte di Impostazioni › Aggiornamenti sopra `SPUUpdater` (`automaticallyChecksForUpdates`, `automaticallyDownloadsUpdates`) e "Ricevi le beta".
- `Updates/RelaunchGate`: chiede a `Sessions/` e a `Automations/` se c'è lavoro in corso; libera il riavvio quando finisce.
- `Updates/InstallLocation`: riconosce app traslocata, sul DMG o fuori da `/Applications`.
- `Updates/WhatsNew`: versione vista l'ultima volta, sezione Novità dal bundle nella lingua attiva.
- `HUD/UpdateBanner`, `HUD/WhatsNewCard`, `Settings/UpdatesSettingsView`; voce "Controlla aggiornamenti…" nel menu dell'app, nel menu della barra dei menu e nel `CommandCatalog` della Palette.
- `Agent/ClaudeCompatibility`: minima da `compat.json`, confronto semver con `claude --version` e `init.claude_code_version`, insieme di `capabilities` per le altre feature. Lo usa `Account/ClaudeReadiness` (26) per l'esito "vecchia".
- `bridge/bridge.entitlements` (solo `cs.allow-jit`), `bridge/compat.json`, smoke test in `bridge/smoke/`.
- `scripts/release/`: `build.sh`, `sign.sh`, `notarize.sh`, `dmg.sh`, `appcast.sh` (con riscrittura degli URL per tag), `yank.sh`, `verify-entitlements.sh`, `bridge-speed.sh`, `bump-sdk.sh`.
- `.github/workflows/release.yml` (sul tag), `yank.yml` (a mano), `nightly-claude.yml` (ogni notte).
- `scripts/polish-check.sh` e `.github/pull_request_template.md` con la checklist degli otto criteri.
- Riuso: ponte e `Agent/ProcessSpawner` ([#66](https://github.com/mgiuditta/bubo/issues/66)), `Account/ClaudeLocator`, `Account/ClaudeReadiness` e `Onboarding/FixCard` (26), Attività delle Sessioni (06), `AutomationScheduler` (19), `Palette/CommandCatalog` (14), `scripts/perf.sh` e test di prestazione (25).

### Flusso

1. **Release**: tag `vX.Y.Z[-beta.N]` → `release.yml` su `macos-26` → controllo della freschezza dell'SDK → ponte compilato e firmato con `bridge.entitlements` → build Release con versione e numero di build → firma dall'interno verso l'esterno → `verify-entitlements.sh` e `bridge-speed.sh` sul bundle firmato → DMG UDZO firmato → `notarytool --wait` + log → `stapler staple` → firma EdDSA → release in `bubo-releases` → `appcast.sh` (delta, note per lingua, canale, gradualità, critico, feed firmato) → Pages → controllo che ogni URL dell'appcast risponda.
2. **Sul Mac dell'utente**: ogni 24 ore Sparkle legge l'appcast → voce ammessa dal Canale e dal gruppo del rilascio graduale → download in background (delta se possibile) → `willInstallUpdateOnQuit` → promemoria nell'HUD (se c'è stata la prima risposta).
3. **Riavvia**: `RelaunchGate` → nessun lavoro? installa e riavvia : "Riavvio appena le Sessioni finiscono" → ultima Sessione Ferma o Esecuzione finita → installa e riavvia.
4. **Uscita**: Sparkle installa; alla riapertura `WhatsNew` mostra la scheda.
5. **Ritiro**: `yank.yml` con il tag → voce tolta, appcast rifirmato, release marcata "ritirata", DMG tenuto → correzione con numero più alto.
6. **Compatibilità**: `ClaudeReadiness` (26) legge `claude --version` → sotto la minima? riquadro, Sessione ferma, domanda tenuta → FSEvents sul binario → nuova verifica → la Sessione parte. A ogni `init`, stessa verifica e `capabilities` aggiornate.
7. **Notte**: `nightly-claude.yml` → ultimo `claude` e minima → smoke del ponte → rotto? issue `needs-triage` → patch.

### Casi limite

- **Aggiornamento pronto e Bubo mai chiuso per una settimana**: il promemoria resta nell'HUD. Se l'utente l'aveva chiuso, torna dopo una settimana (`SUScheduledImpatientCheckInterval`), sempre come riga e mai come finestra.
- **Riavvia premuto con un'Automazione tra 1 minuto**: il riavvio parte comunque; l'Esecuzione, se persa, segue il recupero della 19.
- **Esecuzione che parte mentre il riavvio aspetta**: il riavvio aspetta anche lei.
- **Uscita con una Sessione al lavoro**: vale il comportamento di uscita della 01; l'installazione avviene dopo, a processi chiusi.
- **Beta spenta su una beta più nuova della stabile**: nessuna voce ammessa più nuova; resta la beta fino alla stabile successiva.
- **Versione ritirata già installata**: resta installata; arriva la correzione. Nessun downgrade.
- **Downgrade a mano**: la versione vecchia apre gli store con campi in più e li ignora.
- **Delta che non si applica**: Sparkle scarica il DMG completo.
- **Rete assente o Pages giù**: il controllo fallisce in silenzio (solo log); riprova al giro successivo.
- **`claude` aggiornato mentre una Sessione è aperta**: il nuovo binario vale alla prossima Conversazione dell'agente; lì l'`init` riporta la versione nuova.
- **`claude` sparito** dopo l'avvio: vale la guida della 26 (CLI mancante).
- **`capabilities` assente** (CLI vecchia sopra la minima): insieme vuoto; le funzioni che la richiedono restano spente.
- **Più di 3 punti di Novità nel CHANGELOG**: la release si ferma.
- **Stringa nuova senza traduzione**: il controllo della rifinitura fallisce prima del merge.
- **Notarizzazione rifiutata o oltre 30 minuti**: la release si ferma senza pubblicare niente; si rilancia il job.

### Test

- `UpdateController` con un appcast locale (server di file nel test): Canale stabile ignora la beta; beta accesa la vede; beta spenta dopo una beta non propone versioni più vecchie.
- `RelaunchGate` con Sessioni e Automazioni finte: Riavvia con una Sessione in Lavora → nessun riavvio; Sessione Ferma → riavvio entro 1 s.
- Promemoria: 0 finestre di Sparkle nei controlli programmati; 0 promemoria prima della prima risposta.
- Aggiornamento vero da versione N a N+1 su un Mac pulito, con delta: installazione all'uscita, riapertura con la scheda Novità.
- `verify-entitlements.sh`: il bundle firmato ha esattamente gli entitlement ammessi, per app, ponte e lanciatore.
- `bridge-speed.sh`: ponte firmato con hardened runtime; tempo del carico di prova ≤ 2× il ponte senza hardened runtime.
- Firma e notarizzazione: `codesign --verify --strict` su ogni eseguibile, `spctl -a -t open --context context:primary-signature` sul DMG, `stapler validate`, `spctl -a -vv` sull'app montata ("Notarized Developer ID").
- Appcast: ogni URL risponde 200; ogni `item` ha `edSignature` e `length` giusti; feed firmato valido; beta con `sparkle:channel`; stabile con `phasedRolloutInterval` 86.400.
- `yank.sh` su un appcast di prova: voce tolta, altre intatte, firma del feed valida.
- Store: fixture scritte dalla versione N+1 aperte dal codice N senza errori; test dell'istantanea dello schema.
- `ClaudeCompatibility`: tabella di versioni (sotto, uguale, sopra la minima, formati strani) → esito; `capabilities` note, sconosciute e assenti.
- Smoke notturno: con una minima finta più alta dell'ultimo `claude`, il job fallisce e apre una sola issue.
- `polish-check.sh`:
  - il build non modifica il String Catalog e nessuna voce è non tradotta o da rivedere;
  - `AppIcon.appiconset` ha tutte e 10 le misure; il glifo della barra dei menu è un'immagine modello a 1× e 2×;
  - nessun `ProgressView` fuori da `Design/LoadingLabel`, che mostra un testo dopo 1 s;
  - nessuna durata di animazione scritta a mano fuori dai token di movimento di `Design/`.
- Menu: test che percorre `NSApp.mainMenu`, le scorciatoie globali e il `CommandCatalog` → 0 scorciatoie doppie; voci standard presenti (Informazioni su Bubo, Controlla aggiornamenti…, Impostazioni…, Nascondi, Esci, Modifica, Finestra, Aiuto).
- Accessibilità: `performAccessibilityAudit()` di XCTest su ogni finestra, 0 problemi; audit con le skill SwiftUI e AppKit su HUD, Panel, Impostazioni › Aggiornamenti, promemoria, scheda Novità e riquadro "Aggiorna Claude Code".
- Prestazioni: `scripts/perf.sh` sull'M4 Max prima di ogni release (25).

### Ordine di costruzione

I passi segnati **(umano)** servono account, certificati, segreti o il Mac di riferimento: un agente non può farli.

1. **Entitlement e velocità del ponte**: `bridge/bridge.entitlements` con il solo `cs.allow-jit`, firma ad hoc con hardened runtime in `scripts/check.sh`, `verify-entitlements.sh` e `bridge-speed.sh`. Non serve nessun segreto. Dipende dal ponte ([#66](https://github.com/mgiuditta/bubo/issues/66)).
2. **(umano) Account e segreti di distribuzione**: certificato Developer ID Application (`.p12`), chiave API di App Store Connect per `notarytool`, coppia EdDSA con `generate_keys` (copia della privata fuori dalla CI), repository pubblico `mgiuditta/bubo-releases` con Pages attivo, token con scrittura solo su quel repository, API key Anthropic per lo smoke notturno. Segreti nel repository `bubo`.
3. **Pipeline di release firmata**: `release.yml` sul tag, XcodeGen e Bun nel job, versione e numero di build, firma dall'interno verso l'esterno, DMG UDZO, notarizzazione, stapling, release in `bubo-releases` (prerelease per le beta). Ancora senza Sparkle. Dipende da 1 e 2.
   - **Script, non passi in linea** ([#221](https://github.com/mgiuditta/bubo/issues/221)): `keychain.sh`, `build.sh`, `sign.sh`, `dmg.sh`, `notarize.sh` in `scripts/release/`. Il workflow li chiama in fila e si possono rilanciare a mano su un Mac.
   - **Segreti** (nomi fissati qui, valori dal passo 2): `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `ASC_API_KEY_P8_BASE64`, `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID`, `BUBO_RELEASES_TOKEN`. Se ne manca uno, il job si ferma al primo passo e lo nomina.
   - **Archivio con firma automatica ed export `developer-id`** con la chiave di App Store Connect (`-allowProvisioningUpdates`), come dice `project.yml`: l'export crea il profilo che serve a `keychain-access-groups`. Poi `sign.sh` rifirma tutto dall'interno verso l'esterno, per profondità: il ponte con `bridge/entitlements.plist` e l'app con `--preserve-metadata=entitlements`, così resta l'entitlement del profilo. Chiude con `verify-entitlements.sh` senza `--dev`.
   - **DMG APFS UDZO**: solo macOS 26 (ADR 0001), quindi HFS+ non serve.
   - **Tag fuori formato** (`v1.2`, `-rc.1`): il job si ferma prima di compilare.
   - **Note della release** ancora solo "Bubo X.Y.Z": arrivano da `CHANGELOG.md` con l'appcast (passo 5).
   - **`BuboReleaseName` nell'Info.plist** rimandata: con `GENERATE_INFOPLIST_FILE` una chiave personalizzata richiede di toccare `project.yml`. Per ora il nome della release sta solo nel tag e nella release.
4. **Sparkle nell'app**: pacchetto SPM, Info.plist parziale (`SUFeedURL`, `SUPublicEDKey`, chiavi di controllo e installazione, feed firmato), servizi XPC tolti, `UpdateController`, `UpdatePreferences`, Impostazioni › Aggiornamenti, "Controlla aggiornamenti…" nel menu, nella barra dei menu e nella Palette. Provato con un appcast locale. Indipendente da 2–3.
5. **Appcast, Canali, gradualità e ritiro**: `appcast.sh` con delta, note per lingua dal CHANGELOG, canale beta, gradualità, critico, firma EdDSA dopo lo stapling, riscrittura degli URL, pubblicazione su Pages; `yank.sh` e `yank.yml`; `CHANGELOG.md`. Dipende da 3 e 4.
6. **Promemoria, riavvio rimandato e Novità**: promemoria gentili, `HUD/UpdateBanner`, `RelaunchGate`, niente promemoria prima della prima risposta, `WhatsNew` e `HUD/WhatsNewCard`, `InstallLocation`, istantanea degli schemi degli store. Dipende da 4; `RelaunchGate` completo dopo 06 e 19.
7. **Compatibilità con `claude`**: `compat.json`, `ClaudeCompatibility`, esito "vecchia" di `ClaudeReadiness` e riquadro "Aggiorna Claude Code" alla partenza di ogni Sessione, con la domanda tenuta; verifica all'`init`, `capabilities` per le altre feature. Dipende da [#66](https://github.com/mgiuditta/bubo/issues/66) e dal passo 1 della 26 (rilevamento di `claude`).
8. **Smoke notturno e freschezza dell'SDK**: `bridge/smoke/`, `nightly-claude.yml` con ultima e minima, issue automatica, `bump-sdk.sh`, controllo nel workflow di release. Dipende da 2, 3 e 7.
9. **Checklist di rifinitura come definizione di fatto**: `pull_request_template.md`, `polish-check.sh` in `scripts/check.sh`, `Design/LoadingLabel`, `Design/ErrorNotice`, token di movimento, test dei menu, audit di accessibilità di XCTest. Indipendente: può partire subito dopo la shell.
10. **(umano) Icona e glifo della barra dei menu**: marchio, icona in 10 misure, glifo modello. Chiude il punto "Marchio e logotipo" di [design-system.md](../design-system.md).
11. **(umano) Audit completo e prima beta**: gli otto criteri schermata per schermata, `scripts/perf.sh` e profilazione della 25 sull'M4 Max, ticket di correzione; poi tag `v0.1.0-beta.1` e prova di aggiornamento reale verso `beta.2` su un secondo Mac. Dopo 1–10 e dopo 01, 11 e l'Indice (profilazione, [#186](https://github.com/mgiuditta/bubo/issues/186)).

## Specifica "migliore di"

Miglior concorrente: **Claude desktop** e **Cursor** (Electron con Squirrel, fermo al 2017) e le app native con la finestra standard di Sparkle. Nessuno dichiara una versione minima della CLI né prova l'app contro la CLI nuova.
Bubo li supera così:

1. **Mai interrotto**: **0 finestre** di aggiornamento non chieste dall'utente; **0 riavvii** con una Sessione in Lavora o un'Esecuzione in corso.
2. **Onboarding intatto**: **0 promemoria** di aggiornamento prima della prima risposta.
3. **Verificabile**: **100%** delle release firmate Developer ID, notarizzate, graffate e firmate EdDSA; appcast firmato; `spctl` accetta DMG e app.
4. **Nessun downgrade**: chi spegne "Ricevi le beta" riceve **0 versioni** più vecchie di quella installata.
5. **Ritiro rapido**: una versione tolta dall'appcast non viene più proposta entro **15 minuti** dal ritiro; **0 store** corrotti riaprendo i dati con la versione precedente.
6. **Delta sempre offerti**: ogni release ha un delta per **ciascuna delle 3 versioni** precedenti del suo Canale.
7. **Release rapida**: dal tag all'appcast pubblicato **≤ 40 minuti**, notarizzazione compresa.
8. **Ponte veloce e stretto**: entitlement del bundle firmato **uguali** alla lista ammessa; test di velocità del ponte firmato **≤ 2×** il ponte senza hardened runtime.
9. **CLI dell'utente sotto controllo**: **0 Sessioni** avviate con un `claude` sotto la minima, riquadro con il comando al **100%**; un `claude` nuovo che rompe il ponte segnalato **entro 24 ore** dalla sua uscita.
10. **Novità brevi**: scheda con **≤ 3 punti**, mostrata **una volta** per versione, nella lingua dell'utente.
11. **Rifinitura misurata**: **0 stringhe** fuori dal String Catalog e **0 traduzioni** mancanti; **0 scorciatoie** in conflitto; **0 spinner** oltre 1 s senza testo; **0 problemi** da `performAccessibilityAudit()`; icona in **10 misure** su 10; budget della 25 rispettati.

## Fonti

1. Apple, App Store Review Guidelines (2.4.5, 2.5.1, 2.5.2) — https://developer.apple.com/app-store/review/guidelines/
2. Apple Developer Forums, Quinn "The Eskimo!", "Resolving App Sandbox Inheritance Problems" — https://developer.apple.com/forums/thread/706390
3. Apple, "Embedding a helper tool in a sandboxed app" — https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app
4. sparkle-project/Sparkle, Releases (2.8.0 → 2.10.0) — https://github.com/sparkle-project/Sparkle/releases
5. Sparkle, "Documentation" — https://sparkle-project.org/documentation/
6. Sparkle 2.10.0, header `SPUStandardUpdaterController.h`, `SPUUpdater.h`, `SPUUpdaterDelegate.h` — https://github.com/sparkle-project/Sparkle/tree/2.10.0/Sparkle ; PR #2827 — https://github.com/sparkle-project/Sparkle/pull/2827
7. Sparkle, "Programmatic Setup" — https://sparkle-project.org/documentation/programmatic-setup/
8. sparkle-project/Sparkle, discussione #2881 e PR #2882 — https://github.com/sparkle-project/Sparkle/discussions/2881
9. Sparkle, "Publishing an update" — https://sparkle-project.org/documentation/publishing/
10. Sparkle 2.10.0, `generate_appcast/main.swift` — https://github.com/sparkle-project/Sparkle/blob/2.10.0/generate_appcast/main.swift
11. Sparkle, "EdDSA migration" — https://sparkle-project.org/documentation/eddsa-migration/
12. Sparkle, "Security and reliability" — https://sparkle-project.org/documentation/security-and-reliability/
13. Sparkle, "Delta updates" — https://sparkle-project.org/documentation/delta-updates/
14. Apple, "Packaging Mac software for distribution" — https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution
15. Apple, "Notarizing macOS software before distribution" e "Customizing the notarization workflow" — https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution ; https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
16. Sparkle, "Customizing Sparkle" — https://sparkle-project.org/documentation/customization/
17. Sparkle, "Gentle Update Reminders" — https://sparkle-project.org/documentation/gentle-reminders/
18. Sparkle, "Sandboxing" — https://sparkle-project.org/documentation/sandboxing/
19. Squirrel/Squirrel.Mac — https://github.com/Squirrel/Squirrel.Mac
20. Homebrew, "Cask Cookbook" — https://docs.brew.sh/Cask-Cookbook
21. Apple Developer Forums, Quinn "The Eskimo!", "--deep Considered Harmful" — https://developer.apple.com/forums/thread/129980
22. Apple, "Placing content in a bundle" — https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle
23. actions/runner-images, `macos-26-arm64-Readme.md` — https://github.com/actions/runner-images
24. GitHub Docs, "Installing an Apple certificate on macOS runners for Xcode development" — https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications
25. GitHub Docs, "Linking to releases" — https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases
26. GitHub REST API, "Get the latest release" — https://docs.github.com/en/rest/releases/releases#get-the-latest-release
27. GitHub Docs, "About releases" — https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases
28. Bun, "Single-file executable" — https://bun.com/docs/bundler/executables
29. Bun, "Codesign a single-file JavaScript executable on macOS" — https://bun.sh/guides/runtime/codesign-macos-executable
30. Apple, `com.apple.security.cs.allow-jit` — https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.allow-jit
31. Apple, `com.apple.security.cs.allow-unsigned-executable-memory` — https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.allow-unsigned-executable-memory
32. oven-sh/bun, Releases — https://github.com/oven-sh/bun/releases
33. Agent SDK, "TypeScript SDK reference" — https://code.claude.com/docs/en/agent-sdk/typescript
34. `@anthropic-ai/claude-agent-sdk` 0.3.285, `sdk.d.ts` e `package.json` — https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk
35. Claude Code, "Advanced setup" — https://code.claude.com/docs/en/setup
