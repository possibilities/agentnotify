import { Database } from "bun:sqlite";
import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { MAX_LIST_LIMIT, MessageStore, parseSince } from "../src/store.ts";

const temporaryDirectories: string[] = [];

function temporaryDatabase(): string {
  const directory = mkdtempSync(join(tmpdir(), "agentnotify-store-"));
  temporaryDirectories.push(directory);
  return join(directory, "log.db");
}

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

describe("MessageStore", () => {
  test("creates the exact schema and database pragmas", () => {
    const store = new MessageStore(temporaryDatabase());
    const columns = store.database.query("PRAGMA table_info(messages)").all() as Array<{
      name: string;
    }>;
    expect(columns.map((column) => column.name)).toEqual([
      "id",
      "timestamp",
      "title",
      "message",
      "sound",
      "group_id",
      "open_url",
      "execute_cmd",
      "method",
      "dismissed_at",
    ]);
    expect(store.database.query("PRAGMA user_version").get()).toEqual({ user_version: 1 });
    expect(store.database.query("PRAGMA journal_mode").get()).toEqual({ journal_mode: "wal" });
    expect(store.database.query("PRAGMA synchronous").get()).toEqual({ synchronous: 1 });
    expect(statSync(store.path).mode & 0o777).toBe(0o600);
    store.close();
  });

  test("migrates a compatible database without losing existing data", () => {
    const path = temporaryDatabase();
    const database = new Database(path, { create: true });
    database.exec(`CREATE TABLE messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT NOT NULL, title TEXT NOT NULL,
      message TEXT NOT NULL, sound TEXT, group_id TEXT, open_url TEXT, execute_cmd TEXT,
      method TEXT NOT NULL
    )`);
    database
      .query("INSERT INTO messages (timestamp, title, message, method) VALUES (?, ?, ?, ?)")
      .run("2025-01-01T00:00:00.000Z", "kept", "body", "test");
    database.close();

    const store = new MessageStore(path);
    const row = store.database.query("SELECT * FROM messages WHERE id = 1").get() as Record<
      string,
      unknown
    >;
    expect(row.title).toBe("kept");
    expect(row.dismissed_at).toBe("2025-01-01T00:00:00.000Z");
    store.close();
  });

  test("logs, lists newest first, searches, filters since, and dismisses idempotently", () => {
    const store = new MessageStore(temporaryDatabase());
    const first = store.add({
      timestamp: "2025-01-01T00:00:00.000Z",
      title: "Alpha 100% title",
      message: "first body",
      sound: "Ping",
      groupId: "group-one",
      openUrl: "https://example.test",
      execute: "open app",
      method: "fake",
    });
    store.add({
      timestamp: "2025-01-02T00:00:00.000Z",
      title: "Beta",
      message: "contains Alpha",
      sound: null,
      groupId: null,
      openUrl: null,
      execute: null,
      method: "fake",
    });

    expect(store.list({ limit: 20 }).map((entry) => entry.title)).toEqual([
      "Beta",
      "Alpha 100% title",
    ]);
    expect(store.list({ limit: 20, search: "Alpha" })).toHaveLength(2);
    expect(store.list({ limit: 20, search: "%" })).toHaveLength(1);
    expect(store.list({ limit: 20, search: "_" })).toHaveLength(0);
    expect(
      store.list({ limit: 20, since: "12h" }, new Date("2025-01-02T06:00:00.000Z")),
    ).toHaveLength(1);
    expect(store.list({ limit: 20, since: "2025-01-02" })).toHaveLength(1);

    store.dismiss(first, "2025-02-01T00:00:00.000Z");
    store.dismiss(first, "2025-03-01T00:00:00.000Z");
    expect(
      (
        store.database.query("SELECT dismissed_at FROM messages WHERE id = ?").get(first) as {
          dismissed_at: string;
        }
      ).dismissed_at,
    ).toBe("2025-02-01T00:00:00.000Z");
    expect(store.dismiss(999, "2025-02-01T00:00:00.000Z")).toBe(false);
    store.close();
  });

  test("validates list limits and since syntax", () => {
    const store = new MessageStore(temporaryDatabase());
    expect(() => store.list({ limit: 0 })).toThrow();
    expect(() => store.list({ limit: MAX_LIST_LIMIT + 1 })).toThrow();
    expect(parseSince("1h", new Date("2025-01-01T01:00:00.000Z"))).toBe("2025-01-01T00:00:00.000Z");
    expect(() => parseSince("1H")).toThrow("Invalid --since value");
    expect(() => parseSince("yesterday")).toThrow("Invalid --since value");
    store.close();
  });
});
