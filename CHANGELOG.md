# Novità di Bubo

Fonte delle note di rilascio (spec 27): `scripts/release/appcast.sh` le mette nell'appcast e la scheda Novità le legge dal bundle. Italiano, lingua di sviluppo; le altre lingue del String Catalog in `CHANGELOG.<lingua>.md`, con la stessa versione.

Regole, controllate a ogni release (la release si ferma se non tornano):

- una sezione per versione, `## X.Y.Z — AAAA-MM-GG` (le beta con il loro nome: `## 1.2.0-beta.1 — …`), la più recente in alto;
- dentro, solo `### Novità` (al massimo 3 punti, gli stessi della scheda), `### Correzioni`, `### Sicurezza`;
- una `### Sicurezza` con almeno un punto rende l'aggiornamento critico;
- ogni lingua ha la sezione di ogni versione.
