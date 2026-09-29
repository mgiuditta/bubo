# Bubo

App agentica nativa macOS (Swift 6, SwiftUI, AppKit, Metal) con orb 3D, voce, router multi-modello e Claude Agent SDK. Riferimento visivo approvato: `reference/bubo.html`.

## Agent skills

### Issue tracker

GitHub Issues su `mgiuditta/bubo` via `gh`; mappe wayfinder come issue `wayfinder:map` con sub-issue. See `docs/agents/issue-tracker.md`.

### Triage labels

Label predefinite (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` alla radice. See `docs/agents/domain.md`.

## Skill Swift obbligatorie

Quando scrivi, modifichi o rivedi codice Swift di Bubo, **devi** caricare con il tool Skill le skill pertinenti di `.claude/skills/` **prima** di scrivere il codice, e rispettarle. Non è facoltativo. Origine e versione di ciascuna in `.claude/skills/SOURCES.txt`.

| Quando | Skill |
|---|---|
| Qualunque codice Swift | `swift-api-design-guidelines-skill`, `swift-concurrency-pro` |
| Viste SwiftUI | `swiftui-pro`, `swiftui-ui-patterns`, `swiftui-liquid-glass` (vetro, macOS 26) |
| Refactor di viste | `swiftui-view-refactor` |
| Test | `swift-testing-pro` |
| Persistenza con SwiftData | `swiftdata-pro` |
| Accessibilità | `swiftui-accessibility-auditor`, `appkit-accessibility-auditor` (Panel, NSPanel, AppKit) |
| App Intents, Comandi rapidi, Spotlight | `app-intents` |
| Portachiavi, API key, crittografia, entitlement | `swift-security-expert` |
| Log, segnali, metriche | `observability` |
| Formattazione di numeri, date, costi, durate | `swift-format-style` |
| Testi dell'interfaccia (String Catalog) | `writing-for-interfaces` |
| Prestazioni (fps, RAM, avvio) | `swiftui-performance-audit` |

Le skill sono scritte per iOS e macOS: dove contraddicono `CONTEXT.md`, un ADR o le decisioni delle mappe wayfinder, prevalgono queste ultime.
