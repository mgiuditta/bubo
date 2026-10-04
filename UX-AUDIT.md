# Audit UX di Bubo

Data: 2026-10-04. Obiettivo: semplificare l'esperienza (meno passaggi, meno scelte per schermata, testi più chiari, default sensati, errori e stati vuoti comprensibili). Colori, font e stile visivo sono fuori dall'audit.

Metodo: euristiche di Nielsen (severità 1-4) e principi di Krug, skill `ux-heuristics`; carico cognitivo (memoria di lavoro, legge di Hick, golfi di esecuzione e di valutazione), skill `cognitive-foundations`. Ogni file:riga è stato verificato sul codice di `main` (commit `793d932`). I termini del glossario (`CONTEXT.md`) non sono segnalati come gergo. Le righe si riferiscono al codice prima delle correzioni.

Colonna **Stato**: ✅ corretto in questo giro, ⏳ aperto, — non applicato (motivo nella riga).

## Punteggi (Quick Diagnostic, su 10)

| Area | Prima | Problemi più gravi |
|---|---|---|
| Finestra principale e Sessioni | 4 | Fogli che non si aprono fuori dalla casa (sev 4); Sessione che non si può fermare; terminale e Anteprima invisibili |
| Primo avvio e Impostazioni | 6 | Nessuna uscita dal primo avvio senza Progetto; API key senza spiegazione; Impostazioni dense |
| Secondo cervello, Riunioni, aree accessorie | 6 | La casa non propone di configurare il Secondo cervello; lingua delle Riunioni non modificabile; Neuroni come vicolo cieco in Release |
| Panel, Bolla, voce, Allegati | 7 | Risposta che sparisce dalla pillola; dettatura vuota silenziosa; Anteprima bianca col server spento |

---

## Mappa di schermate e flussi

**Primo avvio.** `App/LaunchSequence.swift` → `HUD/HUDView.swift` (`showsOnboarding`) → `Onboarding/OnboardingStage.swift` (frase, `OnboardingSteps`, `FixCard`, `ShortcutStep`, Progetti recenti, campo, suggerimenti) → `Onboarding/OnboardingFlow.swift` → `Onboarding/FirstPermissionCard.swift`.

**Finestra principale (HUD).** Barra laterale `Window/MainSidebar.swift` (Cervello, Neuroni, Riunioni, Lavoro, elenco per giorno `ConversationList`, Progetti `ProjectSessions`) → colonna destra:
- casa: `HUD/HUDView.swift` (`main`) + `Window/HomeHeader.swift` + `Question/QuestionView.swift`;
- Domanda: `Window/QuestionDetail.swift`;
- Sessione: `Window/SessionDetail.swift` = `HUD/SessionRow.swift` + `History/ConversationReaderView.swift` + composer;
- Lavoro: `HUD/SessionBoard.swift` (Bozze e 5 colonne, `BoardActions`, `NewDraftSheet`, `IssuePicker`);
- conversazione CLI: `Window/ConversationDetail.swift`.

Fogli: `HUD/NewSessionSheet.swift`, `Review/ReviewSheet.swift`, `HUD/PullRequestSheet.swift`, `HUD/DeliverySheet.swift`, `HUD/DeliveryReceivedSheet.swift`, `Permissions/TrustSheet.swift`.

**Panel e Bolla.** Scorciatoia o clic sull'Orb → `Panel/OrbPanelController.swift` (`askInPanel`) → `Panel/PanelBubble.swift` → `Panel/PanelBubbleView.swift`; pillola di stato `Panel/PanelStatus.swift`; Allegati `Panel/OrbDropTarget.swift`, `Intake/`; voce `Voice/PushToTalk.swift`, `Voice/VoiceNotice.swift`.

**Palette e Cronologia.** `Palette/PaletteView.swift`, `PaletteModel.swift` → `History/HistoryWindow`.

**Secondo cervello.** Impostazioni › Generale › `Settings/SecondBrainSettingsSection.swift` → `SecondBrainSetupSheet.swift` (cartella, app di chiamata, audio, lingua) oppure `SecondBrainConversationSheet.swift` (intervista nella Bolla, `Panel/SecondBrainProposalCard.swift`).

**Riunioni.** Barra laterale o menu → `Meetings/MeetingView.swift` (registra, importa, parlanti) → errori `Meetings/MeetingFailure.swift`.

**Aree accessorie.** Neuroni (`Neurons/NeuronView.swift`, cancello `Release/ReleaseArea.swift`); Automazioni (`Automations/AutomationsWindow.swift`, `AutomationSheet.swift`); Plugin e Server MCP (`Plugins/PluginsWindow.swift`, `InstallSheet.swift`); Galassia (`Galaxy/`); Anteprima (`Preview/PreviewPanel.swift`, `PreviewPage.swift`); Visore (`Viewer/CodeViewer.swift`); Comandi rapidi (`System/Intents/`).

**Impostazioni.** `Settings/SettingsView.swift`, 13 tab: Generale, Account, Modelli, Voce, Scorciatoie, Permessi, Macchine, Budget, iPhone, Aggiornamenti, Diagnostica, Consegne e altre. Barra dei menu: `MenuBar/MenuBarContent.swift`.

### Carico cognitivo per flusso (sintesi)

| Flusso | Decisioni | Memoria richiesta | Verdetto |
|---|---|---|---|
| Primo avvio | 2 obbligatorie (cartella, testo), fino a 8 blocchi a schermo | bassa (passi con spunta) | accettabile ma rigido: nessuna strada per chi vuole solo chiedere |
| Casa → Domanda | 1 (cosa chiedere) | alta: la Domanda «attiva» resta nascosta e continua in silenzio | errore di modalità |
| Nuova Sessione | 6 controlli, 2 già proposti | bassa | troppe scelte per il caso comune |
| Seguire una Sessione | azioni solo nel clic destro | alta (golfo di esecuzione) | alto |
| Rivedere e fondere | 1 azione per file, nessun «accetta tutto» | media | medio-alto |
| Bolla | fino a 5 icone senza testo | media | medio, percorso base buono |
| Dettatura | gesto nascosto | alta al primo uso | silenzio quando non sente nulla |
| Secondo cervello | ingresso solo nelle Impostazioni, 2 percorsi senza consigliato | ricordo | alto all'ingresso |
| Riunioni | foglio di 3 domande prima della prima registrazione | ricordo (lingua non più modificabile) | alto al primo uso |
| Automazione | 8-9 controlli allo stesso livello | bassa | medio-alto |
| Impostazioni › Modelli | 12-13 sezioni, id del modello da scrivere a memoria | ricordo | alto |

---

## Impatto alto

| # | Flusso | Sev | Euristica | File:riga | Problema | Correzione | Stato |
|---|---|---|---|---|---|---|---|
| A1 | Board, Bozze, Consegna | 4 | 1 Visibilità (compito bloccato) | `Bubo/HUD/HUDView.swift:150-163`, `:220-222` | I fogli Nuova Bozza (anche ⌥⌘N), Consegna…, Apri PR… e scelta issue (⌘I) sono agganciati alla vista della casa: con un'altra selezione non si aprono, e saltano fuori più tardi | Spostare i quattro `.sheet` nel `background` di `body`, accanto agli altri fogli | ✅ |
| A2 | Seguire una Sessione | 3 | 3 Controllo e libertà | `Bubo/Window/SessionDetail.swift:40-44` | Non esiste un comando per fermare una Sessione che lavora (`SessionStore.interrupt` lo usano solo le Automazioni) | Mentre la Sessione lavora, «Invia» diventa «Ferma» | ✅ |
| A3 | Seguire una Sessione | 3 | 1 Visibilità | `Bubo/HUD/HUDView.swift:214-216` | Terminale e Anteprima aperti da una Sessione si disegnano solo nella casa: «Apri il terminale» non mostra nulla | Mostrare `PanelRow` anche nel dettaglio della Sessione | ✅ |
| A4 | Board | 3 | 4 Coerenza, 7 Efficienza | `Bubo/HUD/SessionBoard.swift:366-382` | Le card della Board non si aprono: per continuare una Sessione bisogna ritrovarla nella barra laterale | Clic sulla card = apri la Sessione | ✅ |
| A5 | Casa → Domanda | 3 | 1 Visibilità | `Bubo/Question/QuestionModel.swift:855` | La Domanda appena fatta entra nell'elenco solo quando si chiude | Archiviare la Domanda a fine risposta (il salvataggio sostituisce per id) | ✅ |
| A6 | Casa → Domanda | 3 | 3 Controllo, 6 Riconoscimento | `Bubo/HUD/HUDView.swift:31-38` | Dopo aver aperto una vecchia Domanda, tornando su «Cervello» la casa è vuota ma il campo continua quella vecchia (contesto nascosto) | Tornando al Cervello da una Domanda, aprirne una nuova | ✅ |
| A7 | Casa → Domanda | 3 | 4 Coerenza | `Bubo/Question/QuestionView.swift:34`, `:39` | Il campo dice «Chiedi qualcosa a Claude» sotto il titolo «Chiedi al tuo cervello»; il router può non usare Claude | `"Chiedi al tuo cervello"` | ✅ |
| A8 | Primo avvio | 3 | 3 Controllo e libertà | `Bubo/HUD/HUDView.swift:107-109`, `Bubo/Onboarding/OnboardingStage.swift:36-39` | Senza una Sessione il campo della Domanda è nascosto: chi vuole solo chiedere deve scegliere una cartella | Link «Chiedi senza Progetto» che chiude il primo avvio | ✅ |
| A9 | Primo avvio | 3 | 4 Coerenza | `Bubo/Onboarding/OnboardingSteps.swift:15` | Il passo 2 si chiama «Domanda», ma si sta avviando una Sessione: si impara il termine sbagliato al primo schermo | `"Cosa fare"` | ✅ |
| A10 | Nuovo Progetto | 3 | 6 Riconoscimento, 1 Visibilità | `Bubo/Window/MainSidebar.swift:28-35` | Senza Sessioni la sezione Progetti non esiste: nessun punto visibile dice dove si aggiunge un Progetto | Sezione sempre presente con «Aggiungi Progetto…» | ✅ |
| A11 | Bolla | 3 | 1 Visibilità, 3 Controllo | `Bubo/Panel/PanelBubbleView.swift:33` | Cliccando «Risposta pronta» dopo 15 minuti la Bolla si apre vuota: `resetIfIdle` in `onAppear` butta la risposta promessa | Azzerare solo quando si apre per chiedere (`askInPanel`) | ✅ |
| A12 | Dettatura | 3 | 1 Visibilità, 9 Errori | `Bubo/Voice/PushToTalk.swift:164` | Se il riconoscimento non produce testo, al rilascio non succede nulla | Avviso «Non ho sentito niente» con il rimedio | ✅ |
| A13 | Anteprima | 3 | 1 Visibilità, 9 Errori | `Bubo/Preview/PreviewPage.swift:195-202` | Server spento o porta sbagliata: pagina bianca, nessun messaggio | Stato «Il server non risponde» con «Ricarica» | ✅ |
| A14 | Comandi rapidi | 3 | 1 Visibilità | `Bubo/System/Intents/AskBuboIntent.swift:42` | «Chiedi a Bubo» con il Panel spento risponde in silenzio, nessun ritorno in Comandi rapidi | Dialogo «Domanda inviata a Bubo.» e descrizione che dice dove compare la risposta (aprire la finestra col Panel spento resta aperto) | ✅ |
| A15 | Secondo cervello | 3 | 6 Riconoscimento, 1 Visibilità | `Bubo/Window/HomeHeader.swift:11-25` | Senza cartella la casa propone domande senza risposta («Cosa ricordi di me?»); la configurazione sta solo in Impostazioni › Generale | Senza cartella, al posto dei suggerimenti: «Scegli la cartella delle tue note…» | ✅ |
| A16 | Secondo cervello | 3 | 5 Prevenzione, 3 Controllo | `Bubo/Settings/SecondBrainSettingsSection.swift:35` | «Non usare più» agisce senza conferma e fa dimenticare cartelle escluse e prioritarie | Conferma con messaggio su cosa si perde | ✅ |
| A17 | Riunioni | 3 | 3 Controllo, 9 Errori | `Bubo/Meetings/MeetingFailure.swift:42`, `Bubo/Settings/SecondBrainSettingsSection.swift:64-67` | L'errore dice di cambiare la lingua delle Riunioni, ma dopo il primo uso la lingua non si trova più | Picker «Lingua delle Riunioni» nelle Impostazioni; errore che dice dove | ✅ |
| A18 | Riunioni | 3 | 5 Prevenzione | `Bubo/Meetings/MeetingView.swift:112` | Senza cartella «Registra» è attivo e fallisce solo dopo | Disattivarlo senza cartella | ✅ |
| A19 | Neuroni | 3 | 8 Minimalismo, 4 Coerenza | `Bubo/Window/MainSidebar.swift:18`, `Bubo/MenuBar/MenuBarContent.swift:61`, `Bubo/App/BuboApp.swift:92` | In Release la voce di primo livello «Neuroni» apre solo un alert «arriverà presto» | Non applicata: il cancello «Arriverà presto» per le aree 1.1 è una decisione di prodotto (PRD #514, #515, #516) | — |
| A20 | Account | 3 | 1 Visibilità, modello mentale | `Bubo/Settings/AccountSettingsView.swift:121` | Il footer della API key non dice quando viene usata (solo a Quota finita, su conferma) | «Facoltativa. Quando finisce la Quota dell'abbonamento, Bubo ti chiede se continuare con la chiave, a consumo.» | ✅ |
| A21 | Account | 3 | 9 Recupero | `Bubo/Settings/AccountSettingsView.swift:73-77` | CLI mancante: solo un comando da copiare a mano, mentre il primo avvio ha un pulsante | «Installa nel Terminale» | ✅ |
| A22 | Modelli | 3 | 6 Riconoscimento | `Bubo/Settings/EndpointSection.swift:18` | Campo «Modello» vuoto senza esempio: va scritto a memoria, e senza modello l'endpoint non conta | Segnaposto «id del modello, come lo scrive il fornitore» | ✅ |
| A23 | Rivedere e fondere | 3 | 7 Efficienza | `Bubo/Review/ReviewSheet.swift:190-196` | Non c'è «Accetta tutti i blocchi»: per fondere si accetta file per file | Voce in «Altre azioni» | ✅ |
| A24 | Seguire una Sessione | 3 | 6 Riconoscimento | `Bubo/HUD/SessionRow.swift:383-413` | Rivedi, Consegna, Archivia, Terminale stanno solo nel clic destro | Azioni del prossimo passo visibili nel dettaglio | ⏳ |
| A25 | Palette | 3 | 3 Controllo, 4 Coerenza | `Bubo/Window/ConversationDetail.swift:45` | Le conversazioni CLI nella finestra non hanno «Riprendi» | Passare le `ResumeActions` della Cronologia | ⏳ |
| A26 | Dal Cervello a una Sessione | 2 | 5 Prevenzione, 7 Efficienza | `Bubo/Question/QuestionModel.swift:731-732` | «entra in X e…» parte come Domanda; la proposta di Sessione compare solo dopo la risposta | Calcolare la proposta anche sul testo che si sta scrivendo | ✅ |
| A27 | Riunioni | 2 | 7 Efficienza | `Bubo/Meetings/MeetingView.swift:47-53` | Alla prima registrazione si apre un foglio di 3 domande (o l'intervista col modello, senza cartella) | Foglio solo senza cartella, ed è quello rapido | ✅ |
| A28 | Secondo cervello | 2 | 2 Corrispondenza | `Bubo/Settings/SecondBrainSettingsSection.swift:74` | «Configura in 60 secondi» promette la cartella ma pone 4 domande, 3 sulle Riunioni | Solo il passo della cartella | ✅ |
| A29 | Automazione | 2 | 8 Minimalismo | `Bubo/Automations/AutomationSheet.swift:93-106` | Modello, Agente e Modalità autonoma sempre visibili: 8-9 scelte | `DisclosureGroup("Opzioni avanzate")` | ✅ |
| A30 | Budget | 2 | 8 Minimalismo, Hick | `Bubo/Costs/BudgetSettingsView.swift:64` | Budget anche per fornitori non configurati: interruttori che non scattano mai | Solo i fornitori pronti | ✅ |
| A31 | Plugin | 2 | 10 Aiuto | `Bubo/Plugins/PluginEntryList.swift:48` | «Nessun plugin installato» non dice da dove si installano | Descrizione che rimanda ai Marketplace | ✅ |

## Impatto medio

| # | Flusso | Sev | Euristica | File:riga | Problema | Correzione | Stato |
|---|---|---|---|---|---|---|---|
| M1 | Primo avvio | 2 | 2 Corrispondenza | `Bubo/Onboarding/OnboardingStage.swift:72` | «Scegli un'altra cartella…» anche senza recenti | «Scegli la cartella del Progetto…» se l'elenco è vuoto | ✅ |
| M2 | Primo avvio | 2 | 4 Coerenza | `Bubo/Onboarding/FixCard.swift:159` | «Copia e apri Terminale» rompe lo schema «Verbo nel Terminale» | «Installa nel Terminale» | ✅ |
| M3 | Primo avvio | 2 | 8 Minimalismo, 6 Riconoscimento | `Bubo/Onboarding/FirstPermissionCard.swift:18` | Una frase spiega le 4 risposte già scritte sui pulsanti, senza dire dove si toglie una regola | Testo più corto con il percorso | ⏳ |
| M4 | Account | 2 | 9 Recupero | `Bubo/Settings/AccountSettingsView.swift:82-84` | «codice N» senza cosa fare | Pulsante di diagnostica nel Terminale | ⏳ |
| M5 | Account | 2 | 2 Corrispondenza | `Bubo/Settings/AccountSettingsView.swift:80` | In stato offline parla della API key | «Controlla la connessione, poi premi Riprova.» | ✅ |
| M6 | Impostazioni | 2 | 8 Minimalismo, Hick | `Bubo/Settings/SettingsView.swift:28-40` | Tab «Arriverà presto» (Macchine, iPhone) in mezzo a quelle vere | Spostarle in fondo | ✅ |
| M7 | Impostazioni | 2 | 8 Minimalismo | `Bubo/Settings/GeneralSettingsView.swift:27-30` | Generale contiene 4 sezioni del Secondo cervello | Tab dedicata «Secondo cervello» | ⏳ |
| M8 | Secondo cervello | 2 | Hick, 8 Gerarchia | `Bubo/Settings/SecondBrainSettingsSection.swift:40-49` | Due pulsanti di pari peso senza un consigliato; sottotitolo lungo | Sottotitolo più corto | ✅ |
| M9 | Secondo cervello | 2 | 3 Controllo | `Bubo/Settings/SecondBrainSetupSheet.swift:49` | Al passo cartella «Salta» e «Salta tutto» fanno la stessa cosa | «Salta» solo dopo il passo cartella | ✅ |
| M10 | Secondo cervello | 2 | 1 Visibilità | `Bubo/Panel/SecondBrainProposalCard.swift:40-46` | Dopo «Applica» la scheda sparisce senza conferma | Annuncio di conferma | ⏳ |
| M11 | Modelli | 2 | 4 Coerenza | `Bubo/Settings/ModelsSettingsView.swift:45` | Consenso Copilot lontano dall'account Copilot | Spostarlo subito dopo | ✅ |
| M12 | Modelli | 2 | 1 Visibilità | `Bubo/Settings/ModelsSettingsView.swift:24-32` | Picker «Modello locale» con solo «Nessuno», senza dire perché | Footer che dice cosa fare | ⏳ |
| M13 | Modelli | 2 | 8 Minimalismo | `Bubo/Settings/ModelsSettingsView.swift:17` | Introduzione di 3 frasi in parte smentita dalla tab | Testo più corto | ⏳ |
| M14 | Budget | 2 | 8 Minimalismo | `Bubo/Costs/BudgetSettingsView.swift:29` | Footer di 4 frasi | Testo dimezzato | ⏳ |
| M15 | Barra dei menu | 2 | 4 Coerenza | `Bubo/MenuBar/MenuBarContent.swift:62` | «Mostra HUD»: termine interno, la scorciatoia altrove si chiama «Mostra e nascondi Bubo» | «Mostra Bubo» | ✅ |
| M16 | Barra dei menu | 2 | 4 Coerenza, 5 Prevenzione | `Bubo/MenuBar/MenuBarContent.swift:66-67` | «Chiedi nel Panel» grigio col Panel nascosto, mentre la scorciatoia funziona | Sempre attivo: Panel se c'è, altrimenti finestra | ✅ |
| M17 | Voce | 2 | 6 Riconoscimento | `Bubo/Settings/VoiceSettingsView.swift:17` | Rimanda a Modelli senza pulsante | Pulsante «Apri Modelli» | ⏳ |
| M18 | Permessi | 2 | 4 Coerenza | `Bubo/Permissions/ProjectRulesSection.swift:86` | «Revoca» qui, «Togli…» nelle Impostazioni per la stessa azione | «Togli» | ✅ |
| M19 | Nuova Sessione | 2 | 8 Minimalismo | `Bubo/HUD/NewSessionSheet.swift:74`, `:84-87` | Titolo e Branch proposti da soli ma sempre visibili | Spostarli in «Altre opzioni» | ⏳ |
| M20 | Nuova Sessione | 2 | 2 Corrispondenza | `Bubo/HUD/NewSessionSheet.swift:78` | «Lavora sul checkout» è gergo git | «Lavora direttamente nella cartella» | ✅ |
| M21 | Nuova Sessione | 2 | 9 Errori | `Bubo/HUD/NewSessionSheet.swift:162-165` | Se l'avvio fallisce il foglio si chiude e l'errore va solo nel log | Chiudere solo se riesce, altrimenti mostrare l'errore | ✅ |
| M22 | Casa → Domanda | 2 | 3 Controllo | `Bubo/Question/QuestionModel.swift:654-656` | Aprire un'altra Domanda interrompe senza avviso la risposta in arrivo | Continuare solo a risposta finita | ⏳ |
| M23 | Seguire una Sessione | 2 | 8 Minimalismo | `Bubo/History/ConversationReaderView.swift:52-55` | «Punto successivo» sempre disattivato senza ricerca | Mostrarlo solo con risultati | ⏳ |
| M24 | Seguire una Sessione | 2 | 8 Minimalismo | `Bubo/HUD/SessionRow.swift:222-370` | La card in testa al dettaglio impila oltre 15 elementi | Variante compatta | ⏳ |
| M25 | Board | 2 | 8 Minimalismo, Hick | `Bubo/HUD/SessionBoard.swift:78-80` | 6 colonne sempre visibili anche vuote | Nascondere «PR aperta» e «Fusa» se vuote | ⏳ |
| M26 | Rivedere e fondere | 2 | 8 Minimalismo | `Bubo/Review/ReviewSheet.swift:161-169` | Strategia di merge sempre nell'intestazione | Spostarla in «Altre azioni» | ⏳ |
| M27 | Pull request | 2 | 4 Coerenza | `Bubo/HUD/PullRequestSheet.swift:92` | Toggle «Bozza» si scontra con la Bozza di Bubo | «Apri come bozza su GitHub» | ✅ |
| M28 | Consegna | 2 | 4 Coerenza | `Bubo/HUD/DeliveryReceivedSheet.swift:33` | «Livelli di permesso» non esiste nel glossario | «Regole di permesso» | ✅ |
| M29 | Palette | 2 | 1 Visibilità | `Bubo/Window/ConversationDetail.swift:52` | Intestazione della conversazione CLI vuota | Titolo dalla Cronologia | ⏳ |
| M30 | Palette | 2 | 4 Coerenza | `Bubo/App/AppDelegate.swift:163-165` | Un risultato Sessione apre la Cronologia in sola lettura, non la Sessione | Aprire la Sessione nella finestra | ⏳ |
| M31 | Palette | 2 | 6 Riconoscimento | `Bubo/History/ConversationSearch.swift:4-7` | Le Domande non si cercano | Includere l'archivio delle Domande | ⏳ |
| M32 | Barra laterale | 2 | 4 Coerenza | `Bubo/Window/MainSidebar.swift:44-45` | «riga di comando» invece di «Cronologia CLI» | «Mostra la Cronologia CLI» | ✅ |
| M33 | Bolla | 2 | 2 Corrispondenza | `Bubo/Panel/PanelBubbleView.swift:85`, `Bubo/Question/QuestionView.swift:203` | «Chiedo a Claude…» anche con Copilot o modello locale | «Sto pensando…» | ✅ |
| M34 | Bolla | 2 | 4 Coerenza | `Bubo/Panel/PanelBubbleView.swift:162`, `:169` | «Chiedi qualcosa a Claude» contro il comando «Chiedi a Bubo» | «Chiedi a Bubo» | ✅ |
| M35 | Bolla | 2 | 8 Minimalismo | `Bubo/Panel/PanelBubbleView.swift:100`, `:188-191` | Due «Trasforma in Sessione» quando c'è una proposta | Solo la proposta | ✅ |
| M36 | Bolla | 2 | 4 Coerenza | `Bubo/Panel/PanelBubbleView.swift:193`, `:197` | «Apri la chat completa»: parola evitata dal glossario | «Apri nella finestra» | ✅ |
| M37 | Pillola di stato | 2 | 1 Visibilità | `Bubo/Panel/OrbPanelController.swift:416` | Con il Panel normale niente pillola di stato | Pillola anche col Panel normale | ⏳ |
| M38 | Scorciatoie | 2 | 4 Coerenza | `Bubo/Settings/ShortcutSettingsView.swift:10` | Stessa scorciatoia con nomi diversi; nessuno dice «tieni premuto per parlare» | «Mostra Bubo · tieni premuto per parlare» | ✅ |
| M39 | Dettatura | 2 | 1 Visibilità | `Bubo/Voice/PushToTalk.swift:119` | Primo uso: concesso il microfono, la pressione si perde in silenzio | Avviso «Microfono pronto» | ⏳ |
| M40 | Dettatura | 2 | 4 Coerenza | `Bubo/App/AppDelegate.swift:193-194` | La voce apre sempre la finestra anche lavorando col Panel | Da decidere con ADR 0013 | ⏳ |
| M41 | Allegati | 2 | 3 Controllo, 5 Prevenzione | `Bubo/Panel/OrbPanelController.swift:177-185` | La pagina del browser si allega da sola e la prima volta chiede il permesso di Automazione | Allegare solo con Bolla vuota | ⏳ |
| M42 | Comandi rapidi | 2 | 6 Riconoscimento | `Bubo/System/Intents/ProjectEntity.swift:39-41` | Si scelgono solo Progetti con Sessioni | Accettare un percorso di cartella | ⏳ |
| M43 | Galassia | 2 | 9 Errori | `Bubo/Galaxy/GalaxyFileList.swift:73-75` | Ricerca vuota con filtro dice «Nessun file modificato» | Stato vuoto di ricerca | ✅ |
| M44 | Visore | 2 | 9 Errori, 3 Controllo | `Bubo/Viewer/CodeViewer.swift:31-39` | Errori senza azione se non c'è un editor | «Mostra nel Finder» | ✅ |
| M45 | Riunioni | 2 | 5 Prevenzione | `Bubo/Meetings/MeetingMenuItems.swift:14` | «Importa Riunioni…» attivo senza cartella | Disattivarlo senza cartella | ⏳ |
| M46 | Riunioni | 2 | 9 Recupero | `Bubo/Meetings/MeetingFailure.swift:52` | yt-dlp: nessun rimedio | «Controlla la connessione e riprova.» | ✅ |
| M47 | Neuroni | 2 | 3 Controllo | `Bubo/App/AppDelegate.swift:540-544` | Alert «Nessun Secondo cervello» senza pulsante per rimediare | Pulsante «Apri Impostazioni» | ⏳ |
| M48 | Automazione | 2 | 5 Prevenzione | `Bubo/Automations/AutomationSheet.swift:70`, `:160` | Nome obbligatorio | Nome facoltativo, preso dalla richiesta | ✅ |
| M49 | Automazione | 2 | 4 Coerenza | `Bubo/Automations/AutomationSheet.swift:94`, `AutomationRow.swift:109` | «Router» qui, «Automatico» altrove | «Automatico» | ✅ |
| M50 | Automazione | 2 | 1 Visibilità, 9 Errori | `Bubo/Automations/AutomationSheet.swift:129-131` | «Crea» disattivato senza motivo (ora passata) | «Scegli un'ora futura.» | ✅ |
| M51 | Plugin | 2 | 4 Coerenza | `Bubo/Plugins/InstallSheet.swift:71` | «Solo io qui» contro «Solo io in questo Progetto» | Usare i titoli di `PluginScope` | ⏳ |
| M52 | Plugin | 2 | 10 Aiuto | `Bubo/Plugins/PluginsWindow.swift:199-201` | Server MCP: stato vuoto senza strada | «Arrivano con i Plugin: cercane uno in un Marketplace.» | ✅ |
| M53 | Plugin | 2 | 2 Corrispondenza | `Bubo/Plugins/PluginReloadBanner.swift:19` | «cache del prompt» è gergo | Testo in parole semplici | ✅ |
| M54 | Ricerca | 2 | 2 Corrispondenza | `Bubo/Settings/SemanticSearchSettingsSection.swift:12`, `:18` | «Come grep», «RAG» | «Trova le parole esatte…», «Per significato» | ✅ |

## Impatto basso

| # | Flusso | Sev | Euristica | File:riga | Problema | Correzione | Stato |
|---|---|---|---|---|---|---|---|
| B1 | Primo avvio | 1 | 8 Minimalismo | `Bubo/Onboarding/OnboardingStage.swift:26` | Spiegazione di 30 parole | Testo più corto | ⏳ |
| B2 | Primo avvio | 1 | 7 Efficienza | `Bubo/Onboarding/OnboardingStage.swift:129-131` | Il suggerimento riempie il campo ma non invia | Accettabile: permette di modificare | ⏳ |
| B3 | Account | 1 | 4 Coerenza | `Bubo/Settings/AccountSettingsView.swift:66` | «Non sei collegato» contro «Accedi a Claude Code» | «Non hai fatto l'accesso a Claude Code.» | ✅ |
| B4 | Impostazioni | 1 | 8 Minimalismo | `Bubo/Settings/SettingsView.swift:54-56` | Diagnostica è per lo sviluppatore | Accettabile come ultima tab | ⏳ |
| B5 | Impostazioni | 1 | 4 Coerenza | `Bubo/Settings/GeneralSettingsView.swift:23` | «chat nella bolla» | «conversazione nella Bolla» | ✅ |
| B6 | Modelli | 1 | 2 Corrispondenza | `Bubo/Settings/ModelsSettingsView.swift:31`, `:43` | «Apple FM» è una sigla interna | Testo esteso | ⏳ |
| B7 | Modelli | 1 | 7 Efficienza | `Bubo/Settings/ModelsSettingsView.swift:37` | Stepper a 0,01: fino a 50 clic | Passo 0,05 | ✅ |
| B8 | Barra dei menu | 1 | 4 Coerenza | `Bubo/MenuBar/MenuBarContent.swift:63` | «Mostra Panel» contro «Mostra il Panel con l'Orb» | «Mostra il Panel» | ✅ |
| B9 | Permessi | 1 | 6 Riconoscimento | `Bubo/Permissions/ProjectRuleSheet.swift:52` | Rimanda solo al pannello del Progetto | Citare Impostazioni › Permessi | ⏳ |
| B10 | Macchine (1.1) | 2 | 10 Aiuto | `Bubo/Settings/MachinesSettingsView.swift:16` | Stato vuoto senza istruzioni | Testo con il blocco da aggiungere | ⏳ |
| B11 | Casa → Domanda | 1 | 6 Riconoscimento | `Bubo/Question/QuestionView.swift:45-52` | «Trasforma in Sessione» attivo a campo vuoto | Disattivarlo senza testo né turni | ⏳ |
| B12 | Casa → Domanda | 1 | 3 Controllo | `Bubo/Question/QuestionView.swift:186` | «Chiudi la Domanda» nel dettaglio lascia una pagina vuota | Tornare al Cervello | ⏳ |
| B13 | Dal Cervello a una Sessione | 1 | 4 Coerenza | `Bubo/Question/SessionProposalButton.swift:29` | «Apri come Progetto e crea Sessione»: due verbi | «Nuova Sessione su …» | ⏳ |
| B14 | Nuovo Progetto | 1 | 4 Coerenza | `Bubo/Window/ProjectSessions.swift:30` | Stato vuoto senza pulsante | Azione «Nuova Sessione» | ⏳ |
| B15 | Seguire una Sessione | 1 | 1 Visibilità | `Bubo/Window/SessionDetail.swift:56` | «Sessione archiviata» non dice come continuare | «Sessione archiviata: riaprila dalla Cronologia» | ⏳ |
| B16 | Rivedere e fondere | 1 | 10 Aiuto | `Bubo/Review/ReviewSheet.swift:210` | Legenda di 8 scorciatoie | Tenere le 4 principali | ⏳ |
| B17 | Consegna | 1 | 2 Corrispondenza | `Bubo/HUD/DeliveryContents.swift:64` | «Subagent» | «Sotto-agenti» | ✅ |
| B18 | Palette | 1 | 2 Corrispondenza | `Bubo/Palette/PaletteView.swift:43` | Segnaposto con sintassi da ricordare | «Cerca comandi, conversazioni e note» | ⏳ |
| B19 | Terminale | 1 | 2 Corrispondenza | `Bubo/Terminal/TerminalPanel.swift:68` | «Riporta nell'HUD» | «Riporta nella finestra» | ✅ |
| B20 | Bolla | 1 | 1 Visibilità | `Bubo/Panel/PanelBubbleView.swift:79` | Avviso «Sessione non creata» con rimedio non eseguibile da lì | Accettabile | ⏳ |
| B21 | Pillola di stato | 1 | 2 Corrispondenza | `Bubo/Panel/PanelStatus.swift:37-38` | «2 ti attendono» senza soggetto | «2 Sessioni ti attendono» | ⏳ |
| B22 | Scorciatoie | 1 | 4 Coerenza | `Bubo/System/HotKeyCenter.swift:65` | «apre già la bolla» | Nome del comando | ✅ |
| B23 | Barra dei menu | 1 | 8 Minimalismo | `Bubo/App/AppDelegate.swift:307-308` | Clic destro sull'Orb = menu completo | Scelta voluta, nessuna correzione | ⏳ |
| B24 | Allegati | 1 | 9 Errori | `Bubo/Panel/OrbPanelController.swift:265-268` | Rilascio non allegabile torna indietro senza spiegare | Avviso nella Bolla | ⏳ |
| B25 | Allegati | 1 | 2 Corrispondenza | `Bubo/Panel/PanelStatus.swift:41` | «salvo nel cervello» non dice che nasce una Riunione | «Rilascia per farne una Riunione» | ✅ |
| B26 | Secondo cervello | 1 | 6 Riconoscimento | `Bubo/Panel/SecondBrainProposalCard.swift:27-28` | «Escluse», «Prioritarie» senza sostantivo | «Cartelle escluse», «Cartelle prioritarie» | ✅ |
| B27 | Comandi rapidi | 2 | 4 Coerenza | `Bubo/System/Intents/AskBuboIntent.swift:73` | File non di testo senza alternativa | «Trascinalo sull'Orb per allegarlo.» | ✅ |
| B28 | Visore | 1 | 9 Errori | `Bubo/Viewer/CodeViewerStore.swift:67` | «Non riesco a leggere il file.» senza motivo | «…forse è stato spostato o cancellato.» | ✅ |
| B29 | Allega finestra | 1 | 6 Riconoscimento | `Bubo/Panel/OrbPanelController.swift:216-218` | Procedura di 4 passi da ricordare | Testo più corto | ⏳ |
| B30 | Telecomando (1.1) | 2 | 8 Minimalismo | `Bubo/Settings/RemoteSettingsView.swift:17` | Consenso di 9 righe | Elenco dei dati in un gruppo espandibile | ⏳ |
| B31 | Telecomando (1.1) | 1 | 4 Coerenza | `Bubo/Settings/SettingsView.swift:36` | Tab «iPhone» contro «Telecomando» | Rinominare all'apertura dell'area | ⏳ |
| B32 | Sandbox (1.1) | 2 | 8 Minimalismo | `Bubo/Sandbox/ProjectSandboxSection.swift:22` | Paragrafo di 7 frasi | Testo dimezzato | ⏳ |
| B33 | Sandbox (1.1) | 1 | 4 Coerenza | `Bubo/Sandbox/SandboxBlock.swift:38-45` | «sandbox» minuscolo | «Sandbox» | ⏳ |
| B34 | Secondo cervello | 1 | 4 Coerenza | `Bubo/Settings/SecondBrainSettingsSection.swift:54` | «Claude salva» contro «Bubo salva» | «Bubo salva» | ✅ |
| B35 | Secondo cervello | 2 | 9 Recupero | `Bubo/Panel/SecondBrainProposalCard.swift:34` | Errore senza motivo né dove | Testo con causa e rimedio | ✅ |
| B36 | Indice | 1 | 2 Corrispondenza | `Bubo/Settings/ExcludedFoldersSection.swift:14` | «frammenti» è un dettaglio interno | Testo sull'effetto | ⏳ |
| B37 | Riunioni | 2 | 9 Recupero | `Bubo/Meetings/MeetingFailure.swift:48` | File illeggibile senza rimedio | Elenco dei formati accettati | ✅ |
| B38 | Riunioni | 1 | 8 Minimalismo | `Bubo/Meetings/MeetingView.swift:167` | Footer di 45 parole | Testo più corto | ⏳ |
| B39 | Riunioni | 1 | 4 Coerenza | `Bubo/Window/MainSidebar.swift:19` | «Riunioni» apre una finestra separata | Aiuto «Apre la finestra delle Riunioni» | ⏳ |
| B40 | Neuroni | 1 | 10 Aiuto | `Bubo/Neurons/NeuronView.swift:40` | Stato vuoto senza descrizione | Descrizione del passo successivo | ✅ |
| B41 | Automazione | 2 | 2 Corrispondenza | `Bubo/Automations/AutomationRow.swift:56` | «0 negate» sempre visibile | Solo se > 0, «N azioni negate» | ⏳ |
| B42 | Automazione | 1 | 10 Aiuto | `Bubo/Automations/AutomationsWindow.swift:77-78` | Stato vuoto non spiega cos'è un'Automazione | Titolo e descrizione nuovi | ✅ |
| B43 | Plugin | 2 | 9 Recupero | `Bubo/Plugins/InstallSheet.swift:150` | Errore grezzo di claude, spesso in inglese | Riga di contesto in italiano | ⏳ |
| B44 | Risorse di squadra | 2 | 2 Corrispondenza | `Bubo/Team/TeamResourcesSheet.swift:34` e altri | «allow», «deny» nell'interfaccia | «che consentono», «che negano» | ⏳ |

---

## Correzioni applicate

Un commit per flusso, in ordine:

| Commit | Flusso | Voci |
|---|---|---|
| `0f46025` | Sessioni, Board e fogli | A1, A2, A3, A4, M27, M28, B17, B19 |
| `2fbe8f1` | Casa → Domanda | A5, A6, A7, A26, M33 |
| `eb3f960` | Primo avvio | A8, A9, M1, M2 |
| `fcdcefb` | Aggiungere un Progetto, nuova Sessione | A10, M20, M21, M32 |
| `a76f3d7` | Bolla, scorciatoie, dettatura | A11, A12, M15, M16, M34, M35, M36, M38, B8, B22, B25 |
| `52f453b` | Secondo cervello e Riunioni | A15, A16, A17, A18, A27, A28, M8, M9, M46, M54, B26, B34, B35, B37, B40 |
| `1aee3a5` | Impostazioni e Account | A20, A21, A22, A30, M5, M6, M11, M18, B3, B5, B7 |
| `41bc0dd` | Anteprima, Visore, Galassia | A13, M43, M44, B28 |
| `0649edd` | Automazioni | A29, M48, M49, M50, B42 |
| `8dadf65` | Plugin e Server MCP | A31, M52, M53 |
| `b04c2aa` | Revisione del diff | A23 |
| `80ef7fe` | Comandi rapidi | A14, B27 |

Stima dopo le correzioni: finestra principale da 4 a 7, primo avvio e Impostazioni da 6 a 8, Secondo cervello da 6 a 8, Panel e Bolla da 7 a 8. Per arrivare a 10 restano le voci ⏳ ad alto impatto: A24 (azioni della Sessione fuori dal clic destro) e A25 («Riprendi» per le conversazioni CLI), poi M7 (tab «Secondo cervello»), M31 (Domande nella Palette) e M37 (pillola di stato col Panel normale).

Nessuna correzione cambia colori, font o stile visivo: sono testi, default, condizioni di visibilità, stati vuoti e d'errore, e il punto in cui sono agganciati fogli e controlli già esistenti.
