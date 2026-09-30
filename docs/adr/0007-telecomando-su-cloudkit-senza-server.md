# Il Telecomando passa da CloudKit, senza server e senza Remote Control

L'app iPhone di Bubo (feature 21) deve far vedere le Sessioni del Mac e far decidere le Richieste di permesso da lontano. Remote Control di Claude Code lo fa già per le sessioni interattive della CLI, ma non si aggancia alle Sessioni dell'Agent SDK, richiede un abbonamento e tiene la trascrizione sui server Anthropic senza cifratura end-to-end. Tutti i concorrenti passano da un relay del fornitore; Bubo non ha server e non vuole averne.

Abbiamo scelto:

- **App iPhone di Bubo** (il Telecomando), non un'integrazione con Remote Control. Chi usa `claude --rc` continua con l'app Claude.
- **Trasporto sul database privato CloudKit** dell'utente: record scritti dal Mac e dall'iPhone, push visibili dalle subscription. Nessun server, nessun relay, nessuna chiave APNs nel bundle.
- **Cifratura propria**: una chiave per coppia Mac–iPhone concordata all'accoppiamento (QR + codice a 6 cifre); in CloudKit solo testo cifrato. Non dipende dalla Protezione avanzata dei dati.
- **Verdetti firmati** nel Secure Enclave con Face ID; il Mac scarta firme sconosciute, scadute o già risolte.

Limiti accettati: latenza best effort (CloudKit non la documenta), niente Live Activity (servirebbe un server APNs), stesso Apple ID obbligatorio. Il primo ticket di costruzione misura 100 push con una build Developer ID: se p50 > 5 s o p95 > 30 s si ripiega sul Telecomando in rete locale (Bonjour, solo in primo piano) con un nuovo ADR; se CloudKit non funziona con Developer ID, la 21 si ferma e la questione del relay si riapre. Decisione presa in [iPhone compagna: cosa entra in v1](https://github.com/mgiuditta/bubo/issues/235).
