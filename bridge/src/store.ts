// La copia a specchio delle conversazioni (ADR 0006): il `sessionStore` dell'SDK sul database SQLite di Bubo.
// Non cancella mai da sé: solo quando Bubo elimina una Sessione o spegne la copia della Cronologia CLI.
import { Database } from "bun:sqlite";
import { importSessionToStore, type SessionKey, type SessionStore, type SessionStoreEntry } from "@anthropic-ai/claude-agent-sdk";

export class ConversationStore implements SessionStore {
  private readonly db: Database;

  constructor(path: string) {
    this.db = new Database(path, { create: true, strict: true });
    this.db.run(`CREATE TABLE IF NOT EXISTS entries (
      seq INTEGER PRIMARY KEY AUTOINCREMENT, project TEXT NOT NULL, session TEXT NOT NULL,
      subpath TEXT NOT NULL DEFAULT '', uuid TEXT, entry TEXT NOT NULL, mtime INTEGER NOT NULL)`);
    // `uuid` è la chiave di idempotenza: un nuovo tentativo o un import ripetuto non duplica le righe.
    this.db.run("CREATE UNIQUE INDEX IF NOT EXISTS entries_uuid ON entries(project, session, subpath, uuid) WHERE uuid IS NOT NULL");
    this.db.run("CREATE INDEX IF NOT EXISTS entries_session ON entries(session, subpath, seq)");
    // Le conversazioni della Cronologia CLI copiate, con il `lastModified` della copia.
    this.db.run("CREATE TABLE IF NOT EXISTS imported (session TEXT PRIMARY KEY, mtime INTEGER NOT NULL)");
  }

  async append(key: SessionKey, entries: SessionStoreEntry[]) {
    this.db.transaction(() => this.insert(key, entries))();
  }

  private insert(key: SessionKey, entries: SessionStoreEntry[]) {
    const insert = this.db.prepare(
      "INSERT OR IGNORE INTO entries (project, session, subpath, uuid, entry, mtime) VALUES (?, ?, ?, ?, ?, ?)");
    const now = Date.now();
    for (const entry of entries) {
      insert.run(key.projectKey, key.sessionId, key.subpath ?? "", entry.uuid ?? null, JSON.stringify(entry), now);
    }
  }

  // Rifà la copia di `session` dal transcript locale, subagent compresi, e la sostituisce in un colpo solo:
  // dopo un `mirror_error`, o quando una conversazione della Cronologia CLI è andata avanti.
  // Se il transcript non si legge, la copia di prima resta com'è.
  async replace(session: string, read: typeof importSessionToStore = importSessionToStore) {
    const batches: [SessionKey, SessionStoreEntry[]][] = [];
    await read(session, { append: async (key, entries) => { batches.push([key, entries]); }, load: async () => null });
    if (!batches.length) return;
    this.db.transaction(() => {
      this.db.run("DELETE FROM entries WHERE session = ?", [session]);
      for (const [key, entries] of batches) this.insert(key, entries);
    })();
  }

  async load(key: SessionKey): Promise<SessionStoreEntry[] | null> {
    const rows = this.db.query<{ entry: string }, [string, string, string]>(
      "SELECT entry FROM entries WHERE project = ? AND session = ? AND subpath = ? ORDER BY seq")
      .all(key.projectKey, key.sessionId, key.subpath ?? "");
    return rows.length ? rows.map((row) => JSON.parse(row.entry)) : null;
  }

  async listSessions(projectKey: string) {
    return this.db.query<{ sessionId: string; mtime: number }, [string]>(
      "SELECT session AS sessionId, MAX(mtime) AS mtime FROM entries WHERE project = ? AND subpath = '' GROUP BY session")
      .all(projectKey);
  }

  // Senza `subpath` se ne va la conversazione intera, subagent compresi.
  async delete(key: SessionKey) {
    if (key.subpath === undefined) {
      this.db.run("DELETE FROM entries WHERE project = ? AND session = ?", [key.projectKey, key.sessionId]);
    } else {
      this.db.run("DELETE FROM entries WHERE project = ? AND session = ? AND subpath = ?",
                  [key.projectKey, key.sessionId, key.subpath]);
    }
  }

  async listSubkeys(key: { projectKey: string; sessionId: string }) {
    return this.db.query<{ subpath: string }, [string, string]>(
      "SELECT DISTINCT subpath FROM entries WHERE project = ? AND session = ? AND subpath != ''")
      .all(key.projectKey, key.sessionId).map((row) => row.subpath);
  }

  // Le copie di queste conversazioni, in qualunque Progetto: una Sessione eliminata in Bubo.
  forget(sessions: string[]) {
    const remove = this.db.prepare("DELETE FROM entries WHERE session = ?");
    const unmark = this.db.prepare("DELETE FROM imported WHERE session = ?");
    this.db.transaction(() => {
      for (const session of sessions) {
        remove.run(session);
        unmark.run(session);
      }
    })();
  }

  // Quando è stata copiata la conversazione della Cronologia CLI `session`, nel suo `lastModified`.
  importedAt(session: string): number | undefined {
    return this.db.query<{ mtime: number }, [string]>("SELECT mtime FROM imported WHERE session = ?").get(session)?.mtime;
  }

  markImported(session: string, mtime: number) {
    this.db.run("INSERT OR REPLACE INTO imported (session, mtime) VALUES (?, ?)", [session, mtime]);
  }

  // L'interruttore spento: via tutte le copie della Cronologia CLI, e lo spazio torna libero.
  forgetImported() {
    this.db.transaction(() => {
      this.db.run("DELETE FROM entries WHERE session IN (SELECT session FROM imported)");
      this.db.run("DELETE FROM imported");
    })();
    this.db.run("VACUUM");
  }
}
