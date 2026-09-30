// Carico di prova per bridge-speed.sh: un ciclo caldo che sotto hardened runtime senza allow-jit
// gira ~50× più lento (spec 27). Stampa solo i millisecondi del ciclo, avvio escluso.
const iterations = Number(process.argv[2] ?? 50_000_000);
const start = performance.now();
let sum = 0;
for (let i = 0; i < iterations; i++) sum = (sum + i * 7) % 1_000_003;
const elapsed = performance.now() - start;
if (sum < 0) console.error(sum); // tiene vivo il risultato
console.log(elapsed.toFixed(1));
