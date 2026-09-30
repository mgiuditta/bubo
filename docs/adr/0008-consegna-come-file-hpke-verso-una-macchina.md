# La Consegna è un file cifrato con HPKE auth verso una Macchina

La feature 24 passa una Sessione a un altro utente Bubo, che la riprende col proprio account. Tutti i concorrenti lo fanno dal proprio server senza cifratura end-to-end; Bubo non ha server. I canali dell'utente con una ricevuta o una revoca (CKShare, git) sono end-to-end solo con la Protezione avanzata dei dati per tutti, oppure non revocano davvero.

Abbiamo scelto:

- **Un file `.bubo`** mandato col Condividi di macOS (AirDrop, Messaggi, Mail, Salva sul disco…), un destinatario per volta. CKShare si potrà aggiungere dopo con lo stesso formato.
- **HPKE di CryptoKit in modalità auth**, suite P-256: il file è leggibile solo dal destinatario e dimostra chi l'ha mandato. age non autentica il mittente.
- **Una chiave per Macchina nel Secure Enclave**, non esportabile. Si consegna a una Macchina, non a una persona; riceve solo un Mac con Bubo.
- **Biglietto scambiato nei due sensi** con un codice di verifica di 12 cifre letto a voce: il canale del Biglietto è qualunque, quindi la verifica fa tutta la differenza.
- **In chiaro** solo tipo, versione, identificativi delle due chiavi e peso, legati al contenuto come dato associato.

Limiti accettati: niente ricevuta, revoca o scadenza ("una volta consegnata, è sua"); un Mac reinstallato perde la chiave e le Consegne in viaggio; serve scambiarsi i Biglietti prima. Il primo ticket di costruzione prova HPKE auth con entrambe le chiavi nel Secure Enclave: se il Secure Enclave non funziona come mittente, la chiave va nel Portachiavi del Mac (`ThisDeviceOnly`) con un emendamento a questo ADR. Decisione presa in [Consegna, risorse di squadra e dal vivo: cosa entra in v2](https://github.com/mgiuditta/bubo/issues/267), dettagli dal [prototipo](https://github.com/mgiuditta/bubo/issues/268).
