# Bubo conserva le conversazioni oltre la pulizia di Claude Code

Claude Code cancella transcript, subagent e file-history dopo `cleanupPeriodDays` (30 giorni di default). La regola vale anche per le conversazioni avviate da un'app sull'SDK come Bubo; le sessioni di Claude Desktop sono esenti, le nostre no. Senza intervento, una Sessione vecchia si troverebbe nell'Indice ma non si potrebbe riaprire né riprendere, e l'Indice smetterebbe di essere ricostruibile.

Abbiamo scelto:

- **Copia a specchio con `sessionStore`**: ogni Conversazione dell'agente di Bubo viene copiata nel database locale di Bubo, che non la cancella mai. La ripresa legge da lì.
- **Anche la Cronologia CLI**, di default: Bubo copia le conversazioni della riga di comando (`importSessionToStore`) quando le vede per la prima volta. Un interruttore nelle Impostazioni lo spegne e cancella le copie.
- **Nessuna modifica ai settaggi dell'utente**: `cleanupPeriodDays` resta com'è. Alzarlo con `Options.settings` avrebbe cambiato anche la conservazione della CLI, che è globale.
- **Per sempre**: nessun tetto. Lo spazio occupato si vede nelle Impostazioni; eliminare una Sessione in Bubo elimina la sua copia.

Limiti accettati: la file-history non entra nello store, quindi una Sessione di oltre 30 giorni si riprende ma non si riavvolge sui file. `sessionStore` è in alpha: la versione dell'SDK resta fissata, e se l'API cambia il ripiego è copiare il JSONL alla fine di ogni turno, con gli stessi dati. Decisione presa in [Conservazione delle conversazioni oltre i 30 giorni](https://github.com/mgiuditta/bubo/issues/138).
