// Gli strumenti di Bubo che `claude` usa senza chiedere: `cerca` sempre, `ricorda` solo nelle Domande,
// dove "Ricordati questo" va nel Secondo cervello. In una Sessione lo salva l'agente nella Memoria di Progetto.
export function allowedBuboTools(remembers: boolean): string[] {
  return remembers ? ["mcp__bubo__cerca", "mcp__bubo__ricorda"] : ["mcp__bubo__cerca"];
}
