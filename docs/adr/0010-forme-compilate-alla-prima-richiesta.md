# Una Forma per file, compilata alla prima richiesta

Con 13 Forme in `Orb.metal` e una pipeline ciascuna, scelta dalla function constant `FORMA`, l'archivio Metal 4 della Release pesava circa 11 MB (#355). Il Catalogo ne vuole circa 500 (ADR 0002). Abbiamo scelto:

- **un file per Forma**: `Bubo/Orb/Forme/<forma>.metal` scrive il suo SDF e finisce con `ORB_FORMA(<forma>)`. La macro di `OrbShading.h` crea la funzione di frammento `forma_<forma>` (il Blob fuso con quella Forma) e, solo nel bundle dei test, il kernel `probe_<forma>`. Lo `switch`, la function constant e l'enum Swift spariscono: `Forma` è un nome, e la pipeline nasce dalla funzione con quel nome. Aggiungere una Forma tocca il suo file, una voce di `catalogo.json` (con la sua etichetta) e i campioni di `FormaTests`;
- **pipeline compilate a runtime alla prima richiesta** con `MTL4Compiler`, tenute in memoria da `OrbPipelines`. Metal le salva nella sua cache degli shader, quindi dal secondo avvio arrivano in meno di un millisecondo;
- **solo il Blob nell'archivio Metal 4**, che resta di 0,5 MB qualunque sia il numero di Forme. L'archivio ha una libreria sua, `Orb.metallib`, fatta del solo `Orb.metal`, per due motivi misurati: `metal-tt` compila ogni funzione della libreria che riceve (archiviare il Blob dalla libreria completa costa 113 MB a 500 Forme), e a runtime l'archivio trova la pipeline solo con la stessa libreria da cui è nato (con la libreria completa la ricerca fallisce).

## Misure

Su questo Mac (M4 Max, 14 core, Xcode 26.6, SDK macOS 26.5), con Forme finte generate da uno script: ognuna è un'unione di 5–15 primitive esatte prese da quelle delle Forme vere, con un moto proprio nel 60% dei casi. Pesano circa il 10% più delle vere (0,30 MB di archivio per pipeline contro 0,27). Il primo Morph è misurato su Forme mai compilate (seme nuovo a ogni giro, così la cache di Metal è fredda). La GPU disegna 600 × 600 px, Morph a 1, mediana su 600 fotogrammi.

Le alternative:

- **A**: com'era. Un frammento con `switch (FORMA)` e tutte le pipeline nell'archivio.
- **B**: come A, ma senza archivio: si compila la specializzazione alla prima richiesta.
- **C**: un file e una funzione di frammento per Forma, compilata alla prima richiesta. È la scelta.
- **D**: una sola pipeline generica, con lo `switch` su un indice passato negli uniform.

| | 13 | 50 | 200 | 500 |
|---|---|---|---|---|
| **Dimensione** delle risorse Metal | | | | |
| A: archivio | 17 MB | 139 MB | 1,8 GB | ≈ 11,5 GB (stima su 21 pipeline) |
| A con un file per Forma, tutto archiviato | 7,0 MB | 25 MB | 101 MB | ≈ 255 MB (stima) |
| B, D: libreria | 0,05 MB | 0,16 MB | 0,6 MB | 1,5 MB |
| **C**: libreria + archivio del Blob | 0,7 MB | 1,3 MB | 3,7 MB | 8,4 MB |
| **Build** (compilazione Metal) | | | | |
| A: solo l'archivio, in più | 4,2 s | 15 s | 76 s | ≈ 3 min (stima) |
| B, D: un file, ricompilato per ogni modifica | 0,2 s | 0,5 s | 0,6 s | 1,3 s |
| **C**: tutto, in parallelo | 0,5 s | 0,8 s | 1,7 s | 4,3 s |
| **C**: una Forma modificata | 0,3 s | 0,2 s | 0,3 s | 0,7 s |
| **Primo Morph** verso una Forma mai vista | | | | |
| A: pipeline dall'archivio | 0,3 ms | 0,1 ms | 24 ms | 43 ms |
| B: compilazione della specializzazione | 50 ms | 46 ms | 56 ms | 76 ms |
| **C**: compilazione | 35 ms | 36 ms | 33 ms | 33 ms |
| **C**: la prima dopo l'avvio (compilatore ancora freddo) | 75 ms | 73 ms | 62 ms | 57 ms |
| **C**: secondo avvio (cache di Metal) | 0,2 ms | 0,1 ms | 0,1 ms | 0,1 ms |
| D: l'unica compilazione, per tutte | 149 ms | 353 ms | 2,2 s | 6,6 s |
| **Memoria** (phys_footprint) | | | | |
| A: dopo 5 pipeline dall'archivio | 1,2 MB | 1,2 MB | 3,8 MB | 5,8 MB |
| B: per pipeline | 0,41 MB | 0,53 MB | 0,97 MB | 1,09 MB |
| **C**: per pipeline | 0,33 MB | 0,31 MB | 0,31 MB | 0,31 MB |
| **GPU** per fotogramma | | | | |
| A, B, C (lo stesso codice compilato) | 0,9 ms | 0,7 ms | 0,8 ms | 1,05 ms |
| D | 0,8 ms | 0,75 ms | 1,0 ms | 1,26 ms |

Nell'app vera, con 500 Forme finte copiate in `Forme/`: la build Release che le aggiunge dura 9,9 s (43 s di compilazione Metal, distribuiti sui core), una Forma modificata aggiunge 1,1 s a una build senza modifiche, e l'app cresce da 168,8 a 176,8 MB: la libreria passa da 0,25 a 8,3 MB, l'archivio del Blob resta di 0,5 MB. Con le 13 Forme di oggi l'app è circa 10 MB più leggera di prima. Nella stessa libreria, la prima Forma dopo l'avvio si compila in 75 ms e le successive in 31 ms.

A non regge: l'archivio cresce più che in proporzione e già a 200 Forme supera l'app intera. B costa poco ma tiene un solo file, che i blocchi paralleli si contenderebbero, e compila sempre più lento. D fallisce il primo Morph dai 200 in su e rallenta ogni fotogramma del 20%. C resta piatto su tutto, tranne la libreria, che cresce di 16 KB per Forma.

## Budget

Li controlla chi cambia `OrbShading.h` o il modo di costruire le pipeline, rifacendo le misure:

- **App**: risorse Metal ≤ 10 MB a 500 Forme (misurati 8,8 MB nell'app);
- **Build**: compilazione Metal di tutte le Forme ≤ 15 s di orologio (9,9 s), una Forma modificata ≤ 2 s (1,1 s);
- **Primo Morph** verso una Forma mai usata: compilazione della pipeline ≤ 300 ms. «09 — Sistema» chiede l'inizio del Morph entro 600 ms col classificatore finale, e la classificazione ne prende fino a 300. Misurati 75 ms nel caso peggiore, la prima Forma dopo l'avvio, su un M4 Max. Il margine di 4 volte deve coprire i Mac più lenti, che non abbiamo misurato: l'intervallo di signpost «Compilazione Forma» (Points of Interest) lo misura sul campo, e un errore di compilazione finisce nel log `orb` e si ritenta alla scelta successiva della stessa Variante. Intanto l'Orb resta Blob: un Morph Variante → Variante parte con la mezza gamba verso il Blob, di 0,55 s, che nasconde l'attesa;
- **Memoria**: 0,31 MB per ogni Forma già usata. Le pipeline non vengono mai liberate: una sessione che usasse tutte le 500 Forme terrebbe 155 MB. Lo accettiamo perché una sessione ne usa poche; se servirà, una cache con un tetto andrà in `OrbPipelines`.

Limiti accettati: la chiave della cache di Metal dipende dalla libreria intera (lo mostra la ricerca nell'archivio), quindi dopo un aggiornamento che cambia gli shader il primo uso di ogni Forma costa di nuovo 35–75 ms. In Debug non c'è archivio e anche il Blob si compila all'avvio (circa 60–80 ms la prima volta). Decisione presa in [Catalogo: Forme che reggono 500 Varianti](https://github.com/mgiuditta/bubo/issues/378). Le misure si rifanno con `scripts/forme-bench/run_all.sh`.
