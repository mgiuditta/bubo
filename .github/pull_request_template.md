Closes #

-

## Rifinitura

Definizione di "fatto" per ogni PR che tocca l'interfaccia ([spec 27](../docs/features/27-rifinitura-aggiornamenti.md#audit-di-rifinitura-deciso)). Se la PR non tocca l'interfaccia, cancella questa sezione. `scripts/check.sh` controlla da solo le voci segnate con (auto).

- [ ] **Stati**: vuoto, caricamento ed errore disegnati; ogni attesa usa `LoadingLabel`, nessuno spinner oltre 1 s senza testo (auto: niente `ProgressView` fuori da `Design/LoadingLabel`).
- [ ] **Errori**: ogni errore usa `ErrorNotice`: cosa è successo, cosa fare, un'azione.
- [ ] **Movimento**: contenitore 150–250 ms, solo l'Orb respira, Riduci movimento onorato ([design-system](../docs/design-system.md#movimento)) (auto: durate solo dai token di `Design/Motion`).
- [ ] **Icona**: tutte le misure, più il glifo della barra dei menu (auto: 10 misure dell'icona).
- [ ] **Menu**: menu dell'app completi, scorciatoie senza conflitti (auto: `MainMenuTests`).
- [ ] **Accessibilità**: VoiceOver, tastiera e contrasto AA; 0 problemi dall'audit (auto: `AccessibilityAuditTests` su HUD, Panel e Impostazioni).
- [ ] **Stringhe**: 0 stringhe fuori dal String Catalog, 0 traduzioni mancanti (auto: `polish-check.sh`).
- [ ] **Prestazioni**: budget di [#186](https://github.com/mgiuditta/bubo/issues/186) rispettati.
