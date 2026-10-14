// JSON-file state for the Node targets (VPS / Fly.io service and the macOS launchd job).
// The file is re-read on every operation and replaced atomically (write temp + rename). All file
// I/O is synchronous, so operations of one process never interleave.
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import type { Entry, Store, Versioned } from "../core/store.ts";

interface FileShape {
  entries: Record<string, Versioned>;
  meta: Record<string, string>;
}

export class FileStore implements Store {
  private readonly path: string;
  constructor(path: string) {
    this.path = path;
    mkdirSync(dirname(path), { recursive: true });
  }

  private read(): FileShape {
    try {
      const j = JSON.parse(readFileSync(this.path, "utf8")) as Partial<FileShape>;
      return { entries: j.entries ?? {}, meta: j.meta ?? {} };
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === "ENOENT") return { entries: {}, meta: {} };
      throw new Error(`cannot read state file ${this.path}: ${(e as Error).message}`);
    }
  }

  private write(s: FileShape) {
    const tmp = `${this.path}.${process.pid}.tmp`;
    writeFileSync(tmp, JSON.stringify(s, null, 2) + "\n", { mode: 0o600 });
    renameSync(tmp, this.path);
  }

  async get(classId: number) {
    return this.read().entries[classId];
  }

  async cas(classId: number, expected: number | null, entry: Entry) {
    const s = this.read();
    const cur = s.entries[classId];
    if ((cur?.version ?? null) !== expected) return false;
    s.entries[classId] = { entry, version: (cur?.version ?? 0) + 1 };
    this.write(s);
    return true;
  }

  async put(classId: number, entry: Entry) {
    const s = this.read();
    s.entries[classId] = { entry, version: (s.entries[classId]?.version ?? 0) + 1 };
    this.write(s);
  }

  async getMeta(key: string) {
    return this.read().meta[key];
  }

  async setMeta(key: string, value: string | undefined) {
    const s = this.read();
    if (value === undefined) delete s.meta[key];
    else s.meta[key] = value;
    this.write(s);
  }

  async prune(beforeIso: string) {
    const s = this.read();
    let n = 0;
    for (const [id, v] of Object.entries(s.entries)) {
      if (v.entry.start < beforeIso) {
        delete s.entries[id];
        n++;
      }
    }
    if (n) this.write(s);
    return n;
  }
}
