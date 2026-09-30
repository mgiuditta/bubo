// Passi dell'appcast che non chiedono macOS (spec 27, #223), usati da appcast.sh e yank.sh.
//   bun scripts/release/appcast.ts notes <nome> <cartella> <prefisso>  note da CHANGELOG*.md; stampa "critical" se c'è Sicurezza
//   bun scripts/release/appcast.ts previous <appcast> <stable|beta> <n>  URL dei DMG delle n versioni precedenti del Canale
//   bun scripts/release/appcast.ts urls <appcast> <prefisso download>   ogni URL segnaposto → la release del suo item
//   bun scripts/release/appcast.ts yank <appcast> <tag>                 toglie l'item del tag
//   bun scripts/release/appcast.ts check <appcast>                      firma, lunghezza e risposta 200 di ogni URL
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

export const placeholder = "__TAG__";
const maxNews = 3;
// Titoli delle sezioni per lingua: il nome interno è la chiave, il titolo è quello che legge l'utente.
const headings: Record<string, Record<"novita" | "correzioni" | "sicurezza", string>> = {
  it: { novita: "Novità", correzioni: "Correzioni", sicurezza: "Sicurezza" },
  en: { novita: "What's New", correzioni: "Fixes", sicurezza: "Security" },
};

export type Section = { body: string; news: number; security: number };

/** La sezione `## <nome> — AAAA-MM-GG` del CHANGELOG, senza il titolo; errore se manca o è fuori regola. */
export function changelogSection(changelog: string, name: string, language: string): Section {
  const titles = headings[language];
  if (!titles) throw new Error(`lingua ${language} senza titoli delle sezioni in appcast.ts`);
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const header = new RegExp(`^## ${escaped} — \\d{4}-\\d{2}-\\d{2}\\s*$`, "m");
  const match = header.exec(changelog);
  if (!match) throw new Error(`manca "## ${name} — AAAA-MM-GG"`);
  const rest = changelog.slice(match.index + match[0].length);
  const next = rest.search(/^## /m);
  const body = (next === -1 ? rest : rest.slice(0, next)).trim();

  const known = new Set(Object.values(titles));
  const counts: Record<string, number> = {};
  let current: string | undefined;
  for (const line of body.split("\n")) {
    const subheading = /^### (.+?)\s*$/.exec(line);
    if (subheading) {
      if (!known.has(subheading[1])) throw new Error(`sezione sconosciuta "### ${subheading[1]}"`);
      current = subheading[1];
      counts[current] = 0;
    } else if (/^[-*] \S/.test(line)) {
      if (!current) throw new Error("punto fuori da una sezione ###");
      counts[current]++;
    }
  }
  const news = counts[titles.novita] ?? 0;
  if (news > maxNews) throw new Error(`${news} punti in ${titles.novita}, al massimo ${maxNews}`);
  if (!body) throw new Error("sezione vuota");
  return { body: body + "\n", news, security: counts[titles.sicurezza] ?? 0 };
}

/** Scrive `<prefisso>.md` (lingua di sviluppo, incorporata) e `<prefisso>.<lingua>.md` per le altre. */
export function writeNotes(root: string, name: string, directory: string, prefix: string, languages: string[]) {
  const [source] = languages;
  const errors: string[] = [];
  let critical = false;
  for (const language of languages) {
    const file = language === source ? "CHANGELOG.md" : `CHANGELOG.${language}.md`;
    const path = join(root, file);
    try {
      if (!existsSync(path)) throw new Error("file mancante");
      const section = changelogSection(readFileSync(path, "utf8"), name, language);
      if (language === source) critical = section.security > 0;
      const out = language === source ? `${prefix}.md` : `${prefix}.${language}.md`;
      writeFileSync(join(directory, out), section.body);
    } catch (error) {
      errors.push(`${file}: ${(error as Error).message}`);
    }
  }
  if (errors.length) throw new Error(errors.join("\n"));
  return { critical };
}

/** Lingue del String Catalog: prima quella di sviluppo. */
export function catalogLanguages(root: string): string[] {
  const catalog = JSON.parse(readFileSync(join(root, "Bubo/Resources/Localizable.xcstrings"), "utf8"));
  const found = new Set<string>();
  for (const entry of Object.values<{ localizations?: Record<string, unknown> }>(catalog.strings)) {
    for (const language of Object.keys(entry.localizations ?? {})) found.add(language);
  }
  found.delete(catalog.sourceLanguage);
  return [catalog.sourceLanguage, ...[...found].sort()];
}

const itemPattern = /<item>[\s\S]*?<\/item>/g;
const enclosureURL = (item: string) => /<enclosure\b[^>]*\burl="([^"]+)"/.exec(item)?.[1];
const dmgName = (url: string) => /\/Bubo-([^/"]+)\.dmg$/.exec(url)?.[1];
export const stripFeedSignature = (xml: string) => xml.replace(/\s*<!-- sparkle-signatures:[\s\S]*?-->\s*/g, "\n");

/** I DMG delle n versioni più recenti del Canale già nel feed, per i delta. */
export function previousArchives(xml: string, channel: "stable" | "beta", count: number): string[] {
  return (xml.match(itemPattern) ?? [])
    .filter((item) => {
      const itemChannel = /<sparkle:channel>\s*([^<\s]+)\s*<\/sparkle:channel>/.exec(item)?.[1];
      return channel === "stable" ? itemChannel === undefined : itemChannel === "beta";
    })
    .map(enclosureURL)
    .filter((url): url is string => url !== undefined && dmgName(url) !== undefined)
    .slice(0, count);
}

/** generate_appcast conosce un solo prefisso: ogni URL col segnaposto va nella release del suo item. */
export function rewriteURLs(xml: string, downloadPrefix: string): string {
  const rewritten = xml.replace(itemPattern, (item) => {
    const url = enclosureURL(item);
    const name = url && dmgName(url);
    if (!name) throw new Error(`item senza DMG Bubo-<nome>.dmg: ${url ?? "nessun enclosure"}`);
    return item.replaceAll(`${downloadPrefix}/${placeholder}/`, `${downloadPrefix}/v${name}/`);
  });
  if (rewritten.includes(placeholder)) throw new Error(`segnaposto ${placeholder} rimasto fuori da un item`);
  return stripFeedSignature(rewritten);
}

/** Toglie l'item del tag; le altre voci restano identiche. */
export function yank(xml: string, tag: string): string {
  let removed = 0;
  const result = xml.replace(/[ \t]*<item>[\s\S]*?<\/item>[ \t]*\n?/g, (item) => {
    const url = enclosureURL(item);
    if (url && url.includes(`/download/${tag}/`)) {
      removed++;
      return "";
    }
    return item;
  });
  if (removed !== 1) throw new Error(`${removed} item per ${tag}, atteso 1`);
  return stripFeedSignature(result);
}

export type Problem = string;

/** Ogni enclosure ha edSignature e length; ogni URL risponde 200 con la lunghezza dichiarata. */
export async function checkFeed(xml: string, fetcher: typeof fetch = fetch): Promise<Problem[]> {
  const problems: Problem[] = [];
  if (!xml.includes("<!-- sparkle-signatures:")) problems.push("feed senza firma");
  const enclosures = [...xml.matchAll(/<enclosure\b[^>]*>/g)].map((m) => m[0]);
  if (!enclosures.length) problems.push("nessun enclosure");
  for (const tag of enclosures) {
    const url = /\burl="([^"]+)"/.exec(tag)?.[1];
    const length = /\blength="(\d+)"/.exec(tag)?.[1];
    if (!url) { problems.push(`enclosure senza url: ${tag}`); continue; }
    if (!/\bsparkle:edSignature="[^"]+"/.test(tag)) problems.push(`${url}: senza edSignature`);
    if (!length) problems.push(`${url}: senza length`);
    const response = await fetcher(url, { method: "HEAD", redirect: "follow" });
    if (response.status !== 200) problems.push(`${url}: ${response.status}`);
    else if (length && response.headers.get("content-length") !== length)
      problems.push(`${url}: length ${length}, servito ${response.headers.get("content-length")}`);
  }
  for (const m of xml.matchAll(/<sparkle:(?:releaseNotesLink|fullReleaseNotesLink)[^>]*>\s*([^<\s]+)\s*</g)) {
    const response = await fetcher(m[1], { method: "HEAD", redirect: "follow" });
    if (response.status !== 200) problems.push(`${m[1]}: ${response.status}`);
  }
  return problems;
}

if (import.meta.main) {
  const [command, ...args] = process.argv.slice(2);
  const root = join(import.meta.dir, "../..");
  try {
    switch (command) {
      case "notes": {
        const [name, directory, prefix] = args;
        const { critical } = writeNotes(root, name, directory, prefix, catalogLanguages(root));
        if (critical) console.log("critical");
        break;
      }
      case "previous": {
        const [path, channel, count] = args;
        const urls = existsSync(path) ? previousArchives(readFileSync(path, "utf8"), channel as "stable" | "beta", Number(count)) : [];
        if (urls.length) console.log(urls.join("\n"));
        break;
      }
      case "urls":
        writeFileSync(args[0], rewriteURLs(readFileSync(args[0], "utf8"), args[1]));
        break;
      case "yank":
        writeFileSync(args[0], yank(readFileSync(args[0], "utf8"), args[1]));
        break;
      case "check": {
        const problems = await checkFeed(readFileSync(args[0], "utf8"));
        if (problems.length) throw new Error(problems.join("\n"));
        console.log("appcast: ok");
        break;
      }
      default:
        throw new Error("comandi: notes, previous, urls, yank, check");
    }
  } catch (error) {
    console.error(`appcast: ${(error as Error).message}`);
    process.exit(1);
  }
}
