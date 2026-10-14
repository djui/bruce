// A D1 stand-in for tests: Node's built-in SQLite (node:sqlite) with the D1 statement API the worker uses
// (prepare/bind/run/first/all, batch), the `users` table the worker creates and the real migrations applied.
import { DatabaseSync } from "node:sqlite";
import { readFileSync, readdirSync } from "node:fs";

const migrations = new URL("../migrations/", import.meta.url);

export function d1(users = []) {
  const sql = new DatabaseSync(":memory:");
  sql.exec(`CREATE TABLE users (user_id INTEGER PRIMARY KEY, access_token TEXT NOT NULL, rules TEXT NOT NULL DEFAULT '[]',
            devices TEXT NOT NULL DEFAULT '[]', state TEXT NOT NULL DEFAULT '{}', updated_at TEXT)`);
  for (const f of readdirSync(migrations).filter((f) => f.endsWith(".sql")).sort()) sql.exec(readFileSync(new URL(f, migrations), "utf8"));
  const ins = sql.prepare("INSERT INTO users (user_id, access_token, rules, devices, state) VALUES (?, ?, ?, ?, ?)");
  for (const u of users) ins.run(u.user_id, u.access_token, u.rules ?? "[]", u.devices ?? "[]", u.state ?? "{}");
  const plain = (r) => (r ? { ...r } : null);
  const DB = {
    sql,
    // Like D1, bind() returns a new statement, so one prepared statement can be bound many times (batch inserts).
    prepare(q, args = []) {
      return {
        bind: (...a) => DB.prepare(q, a.map((x) => (x === undefined ? null : typeof x === "boolean" ? +x : x))),
        exec: () => sql.prepare(q).run(...args),
        async run() { sql.prepare(q).run(...args); return { success: true }; },
        async first() { return plain(sql.prepare(q).get(...args)); },
        async all() { return { results: sql.prepare(q).all(...args).map(plain) }; },
      };
    },
    async batch(stmts) {
      sql.exec("BEGIN");
      try { for (const s of stmts) s.exec(); sql.exec("COMMIT"); } catch (e) { sql.exec("ROLLBACK"); throw e; }
      return stmts.map(() => ({ success: true }));
    },
    /** Test helpers: rows of a table, the `users` row of a user. */
    rows(table, where = "1") { return sql.prepare(`SELECT * FROM ${table} WHERE ${where}`).all().map(plain); },
    t: {
      get: (id) => plain(sql.prepare("SELECT * FROM users WHERE user_id = ?").get(id)) ?? undefined,
      get size() { return sql.prepare("SELECT COUNT(*) AS n FROM users").get().n; },
    },
  };
  return DB;
}
