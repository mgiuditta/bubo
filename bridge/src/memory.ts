// La memoria automatica (`~/.claude/projects/<repo>/memory/`) è la Memoria di Progetto: accesa dove c'è un Progetto,
// nelle Sessioni e nell'ispezione, come nella CLI; spenta nelle Domande, che non devono ereditare i ricordi del
// repo da cui partono (spec 13).
export function withAutoMemory(env: Record<string, string | undefined>, isOn: boolean): Record<string, string | undefined> {
  const { CLAUDE_CODE_DISABLE_AUTO_MEMORY: _ignored, ...rest } = env;
  return isOn ? rest : { ...rest, CLAUDE_CODE_DISABLE_AUTO_MEMORY: "1" };
}
