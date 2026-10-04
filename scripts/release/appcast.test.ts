import { describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { changelogSection, checkFeed, placeholder, previousArchives, rewriteURLs, writeNotes, yank } from "./appcast";

const prefix = "https://github.com/mgiuditta/bubo-releases/releases/download";

const changelogIt = `# Novità di Bubo

## 1.2.0 — 2026-10-01

### Novità
- Uno
- Due

### Correzioni
- Tre

### Sicurezza

## 1.1.0 — 2026-09-01

### Novità
- Vecchio
`;

const changelogEn = `# Bubo release notes

## 1.2.0 — 2026-10-01

### What's New
- One
- Two

### Fixes
- Three
`;

function item(name: string, options: { channel?: string; deltas?: boolean; url?: string } = {}) {
  const url = options.url ?? `${prefix}/${placeholder}/Bubo-${name}.dmg`;
  return `        <item>
            <title>${name}</title>
            ${options.channel ? `<sparkle:channel>${options.channel}</sparkle:channel>` : ""}
            <enclosure url="${url}" length="10" type="application/octet-stream" sparkle:edSignature="sig"/>
            ${options.deltas ? `<sparkle:deltas><enclosure url="${prefix}/${placeholder}/Bubo3-2.delta" sparkle:deltaFrom="2" length="5" sparkle:edSignature="d"/></sparkle:deltas>` : ""}
        </item>
`;
}

const feed = (...items: string[]) => `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Bubo</title>
${items.join("")}    </channel>
</rss>
<!-- sparkle-signatures:
edSignature: vecchia
length: 1
-->
`;

describe("changelogSection", () => {
  test("prende solo la sezione della versione e conta i punti", () => {
    const section = changelogSection(changelogIt, "1.2.0", "it");
    expect(section.news).toBe(2);
    expect(section.security).toBe(0);
    expect(section.body).toContain("- Tre");
    expect(section.body).not.toContain("Vecchio");
  });

  test("più di 3 punti in Novità ferma la release", () => {
    const four = changelogIt.replace("- Due", "- Due\n- Tre\n- Quattro");
    expect(() => changelogSection(four, "1.2.0", "it")).toThrow("4 punti in Novità");
  });

  test("versione assente ferma la release", () => {
    expect(() => changelogSection(changelogIt, "1.3.0", "it")).toThrow("manca");
  });

  test("una beta ha la sua sezione e i punti non si confondono con la stabile", () => {
    const beta = "## 1.2.0-beta.1 — 2026-09-20\n\n### Novità\n- Prova\n\n" + changelogIt;
    expect(changelogSection(beta, "1.2.0-beta.1", "it").news).toBe(1);
    expect(() => changelogSection(changelogIt, "1.2.0-beta.1", "it")).toThrow("manca");
  });

  test("sezione sconosciuta o titolo nell'altra lingua", () => {
    expect(() => changelogSection(changelogEn, "1.2.0", "it")).toThrow("sezione sconosciuta");
  });

  test("Sicurezza non vuota rende l'aggiornamento critico", () => {
    const secure = changelogIt.replace("### Sicurezza\n", "### Sicurezza\n- Falla chiusa\n");
    expect(changelogSection(secure, "1.2.0", "it").security).toBe(1);
  });
});

describe("writeNotes", () => {
  test("una lingua senza la versione ferma la release e le nomina tutte", () => {
    const root = mkdtempSync(join(tmpdir(), "notes-"));
    writeFileSync(join(root, "CHANGELOG.md"), changelogIt);
    writeFileSync(join(root, "CHANGELOG.en.md"), changelogEn.replace("1.2.0", "1.1.9"));
    expect(() => writeNotes(root, "1.2.0", root, "Bubo-1.2.0", ["it", "en"])).toThrow("CHANGELOG.en.md: manca");
  });

  test("italiano incorporato, altre lingue con il suffisso di Sparkle", () => {
    const root = mkdtempSync(join(tmpdir(), "notes-"));
    writeFileSync(join(root, "CHANGELOG.md"), changelogIt);
    writeFileSync(join(root, "CHANGELOG.en.md"), changelogEn);
    expect(writeNotes(root, "1.2.0", root, "Bubo-1.2.0", ["it", "en"])).toEqual({ critical: false });
    expect(readFileSync(join(root, "Bubo-1.2.0.md"), "utf8")).toContain("- Uno");
    expect(readFileSync(join(root, "Bubo-1.2.0.en.md"), "utf8")).toContain("- One");
  });
});

describe("previousArchives", () => {
  const xml = feed(
    item("1.3.0-beta.1", { channel: "beta", url: `${prefix}/v1.3.0-beta.1/Bubo-1.3.0-beta.1.dmg` }),
    item("1.2.0", { url: `${prefix}/v1.2.0/Bubo-1.2.0.dmg` }),
    item("1.1.0", { url: `${prefix}/v1.1.0/Bubo-1.1.0.dmg` }),
    item("1.0.1", { url: `${prefix}/v1.0.1/Bubo-1.0.1.dmg` }),
    item("1.0.0", { url: `${prefix}/v1.0.0/Bubo-1.0.0.dmg` }),
  );

  test("le 3 stabili più recenti, senza le beta", () => {
    expect(previousArchives(xml, "stable", 3)).toEqual([
      `${prefix}/v1.2.0/Bubo-1.2.0.dmg`,
      `${prefix}/v1.1.0/Bubo-1.1.0.dmg`,
      `${prefix}/v1.0.1/Bubo-1.0.1.dmg`,
    ]);
  });

  test("solo le beta per il Canale beta", () => {
    expect(previousArchives(xml, "beta", 3)).toEqual([`${prefix}/v1.3.0-beta.1/Bubo-1.3.0-beta.1.dmg`]);
  });
});

describe("rewriteURLs", () => {
  test("ogni item va nella release del suo DMG, delta compresi, e la vecchia firma cade", () => {
    const xml = rewriteURLs(feed(item("1.2.0", { deltas: true }), item("1.1.0-beta.2", { channel: "beta" })), prefix);
    expect(xml).toContain(`${prefix}/v1.2.0/Bubo-1.2.0.dmg`);
    expect(xml).toContain(`${prefix}/v1.2.0/Bubo3-2.delta`);
    expect(xml).toContain(`${prefix}/v1.1.0-beta.2/Bubo-1.1.0-beta.2.dmg`);
    expect(xml).not.toContain(placeholder);
    expect(xml).not.toContain("sparkle-signatures");
  });

  test("un item senza DMG di Bubo si rifiuta", () => {
    expect(() => rewriteURLs(feed(item("x", { url: `${prefix}/${placeholder}/Altro.zip` })), prefix)).toThrow("senza DMG");
  });
});

describe("yank", () => {
  const xml = feed(
    item("1.2.0", { url: `${prefix}/v1.2.0/Bubo-1.2.0.dmg` }),
    item("1.1.0", { url: `${prefix}/v1.1.0/Bubo-1.1.0.dmg` }),
  );

  test("toglie solo la voce del tag e lascia le altre identiche", () => {
    const result = yank(xml, "v1.2.0");
    expect(result).not.toContain("Bubo-1.2.0.dmg");
    expect(result).toContain(item("1.1.0", { url: `${prefix}/v1.1.0/Bubo-1.1.0.dmg` }));
    expect(result).not.toContain("sparkle-signatures");
  });

  test("tag assente: errore, niente da firmare", () => {
    expect(() => yank(xml, "v9.9.9")).toThrow("0 item");
  });
});

describe("checkFeed", () => {
  const signed = feed(item("1.2.0", { url: `${prefix}/v1.2.0/Bubo-1.2.0.dmg` }));
  const serve = (status: number, length = "10") =>
    (async () => new Response(null, { status, headers: { "content-length": length } })) as unknown as typeof fetch;

  test("URL a 200 con la lunghezza giusta: nessun problema", async () => {
    expect(await checkFeed(signed, serve(200))).toEqual([]);
  });

  test("404, lunghezza diversa e feed senza firma si segnalano", async () => {
    expect(await checkFeed(signed, serve(404))).toEqual([`${prefix}/v1.2.0/Bubo-1.2.0.dmg: 404`]);
    expect((await checkFeed(signed, serve(200, "11")))[0]).toContain("length 10, servito 11");
    expect(await checkFeed(signed.replace(/<!-- sparkle-signatures:[\s\S]*-->/, ""), serve(200))).toContain("feed senza firma");
  });

  test("enclosure senza edSignature", async () => {
    expect(await checkFeed(signed.replace(' sparkle:edSignature="sig"', ""), serve(200))).toContain(
      `${prefix}/v1.2.0/Bubo-1.2.0.dmg: senza edSignature`,
    );
  });
});
