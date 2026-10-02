// Gli strumenti dell'Anteprima (spec 15): un server MCP nel ponte che inoltra ogni chiamata a Bubo, dove
// `Preview/PreviewDriver` pilota la stessa pagina dell'utente. Esiste solo se la Sessione ha un server rilevato:
// senza, la sua descrizione non entra nel contesto.
import { createSdkMcpServer, tool, type McpServerConfig, type Query } from "@anthropic-ai/claude-agent-sdk";
import { randomUUID } from "node:crypto";
import { z } from "zod";

export const previewServerName = "anteprima";

// Livello 1 Lettura: girano senza Richiesta. Gli altri (Livello 2) passano da Bubo come ogni strumento.
const readTools = ["screenshot", "dom", "console", "rete"];
export const allowedPreviewTools = readTools.map((name) => `mcp__${previewServerName}__${name}`);

// Bubo chiude ogni azione a 10 s; il ponte aspetta un secondo in più, poi lascia perdere.
export const previewTimeout = 11_000;

// Una chiamata per Bubo: il nome dello strumento e i suoi argomenti, già con i nomi del protocollo.
export type PreviewCall = {
  type: "previewCall";
  call: string;
  tool: string;
  selector?: string;
  text?: string;
  url?: string;
  filter?: string;
  code?: string;
  y?: number;
};

type ToolResult = {
  content: ({ type: "text"; text: string } | { type: "image"; data: string; mimeType: string })[];
  isError?: boolean;
};

function failure(text: string): ToolResult {
  return { content: [{ type: "text", text }], isError: true };
}

// La risposta di Bubo come risultato MCP: un'immagine JPEG in base64, un testo o un errore.
export function previewResult(reply: { text?: unknown; image?: unknown; error?: unknown }): ToolResult {
  if (typeof reply.error === "string") return failure(reply.error);
  if (typeof reply.image === "string") return { content: [{ type: "image", data: reply.image, mimeType: "image/jpeg" }] };
  if (typeof reply.text === "string") return { content: [{ type: "text", text: reply.text }] };
  return failure("Risposta dell'Anteprima non valida.");
}

// Le chiamate in attesa della risposta di Bubo, ciascuna con il suo tempo limite.
export class PreviewCalls {
  private readonly pending = new Map<string, (result: ToolResult) => void>();

  constructor(private readonly send: (conversation: string, call: PreviewCall) => void, private readonly timeout = previewTimeout) {}

  call(conversation: string, fields: Omit<PreviewCall, "type" | "call">): Promise<ToolResult> {
    const call = randomUUID();
    return new Promise((resolve) => {
      const timer = setTimeout(() => this.finish(call, failure("L'Anteprima non ha risposto entro 10 s.")), this.timeout);
      this.pending.set(call, (result) => { clearTimeout(timer); resolve(result); });
      try {
        this.send(conversation, { type: "previewCall", call, ...fields });
      } catch {
        this.finish(call, failure("Bubo non è raggiungibile."));
      }
    });
  }

  answer(call: unknown, reply: { text?: unknown; image?: unknown; error?: unknown }) {
    if (typeof call === "string") this.finish(call, previewResult(reply));
  }

  private finish(call: string, result: ToolResult) {
    const resolve = this.pending.get(call);
    this.pending.delete(call);
    resolve?.(result);
  }
}

// Il server della conversazione `conversation`. Uno per conversazione: un'istanza MCP si collega a un solo trasporto.
export function previewTools(conversation: string, calls: PreviewCalls) {
  const forward = (fields: Omit<PreviewCall, "type" | "call">) => calls.call(conversation, fields);
  const read = { annotations: { readOnlyHint: true } };
  return createSdkMcpServer({
    name: previewServerName,
    tools: [
      tool("screenshot", "Fotografa l'Anteprima della Sessione, la pagina del suo server localhost che vede anche l'utente. Lato lungo al massimo 1568 px.",
        {}, () => forward({ tool: "screenshot" }), read),
      tool("dom", "L'HTML della pagina dell'Anteprima, o dell'elemento indicato, troncato.",
        { selettore: z.string().optional().describe("Selettore CSS dell'elemento; senza, tutta la pagina") },
        ({ selettore }) => forward({ tool: "dom", selector: selettore }), read),
      tool("console", "Le ultime 200 righe della console della pagina dell'Anteprima.",
        { filtro: z.string().optional().describe("Solo le righe che contengono questo testo") },
        ({ filtro }) => forward({ tool: "console", filter: filtro }), read),
      tool("rete", "Le ultime 200 richieste della pagina dell'Anteprima (fetch, XHR e risorse caricate), con stato e durata.",
        { filtro: z.string().optional().describe("Solo le richieste che contengono questo testo") },
        ({ filtro }) => forward({ tool: "rete", filter: filtro }), read),
      tool("naviga", "Apre nell'Anteprima un indirizzo dei server localhost della Sessione; un percorso relativo parte dalla pagina aperta. Ogni altro indirizzo fallisce.",
        { url: z.string().describe("Indirizzo o percorso, per esempio /login") },
        ({ url }) => forward({ tool: "naviga", url })),
      tool("clicca", "Clicca l'elemento indicato nella pagina dell'Anteprima e aspetta l'eventuale caricamento.",
        { selettore: z.string().describe("Selettore CSS dell'elemento") },
        ({ selettore }) => forward({ tool: "clicca", selector: selettore })),
      tool("compila", "Scrive un testo nel campo indicato della pagina dell'Anteprima, al posto del contenuto.",
        { selettore: z.string().describe("Selettore CSS del campo"), testo: z.string().describe("Il testo da scrivere") },
        ({ selettore, testo }) => forward({ tool: "compila", selector: selettore, text: testo })),
      tool("scorri", "Scorre la pagina dell'Anteprima fino all'elemento indicato, o di un numero di pixel in verticale.",
        { selettore: z.string().optional().describe("Selettore CSS dell'elemento da mostrare"), y: z.number().optional().describe("Pixel in verticale, negativi verso l'alto") },
        ({ selettore, y }) => forward({ tool: "scorri", selector: selettore, y })),
      tool("esegui_js", "Esegue JavaScript nella pagina dell'Anteprima, in un mondo separato dagli script della pagina: vede il DOM, non le sue variabili. Restituisce in JSON il valore di return.",
        { codice: z.string().describe("Il corpo di una funzione, con return per il risultato") },
        ({ codice }) => forward({ tool: "esegui_js", code: codice })),
    ],
  });
}

// I server dinamici di un turno: sempre `bubo`, più l'Anteprima quando la Sessione ha un server.
export function turnServers(bubo: McpServerConfig, preview?: McpServerConfig): Record<string, McpServerConfig> {
  return preview ? { bubo, [previewServerName]: preview } : { bubo };
}

// Aggiunge o toglie l'Anteprima a turno in corso. `setMcpServers` sostituisce tutti i server dinamici: senza `bubo`
// sparirebbe `cerca`. Un server già registrato con lo stesso nome resta collegato com'è.
export async function offerPreview(conversation: Pick<Query, "setMcpServers">, bubo: McpServerConfig, preview?: McpServerConfig) {
  try {
    const result = await conversation.setMcpServers(turnServers(bubo, preview));
    for (const [name, error] of Object.entries(result.errors)) console.error(`Server ${name} non collegato:`, error);
  } catch (error) {
    console.error("Strumenti dell'Anteprima non aggiornati:", error instanceof Error ? error.message : error);
  }
}
