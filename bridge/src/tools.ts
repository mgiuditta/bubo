import { z } from "zod";

// Gli strumenti di Bubo che `claude` usa senza chiedere: `cerca` sempre, `ricorda` nelle Domande e nelle Sessioni,
// dove scrive nel Secondo cervello; ogni scrittura si può annullare da Bubo. Le Esecuzioni non lo ricevono.
export function allowedBuboTools(remembers: boolean): string[] {
  return remembers ? ["mcp__bubo__cerca", "mcp__bubo__ricorda"] : ["mcp__bubo__cerca"];
}

// Il prompt di sistema del turno: l'istruzione dell'Orb e poi il Profilo e le Regole del Secondo cervello, quelli
// che ci sono; senza nessuno dei due, `undefined`, e resta quello vuoto dell'SDK.
export function systemPromptOf(orb: string | undefined, brain: string | undefined): string | undefined {
  const parts = [orb, brain].filter((part): part is string => part !== undefined && part.length > 0);
  return parts.length > 0 ? parts.join("\n\n") : undefined;
}

// `cerca` e `ricorda`, gli stessi per `claude` (il server MCP `bubo`) e per `copilot` (strumenti della sessione di una
// Domanda): Bubo risponde a ogni chiamata con `found`.
// `cerca` chiede l'Indice a Bubo: i frammenti restano tra Bubo e il modello.
// `ricorda` fa scrivere a Bubo nel Secondo cervello: una nota nuova in `Bubo/Note/`, del testo in coda a una nota, o
// una nota riscritta; quelle dell'utente, fuori da `Bubo/`, solo dopo la sua conferma.
export const searchTool = {
  name: "cerca",
  description: "Cerca per parole nell'Indice di Bubo: la memoria di Claude Code di tutti i Progetti, il CLAUDE.md dell'utente, il suo Secondo cervello, la cartella di note Markdown che ha scelto (per esempio un vault Obsidian), e le conversazioni passate, delle Sessioni di Bubo e della riga di comando. Note e conversazioni non arrivano in nessun altro modo: cercale qui quando servono. Restituisce i frammenti con il percorso del file, o con la conversazione, chi ha scritto e la data; per le note del Secondo cervello anche la citazione [[…]] da mettere nella risposta dopo ogni affermazione che ne viene.",
  shape: {
    testo: z.string().describe("Le parole da cercare"),
    progetto: z.string().optional().describe("Percorso della cartella di un Progetto, per cercare solo nella sua memoria"),
    fonte: z.enum(["memoria", "secondo-cervello", "conversazioni"]).optional()
      .describe("Dove cercare: \"memoria\" (memoria dei Progetti e CLAUDE.md), \"secondo-cervello\" (le note dell'utente) o \"conversazioni\" (le conversazioni passate); senza, ovunque"),
  },
};

export const rememberTool = {
  name: "ricorda",
  description: "Scrive nel Secondo cervello dell'utente, la sua cartella di note Markdown. Usalo quando l'utente chiede di ricordare qualcosa (\"ricordati questo\", \"segnati che…\") o quando il prompt di sistema ti dice di salvare da solo. Modi: \"nuova\" crea una nota in Bubo/Note con titolo; \"aggiungi\" mette il testo in coda alla nota indicata; \"riscrivi\" sostituisce tutta la nota indicata. Le note fuori da Bubo/ sono dell'utente: per riscriverle chiedigli prima e passa confermato solo se ha detto di sì. Anche ogni modifica di Bubo/Profilo.md vuole la conferma dell'utente; Bubo/Regole.md e Bubo/Intervista.md non si scrivono mai. Non cancella note. L'utente può annullare ogni scrittura. Restituisce dove ha scritto, o perché non l'ha fatto.",
  shape: {
    testo: z.string().describe("Cosa scrivere, in Markdown, comprensibile anche letto da solo tra mesi"),
    modo: z.enum(["nuova", "aggiungi", "riscrivi"]).optional().describe("Come scrivere; senza, \"nuova\""),
    titolo: z.string().optional().describe("Per una nota nuova: un titolo breve, che diventa il nome del file"),
    nota: z.string().optional().describe("Per aggiungere o riscrivere: il percorso della nota .md relativo al Secondo cervello, per esempio Bubo/Profilo.md"),
    confermato: z.boolean().optional().describe("Solo dopo che l'utente ha detto di sì a riscrivere una sua nota fuori da Bubo/"),
  },
};

export type SearchArguments = z.infer<z.ZodObject<typeof searchTool.shape>>;
export type RememberArguments = z.infer<z.ZodObject<typeof rememberTool.shape>>;

/** Una chiamata a `cerca` o `ricorda` per Bubo, senza l'`id` con cui torna il suo `found`. */
export type BuboToolCall =
  | { type: "search"; query: string; project?: string; source?: string; conversation: string }
  | { type: "remember"; conversation: string; mode: "nuova" | "aggiungi" | "riscrivi"; title?: string; note?: string; text: string; confirmed?: boolean };

/** La chiamata a `cerca` della conversazione `conversation`, per la riga "Richiamato". */
export function searchCall({ testo, progetto, fonte }: SearchArguments, conversation: string): BuboToolCall {
  return { type: "search", query: testo, project: progetto, source: fonte, conversation };
}

/** La chiamata a `ricorda` della conversazione `conversation`: la scrittura va nel registro e si può annullare. */
export function rememberCall({ testo, modo, titolo, nota, confermato }: RememberArguments, conversation: string): BuboToolCall {
  return { type: "remember", conversation, mode: modo ?? "nuova", title: titolo, note: nota, text: testo, confirmed: confermato };
}
