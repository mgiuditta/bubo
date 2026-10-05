# Copilot alla pari nelle Domande

**Stato: Accettato** (2026-10-05, mappa #717). Sostituisce in parte [ADR 0011](0011-copilot-solo-per-le-domande.md) (la Domanda Copilot «senza tool» e «Utenti solo Copilot») e completa [ADR 0012](0012-copilot-cli-motore-di-sessione.md).

Un collega ha solo Copilot CLI. Oggi Bubo senza `claude` si blocca: l'onboarding resta sul rimedio, e nemmeno Copilot parte, perché il ponte esige `claude`. I lavori recenti «come la riga di comando» (permessi, cancello sui livelli 4–5, domande dell'agente) valgono solo per Claude, e per ADR 0011 la Domanda Copilot non ha strumenti. Così Copilot è un motore di serie B.

- **Parità nella Domanda.** Una Domanda Copilot ha gli strumenti e le Regole dell'utente che `copilot` ha nel terminale. Passa dallo stesso cancello: chiede solo sui livelli di rischio 4–5. Le domande dell'agente (`ask_user`) compaiono nella stessa vista di quelle di Claude, e gli Allegati arrivano anche a Copilot.
- **Cancello anche nelle Sessioni Copilot.** Le Richieste di permesso di una Sessione Copilot passano dallo stesso cancello 4–5 di Claude.
- **Motore principale.** All'onboarding l'utente sceglie Claude, Copilot o Entrambi. Con Entrambi indica un principale; l'altro fa da riserva. Domande e Sessioni partono sul principale. Gli utenti esistenti restano su Claude. La scelta si cambia in Impostazioni › Modelli › «Motore principale».
- **Riserva solo per Quota o limite.** Si passa all'altro motore solo quando il principale ha finito la Quota o ha raggiunto un limite, mai per rete, login o binario mancante: quelli si correggono, non si aggirano. Una Domanda cambia motore da sola, con una riga di avviso. Una Sessione si ferma e offre «Continua con …», che apre una nuova Sessione sull'altro motore con il prompt e un riassunto. La Domanda successiva riprova il principale.
- **Solo Copilot.** Chi non ha `claude` può usare tutto Bubo. I turni automatici (Automazioni, titoli, classificazione) seguono il principale. Le voci che esistono solo con Claude spariscono invece di dire «Non disponibile», e la pill della Quota mostra la Spesa Copilot.

Scartate: tenere la Domanda Copilot senza strumenti (lascia chi ha solo Copilot con un assistente che non sa fare niente); la riserva anche su errori di rete o di login (nasconde guasti che l'utente deve vedere e sposta i contenuti a un altro fornitore senza motivo); continuare la stessa Sessione sull'altro motore (le Conversazioni dell'agente dei due motori non si riprendono a vicenda).

Riserve di ADR 0011 che restano: niente Copilot Free, consenso privacy per fornitore (ora chiesto all'onboarding), token GitHub tolti dall'ambiente del figlio. Cade invece il divieto di usare Copilot per il lavoro in background, ma solo per chi lo sceglie come principale.

Da verificare: i codici d'errore di quota e limite di Copilot (premium request esaurite) sull'SDK 1.0.16.
