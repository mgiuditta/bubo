// Misura le citazioni delle Domande sul Secondo cervello (#546): su 20 domande, almeno 16 risposte devono citare
// la nota giusta come [[nota]] (per una Riunione anche il minuto, con 2 minuti di tolleranza).
//
// I due file stanno fuori dal repo, perché parlano delle note dell'utente:
// - il set, 20 righe { "id", "domanda", "nota", "minuto"? }: `nota` è il percorso nel Secondo cervello senza `.md`
//   (come lo scrive `cerca` dopo "Cita come"), `minuto` è "MM:SS" o "HH:MM:SS" per le Riunioni;
// - le risposte, un oggetto { "<id>": "<testo della risposta di Bubo>" }, copiate dalla bolla dopo ogni Domanda.
//
// Uso: bun scripts/citazioni-misura.ts ~/set-citazioni.json ~/risposte-citazioni.json
import { readFileSync } from "node:fs";

type Domanda = { id: string; domanda: string; nota: string; minuto?: string };

const [setPath, answersPath] = process.argv.slice(2);
if (!setPath || !answersPath) {
  console.error("Uso: bun scripts/citazioni-misura.ts <set.json> <risposte.json>");
  process.exit(2);
}
const set: Domanda[] = JSON.parse(readFileSync(setPath, "utf8"));
const answers: Record<string, string> = JSON.parse(readFileSync(answersPath, "utf8"));

// Le citazioni di una risposta: nota e punto, senza l'alias dopo |.
function citations(answer: string): { nota: string; punto?: string }[] {
  return [...answer.matchAll(/\[\[([^\[\]\n]+)\]\]/g)].map(([, inner]) => {
    const [nota, punto] = inner.split("|")[0].split("#");
    return { nota: nota.trim(), punto: punto?.trim() || undefined };
  });
}

// Una citazione per nome trova la nota come fa Obsidian: basta l'ultimo pezzo del percorso.
const sameNote = (cited: string, expected: string) =>
  cited.toLowerCase() === expected.toLowerCase()
  || (!cited.includes("/") && expected.toLowerCase().endsWith("/" + cited.toLowerCase()));

const seconds = (time: string) => time.split(":").map(Number).reduce((total, part) => total * 60 + part, 0);

let correct = 0;
for (const domanda of set) {
  const answer = answers[domanda.id];
  const found = answer === undefined ? [] : citations(answer);
  const right = found.some(({ nota, punto }) => sameNote(nota, domanda.nota)
    && (!domanda.minuto || (punto !== undefined && Math.abs(seconds(punto) - seconds(domanda.minuto)) <= 120)));
  if (right) correct++;
  const cited = found.map(({ nota, punto }) => punto ? `${nota}#${punto}` : nota).join(", ") || "nessuna";
  console.log(`${right ? "ok " : "NO "} ${domanda.id}  atteso ${domanda.nota}${domanda.minuto ? "#" + domanda.minuto : ""}  citato ${answer === undefined ? "(risposta mancante)" : cited}`);
}

const needed = Math.ceil(set.length * 0.8);
console.log(`\n${correct}/${set.length} citazioni corrette; servono almeno ${needed}.`);
process.exit(set.length === 20 && correct >= needed ? 0 : 1);
