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
