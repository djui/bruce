// D1 (SQLite) state for the Cloudflare Worker. D1 is strongly consistent (single primary), so the
// version-checked UPDATE / INSERT ... ON CONFLICT DO NOTHING is a real compare-and-set even when two
// cron invocations overlap. (KV would not do: its reads can be up to 60 s stale.)
import type { Entry, Store, Versioned } from "../core/store.ts";

// The subset of the D1 binding API used here (avoids a dependency on @cloudflare/workers-types).
export interface D1Result {
  meta: { changes?: number };
}
export interface D1PreparedStatement {
  bind(...values: unknown[]): D1PreparedStatement;
  first<T = Record<string, unknown>>(): Promise<T | null>;
  run(): Promise<D1Result>;
}
export interface D1Database {
  prepare(sql: string): D1PreparedStatement;
}

export const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS entries (class_id INTEGER PRIMARY KEY, version INTEGER NOT NULL, start TEXT NOT NULL, data TEXT NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)`,
];

export class D1Store implements Store {
  private readonly db: D1Database;
  private ready: Promise<void> | undefined;
  constructor(db: D1Database) {
    this.db = db;
  }

  /** Creates the tables on first use, so no separate migration step is needed. */
  private init(): Promise<void> {
    this.ready ??= (async () => {
      for (const sql of SCHEMA) await this.db.prepare(sql).run();
    })();
    return this.ready;
  }

  async get(classId: number): Promise<Versioned | undefined> {
    await this.init();
    const row = await this.db.prepare(`SELECT version, data FROM entries WHERE class_id = ?`).bind(classId).first<{ version: number; data: string }>();
    return row ? { version: row.version, entry: JSON.parse(row.data) as Entry } : undefined;
  }

  async cas(classId: number, expected: number | null, entry: Entry): Promise<boolean> {
    await this.init();
    const data = JSON.stringify(entry);
    const r =
      expected === null
        ? await this.db
            .prepare(`INSERT INTO entries (class_id, version, start, data) VALUES (?, 1, ?, ?) ON CONFLICT(class_id) DO NOTHING`)
            .bind(classId, entry.start, data)
            .run()
        : await this.db
            .prepare(`UPDATE entries SET version = version + 1, start = ?, data = ? WHERE class_id = ? AND version = ?`)
            .bind(entry.start, data, classId, expected)
            .run();
    return (r.meta.changes ?? 0) === 1;
  }

  async put(classId: number, entry: Entry): Promise<void> {
    await this.init();
    await this.db
      .prepare(
        `INSERT INTO entries (class_id, version, start, data) VALUES (?, 1, ?, ?)
         ON CONFLICT(class_id) DO UPDATE SET version = version + 1, start = excluded.start, data = excluded.data`,
      )
      .bind(classId, entry.start, JSON.stringify(entry))
      .run();
  }

  async getMeta(key: string): Promise<string | undefined> {
    await this.init();
    const row = await this.db.prepare(`SELECT value FROM meta WHERE key = ?`).bind(key).first<{ value: string }>();
    return row?.value;
  }

  async setMeta(key: string, value: string | undefined): Promise<void> {
    await this.init();
    if (value === undefined) await this.db.prepare(`DELETE FROM meta WHERE key = ?`).bind(key).run();
    else
      await this.db
        .prepare(`INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value`)
        .bind(key, value)
        .run();
  }

  async prune(beforeIso: string): Promise<number> {
    await this.init();
    const r = await this.db.prepare(`DELETE FROM entries WHERE start < ?`).bind(beforeIso).run();
    return r.meta.changes ?? 0;
  }
}
