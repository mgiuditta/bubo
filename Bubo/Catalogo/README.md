# Aggiungere un blocco di Varianti

Il Catalogo cresce a blocchi: poche Varianti per volta, ciascuna con la sua Forma scritta a mano (ADR 0002). Per ogni Variante del blocco:

1. **SDF.** In `Bubo/Orb/Orb.metal` scrivi `static float <forma>(float3 p)` nella sezione Forme e aggiungi `case N: return <forma>(q);` allo `switch` di `forma()`, con `N` nuovo. L'SDF deve essere quasi esatto fuori dal solido (gradiente vicino a 1): l'alone legge la distanza minima del raggio e una sottostima si vede come striature. Scale uniformi, niente deformazioni non isometriche.
2. **Forma.** In `Bubo/Orb/Forma.swift` aggiungi il caso con lo stesso nome e `functionConstant` uguale a `N`. L'archivio Metal 4 della Release legge i `case` da solo (`scripts/metal-archive.sh`).
3. **Voce nel JSON.** In `catalogo.json` aggiungi `nome` (italiano, kebab-case, ASCII, stabile), `forma`, `categoria`, `descrizione` (quando sceglierla) e da 3 a 8 `parole`. Una Forma serve una sola Variante: i sinonimi vanno in `parole`, non in Varianti nuove.
4. **Etichetta.** In `Catalogo.xcstrings` aggiungi la chiave `nome` con il nome mostrato in italiano e in inglese.
5. **Test verde.** `scripts/check.sh`: `CatalogoTests` verifica le regole della voce, che ogni `forma` abbia il suo SDF e il suo `case` e che ogni Variante abbia l'etichetta.
6. **Galleria.** Build Debug, menu di Bubo › Debug Orb… › Galleria. Filtra per la Categoria del blocco e controlla ogni Variante: la silhouette si legge a 64 pt in monocromo; nella vista grande l'alone è pulito, senza striature, e il Morph dal Blob e verso il Blob è fluido.
