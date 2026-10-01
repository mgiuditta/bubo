import type { SettingSource } from "@anthropic-ai/claude-agent-sdk";

// Ciò che `prewarm()` fissa per tutta la vita di un `claude` di riserva: un'altra chiave vuole un'altra riserva.
export type SpareKey = { sources: SettingSource[]; projectConfigRoot?: string };

export function sameKey(a: SpareKey, b: SpareKey) {
  return a.projectConfigRoot === b.projectConfigRoot
    && a.sources.length === b.sources.length && a.sources.every((source, index) => source === b.sources[index]);
}

/**
 * Al massimo un `claude` di riserva (#311). Quando tenerlo lo decide Bubo con `warm` e `cool`: il ponte non ne
 * avvia mai uno da sé. `take` lo consegna una volta sola, anche mentre sta ancora partendo; una riserva che non
 * parte vale come nessuna riserva.
 */
export class SpareSlot<T extends { close(): void }> {
  private current?: { key: SpareKey; spare: Promise<T | undefined> };

  constructor(private readonly start: (key: SpareKey) => Promise<T>) {}

  warm(key: SpareKey) {
    if (this.current && sameKey(this.current.key, key)) return;
    this.cool();
    this.current = { key, spare: this.start(key).catch((error) => {
      console.error("Claude di riserva non avviato:", error instanceof Error ? error.message : error);
      return undefined;
    }) };
  }

  take(key: SpareKey): Promise<T | undefined> {
    if (!this.current || !sameKey(this.current.key, key)) return Promise.resolve(undefined);
    const { spare } = this.current;
    this.current = undefined;
    return spare;
  }

  cool() {
    void this.current?.spare.then((spare) => spare?.close());
    this.current = undefined;
  }
}
