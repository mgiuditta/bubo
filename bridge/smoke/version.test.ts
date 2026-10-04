import { describe, expect, test } from "bun:test";
import { checkMinimum, compareVersions, minimumClaudeVersion, parseVersion } from "./version";

describe("versione di claude", () => {
  test.each([
    ["2.1.286 (Claude Code)", [2, 1, 286]],
    ["2.1.285", [2, 1, 285]],
    ["claude 10.0.1-beta.2", [10, 0, 1]],
  ])("%s", (text, expected) => {
    expect(parseVersion(text)).toEqual(expected as [number, number, number]);
  });

  test("formati strani", () => {
    expect(parseVersion("")).toBeUndefined();
    expect(parseVersion("2.1")).toBeUndefined();
  });

  test("confronto numerico, non lessicale", () => {
    expect(compareVersions([2, 1, 100], [2, 1, 99])).toBeGreaterThan(0);
    expect(compareVersions([2, 10, 0], [2, 9, 999])).toBeGreaterThan(0);
    expect(compareVersions([2, 1, 285], [2, 1, 285])).toBe(0);
  });

  test("sotto, uguale e sopra la minima", () => {
    expect(() => checkMinimum("2.1.284 (Claude Code)", "2.1.285")).toThrow("sotto la minima");
    expect(() => checkMinimum("2.1.285 (Claude Code)", "2.1.285")).not.toThrow();
    expect(() => checkMinimum("2.2.0 (Claude Code)", "2.1.285")).not.toThrow();
    expect(() => checkMinimum("boh", "2.1.285")).toThrow("illeggibile");
  });

  test("compat.json ha una minima valida", () => {
    expect(parseVersion(minimumClaudeVersion())).toBeDefined();
  });
});
