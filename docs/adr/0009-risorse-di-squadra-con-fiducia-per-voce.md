# Le Risorse di squadra stanno in `.bubo/` con fiducia per voce legata al contenuto

Automazioni e Regole di permesso di Bubo condivise nel repo sono istruzioni di un'altra persona che girano col proprio account. Claude Code, Codex e VS Code fidano una cartella intera, una volta: una regola `allow` aggiunta dopo vale senza chiedere. direnv, gli hook di Codex e le voci MCP di Cursor legano invece la fiducia al contenuto.

Abbiamo scelto:

- **Cartella `.bubo/` nel repo**, un file per Automazione più `regole.json`, non una chiave in `.claude/settings.json`: quel file e il suo schema sono di Anthropic, e una chiave sconosciuta è ignorata senza avvisi.
- **Fiducia per voce**: ogni Automazione e ogni `allow` vale solo dopo che chi la usa l'ha accettata, legata allo sha256 del contenuto; se cambia, si riaccetta. `deny` e `ask` valgono subito, perché restringono soltanto.
- **Automazioni in pausa** all'arrivo, con l'account di chi le attiva.

Limiti accettati: una riaccettazione a ogni modifica, anche minima; le Risorse di squadra non sostituiscono la fiducia del repo di Claude Code per hook, `env` e `.mcp.json`, che si decide nella 05. Decisione presa in [Consegna, risorse di squadra e dal vivo: cosa entra in v2](https://github.com/mgiuditta/bubo/issues/267).
