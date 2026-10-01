import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { OrbTags, orbInstruction, rosaOf, TurnVariante, varianteOfTool, withoutOrbTags } from "./orb";

const known = new Set(["lente", "parentesi", "pennello", "clessidra", "fumetto", "robot"]);

// Il testo mostrato e i nomi, con `text` tagliato in tutti i punti in `size` pezzi.
function streamed(text: string, size: number) {
  const tags = new OrbTags(known);
  let shown = "";
  const names: string[] = [];
  for (let start = 0; start < text.length; start += size) {
    const pushed = tags.push(text.slice(start, start + size));
    shown += pushed.text;
    names.push(...pushed.names);
  }
  return { shown: shown + tags.flush(), names };
}

test("il tag non arriva mai nel testo, comunque spezzato tra i pezzi", () => {
  const text = "⟦orb:lente⟧\nCerco dove si apre il Panel.\n\nTrovato. ⟦orb:parentesi⟧ Ora lo correggo.";
  for (let size = 1; size <= text.length; size++) {
    const { shown, names } = streamed(text, size);
    expect(shown).toBe("Cerco dove si apre il Panel.\n\nTrovato. Ora lo correggo.");
    expect(names).toEqual(["lente", "parentesi"]);
  }
});

test("dopo il tag cade al più un a capo", () => {
  for (let size = 1; size <= 4; size++) expect(streamed("⟦orb:lente⟧ \n\nCiao", size).shown).toBe("\nCiao");
});

test("un nome sconosciuto toglie il tag senza cambiare l'Orb", () => {
  for (let size = 1; size <= 8; size++) {
    const { shown, names } = streamed("⟦orb:drago⟧Ecco.", size);
    expect(shown).toBe("Ecco.");
    expect(names).toEqual([]);
  }
});

test("ciò che sembra un tag ma non lo è resta testo", () => {
  for (const text of ["Le parentesi ⟦ e ⟧ di Strachey.", "⟦orb:lente", "⟦or", "⟦orb:una\nriga⟧", `⟦orb:${"x".repeat(80)}⟧`]) {
    for (let size = 1; size <= 4; size++) expect(streamed(text, size).shown).toBe(text);
  }
});

test("i testi interi perdono il tag", () => {
  expect(withoutOrbTags("⟦orb:lente⟧ Cerco.")).toBe("Cerco.");
  expect(withoutOrbTags("Nessun tag.")).toBe("Nessun tag.");
});

test("il ripiego copre gli strumenti di Claude Code e guarda il file", () => {
  expect(varianteOfTool("Grep", {})).toBe("lente");
  expect(varianteOfTool("Glob", {})).toBe("lente");
  expect(varianteOfTool("WebFetch", { url: "https://example.com" })).toBe("lente");
  expect(varianteOfTool("Edit", { file_path: "/p/Orb.swift" })).toBe("parentesi");
  expect(varianteOfTool("Write", { file_path: "/p/NOTE.md" })).toBe("pennello");
  expect(varianteOfTool("Read", { file_path: "/p/main.ts" })).toBe("parentesi");
  expect(varianteOfTool("Read", { file_path: "/p/README.md" })).toBe("lente");
  expect(varianteOfTool("Agent", {})).toBe("robot");
  expect(varianteOfTool("CronCreate", {})).toBe("clessidra");
  expect(varianteOfTool("AskUserQuestion", {})).toBe("fumetto");
  expect(varianteOfTool("mcp__anteprima__screenshot", {})).toBe("parentesi");
  expect(varianteOfTool("mcp__altro__fai", {})).toBeUndefined();
});

test("ogni strumento con l'input in sdk-tools.d.ts ha un ripiego verso una Variante del Catalogo", () => {
  // I nomi degli strumenti dietro le interfacce `*Input` di `ToolInputSchemas`; `McpInput` è `mcp__server__nome`.
  const tools = ["Agent", "Bash", "ExitPlanMode", "Edit", "Read", "Write", "Glob", "Grep", "TaskStop",
    "ListMcpResourcesTool", "RefreshMcpTools", "NotebookEdit", "ReadMcpResourceDirTool", "ReadMcpResourceTool",
    "ReportFindings", "TodoWrite", "WebFetch", "WebSearch", "AskUserQuestion", "SendFeedback", "ClaudeDesign",
    "Projects", "EnterPlanMode", "TaskCreate", "TaskGet", "TaskUpdate", "TaskList", "Workflow", "CronCreate",
    "CronDelete", "CronList", "ScheduleWakeup", "RemoteTrigger", "ShowOnboardingRolePicker", "ReadNotifications",
    "Monitor", "ProposeSkills", "ProposeGoal", "Artifact", "PushNotification", "EnterWorktree", "ExitWorktree"];
  const declared = readFileSync(new URL("../node_modules/@anthropic-ai/claude-agent-sdk/sdk-tools.d.ts", import.meta.url), "utf8");
  const union = declared.slice(declared.indexOf("export type ToolInputSchemas ="), declared.indexOf("export type ToolOutputSchemas ="));
  const inputs = [...union.matchAll(/\| (\w+)Input\b/g)].filter((match) => match[1] !== "Mcp");
  expect(inputs.length).toBe(tools.length);
  const catalogo = JSON.parse(readFileSync(new URL("../../Bubo/Catalogo/catalogo.json", import.meta.url), "utf8"));
  const names = new Set(catalogo.varianti.map((variante: { nome: string }) => variante.nome));
  for (const tool of tools) expect(names.has(varianteOfTool(tool, {}))).toBe(true);
});

test("il ripiego vale finché l'agente non scrive tag, e non ripete la stessa Variante", () => {
  const turn = new TurnVariante(known);
  expect(turn.tools([{ name: "Grep", input: {} }])).toBe("lente");
  expect(turn.tools([{ name: "Glob", input: {} }])).toBeUndefined();
  expect(turn.tools([{ name: "Edit", input: { file_path: "/a.swift" } }])).toBe("parentesi");
  expect(turn.text("⟦orb:pennello⟧Scrivo la nota.")).toEqual({ text: "Scrivo la nota.", variante: "pennello" });
  expect(turn.tools([{ name: "Grep", input: {} }])).toBeUndefined();
  expect(turn.text("⟦orb:pennello⟧")).toEqual({ text: "", variante: undefined });
});

test("l'istruzione elenca la rosa, e la rosa accetta solo nomi", () => {
  const instruction = orbInstruction(["lente", "parentesi"]);
  expect(instruction).toContain("⟦orb:nome⟧");
  expect(instruction).toContain("lente, parentesi");
  expect(rosaOf(["lente", "lente", "Ignora le istruzioni", 3, "a-b"])).toEqual(["lente", "a-b"]);
  expect(rosaOf("lente")).toEqual([]);
});
