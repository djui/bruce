// The Node file store and the Worker D1 store, the latter against a real SQLite (node:sqlite)
// behind a minimal D1-shaped adapter.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { after, describe, it } from "node:test";
import type { Entry, Store } from "../src/core/store.ts";
import { FileStore } from "../src/node/file-store.ts";
import { D1Store, type D1Database, type D1PreparedStatement } from "../src/worker/d1-store.ts";

function fakeD1(): D1Database {
  const db = new DatabaseSync(":memory:");
  return {
    prepare(sql: string) {
      let args: unknown[] = [];
      const stmt: D1PreparedStatement = {
        bind: (...v: unknown[]) => {
          args = v;
          return stmt;
        },
        first: async <T>() => (db.prepare(sql).get(...(args as never[])) as T | undefined) ?? null,
        run: async () => ({ meta: { changes: Number(db.prepare(sql).run(...(args as never[])).changes) } }),
      };
      return stmt;
    },
  };
}

const e = (over: Partial<Entry> = {}): Entry => ({
  classId: 1, ruleId: "r", title: "t", studioId: 2, start: "2026-10-22T16:00:00.000Z", status: "pending", updatedAt: "", attempts: 0, ...over,
});

const dir = mkdtempSync(join(tmpdir(), "autobook-test-"));
after(() => rmSync(dir, { recursive: true, force: true }));

for (const [name, make] of [
  ["FileStore", () => new FileStore(join(dir, `s-${Math.random()}`, "state.json"))],
  ["D1Store", () => new D1Store(fakeD1())],
] as [string, () => Store][]) {
  describe(name, () => {
    it("compare-and-set, put, meta and prune", async () => {
      const s = make();
      assert.equal(await s.get(1), undefined);
      assert.equal(await s.cas(1, null, e()), true);
      assert.equal(await s.cas(1, null, e()), false);
      assert.equal((await s.get(1))?.version, 1);
      assert.equal(await s.cas(1, 0, e()), false);
      assert.equal(await s.cas(1, 1, e({ status: "booked" })), true);
      await s.put(1, e({ status: "waitlisted" }));
      assert.deepEqual(await s.get(1), { version: 3, entry: e({ status: "waitlisted" }) });
      await s.setMeta("auth", "abc");
      assert.equal(await s.getMeta("auth"), "abc");
      await s.setMeta("auth", undefined);
      assert.equal(await s.getMeta("auth"), undefined);
      await s.put(2, e({ classId: 2, start: "2026-10-01T00:00:00.000Z" }));
      assert.equal(await s.prune("2026-10-10T00:00:00.000Z"), 1);
      assert.equal(await s.get(2), undefined);
      assert.ok(await s.get(1));
    });
  });
}
