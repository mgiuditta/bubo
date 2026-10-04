// Controlla il set etichettato del router (#85): 20 richieste per Tipo, 10 in italiano e 10 in inglese,
// Categorie dell'enum Swift, Varianti del Catalogo. Uso: bun scripts/richieste-check.ts
import { readFileSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "..");
const read = (path: string) => readFileSync(join(root, path), "utf8");

type Richiesta = {
  id: string;
  lingua: "it" | "en";
  testo: string;
  tipo: string;
  categoria: string;
  variante: string | null;
  allegati?: string[];
};

const set: { versione: number; tipi: string[]; richieste: Richiesta[] } =
  JSON.parse(read("BuboTests/Fixtures/richieste-etichettate.json"));

// Le Categorie stanno in un solo posto: l'enum Swift.
const enumLine = read("Bubo/Catalogo/Categoria.swift").match(/^\s*case (.+)$/m);
const categorie = new Set(enumLine ? enumLine[1].split(",").map((name) => name.trim()) : []);
// Ogni Variante appartiene a una sola Categoria (CONTEXT.md): nome → Categoria dal Catalogo.
type Voce = { nome: string; categoria: string; ritirata?: string };
const voci: Voce[] = JSON.parse(read("Bubo/Catalogo/catalogo.json")).varianti;
const categoriaDi = new Map<string, string>(voci.map((v) => [v.nome, v.categoria]));
// Una Variante ritirata non si sceglie più (#401): non può essere l'etichetta giusta.
const ritirate = new Set(voci.filter((v) => v.ritirata !== undefined).map((v) => v.nome));

const errors: string[] = [];
const fail = (message: string) => errors.push(message);

if (set.versione !== 1) fail(`versione ${set.versione}, attesa 1`);
if (set.tipi.length !== 10) fail(`${set.tipi.length} Tipi, attesi 10`);
if (set.richieste.length !== 200) fail(`${set.richieste.length} richieste, attese 200`);
if (categorie.size !== 12) fail(`${categorie.size} Categorie lette da Categoria.swift, attese 12`);

const ids = new Set<string>();
const testi = new Set<string>();
const perTipo = new Map<string, { it: number; en: number }>(set.tipi.map((t) => [t, { it: 0, en: 0 }]));

for (const r of set.richieste) {
  if (!/^r\d{3}$/.test(r.id) || ids.has(r.id)) fail(`${r.id}: id non valido o doppio`);
  ids.add(r.id);
  if (!r.testo.trim() || testi.has(r.testo)) fail(`${r.id}: testo vuoto o doppio`);
  testi.add(r.testo);
  const conteggio = perTipo.get(r.tipo);
  if (!conteggio) fail(`${r.id}: Tipo sconosciuto ${r.tipo}`);
  else if (r.lingua === "it" || r.lingua === "en") conteggio[r.lingua]++;
  else fail(`${r.id}: lingua ${r.lingua}`);
  if (!categorie.has(r.categoria)) fail(`${r.id}: Categoria sconosciuta ${r.categoria}`);
  // null = nessuna Variante adatta nel Catalogo di oggi: l'Orb resta Blob con la Categoria.
  if (r.variante !== null) {
    const categoria = categoriaDi.get(r.variante);
    if (!categoria) fail(`${r.id}: Variante fuori dal Catalogo ${r.variante}`);
    else if (ritirate.has(r.variante)) fail(`${r.id}: Variante ritirata ${r.variante}`);
    else if (categoria !== r.categoria) fail(`${r.id}: Variante ${r.variante} è di ${categoria}, non di ${r.categoria}`);
  }
  if (r.allegati !== undefined && (!Array.isArray(r.allegati) || r.allegati.some((a) => !a.trim())))
    fail(`${r.id}: allegati non validi`);
}

for (const [tipo, { it, en }] of perTipo) {
  if (it !== 10 || en !== 10) fail(`${tipo}: ${it} it e ${en} en, attese 10 e 10`);
}

if (errors.length) {
  console.error(errors.join("\n"));
  process.exit(1);
}
console.log(`richieste: ok (${set.richieste.length}, ${set.tipi.length} Tipi, ${categorie.size} Categorie)`);
