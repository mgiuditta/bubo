// Il residuo del Budget come arriva da Bubo (spec 18): solo un numero finito e positivo diventa `maxBudgetUsd`.
// Altrimenti nessun tetto: Bubo non manda mai un turno con il residuo a zero, quindi un valore strano non blocca.
export function budgetOf(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : undefined;
}
