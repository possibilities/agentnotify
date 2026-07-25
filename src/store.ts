import { Database } from "bun:sqlite";
import { chmodSync, existsSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { logDatabasePath } from "./paths.ts";
import type { ListOptions, MessageOutput, MessageRecord, NewMessage } from "./types.ts";

const SCHEMA_VERSION = 1;
export const MAX_LIST_LIMIT = 1000;

const CREATE_MESSAGES = `CREATE TABLE IF NOT EXISTS messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp TEXT NOT NULL,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  sound TEXT,
  group_id TEXT,
  open_url TEXT,
  execute_cmd TEXT,
  method TEXT NOT NULL,
  dismissed_at TEXT
)`;

const REQUIRED_COLUMNS = [
  "id",
  "timestamp",
  "title",
  "message",
  "sound",
  "group_id",
  "open_url",
  "execute_cmd",
  "method",
] as const;

export class MessageStore {
  readonly database: Database;

  constructor(
    readonly path: string,
    options: { create?: boolean } = {},
  ) {
    const create = options.create ?? true;
    if (!create && !existsSync(path)) throw new Error(`No notification log found at ${path}`);
    if (create) mkdirSync(dirname(path), { recursive: true, mode: 0o700 });

    this.database = new Database(path, { create, strict: true });
    if (create) chmodSync(path, 0o600);
    this.database.exec("PRAGMA busy_timeout = 5000");
    this.database.exec("PRAGMA journal_mode = WAL");
    this.database.exec("PRAGMA synchronous = NORMAL");
    this.migrate();
  }

  private migrate(): void {
    const versionRow = this.database.query("PRAGMA user_version").get() as {
      user_version: number;
    } | null;
    const version = versionRow?.user_version ?? 0;
    if (version > SCHEMA_VERSION) {
      throw new Error(`Unsupported notification database version ${version}`);
    }

    this.database.transaction(() => {
      const table = this.database
        .query("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?")
        .get("messages");
      if (!table) {
        this.database.exec(CREATE_MESSAGES);
      } else {
        const columnRows = this.database.query("PRAGMA table_info(messages)").all() as Array<{
          name: string;
        }>;
        const columns = new Set(columnRows.map((row) => row.name));
        const missing = REQUIRED_COLUMNS.filter((column) => !columns.has(column));
        if (missing.length > 0) {
          throw new Error(`Incompatible notification database: missing ${missing.join(", ")}`);
        }
        if (!columns.has("dismissed_at")) {
          this.database.exec("ALTER TABLE messages ADD COLUMN dismissed_at TEXT");
          this.database.exec(
            "UPDATE messages SET dismissed_at = timestamp WHERE dismissed_at IS NULL",
          );
        }
      }
      this.database.exec(`PRAGMA user_version = ${SCHEMA_VERSION}`);
    })();
  }

  add(message: NewMessage): number {
    const result = this.database
      .query(
        `INSERT INTO messages
          (timestamp, title, message, sound, group_id, open_url, execute_cmd, method)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(
        message.timestamp,
        message.title,
        message.message,
        message.sound,
        message.groupId,
        message.openUrl,
        message.execute,
        message.method,
      );
    return Number(result.lastInsertRowid);
  }

  list(options: ListOptions, now = new Date()): MessageRecord[] {
    if (!Number.isInteger(options.limit) || options.limit < 1 || options.limit > MAX_LIST_LIMIT) {
      throw new Error(`Limit must be an integer between 1 and ${MAX_LIST_LIMIT}`);
    }

    const conditions: string[] = [];
    const bindings: Array<string | number> = [];
    if (options.since) {
      conditions.push("timestamp >= ?");
      bindings.push(parseSince(options.since, now));
    }
    if (options.search) {
      conditions.push("(title LIKE ? ESCAPE '\\' OR message LIKE ? ESCAPE '\\')");
      const literal = options.search.replace(/[\\%_]/g, "\\$&");
      const query = `%${literal}%`;
      bindings.push(query, query);
    }

    const where = conditions.length > 0 ? ` WHERE ${conditions.join(" AND ")}` : "";
    return this.database
      .query(`SELECT * FROM messages${where} ORDER BY timestamp DESC, id DESC LIMIT ?`)
      .all(...bindings, options.limit) as MessageRecord[];
  }

  dismiss(id: number, timestamp = new Date().toISOString()): boolean {
    const result = this.database
      .query("UPDATE messages SET dismissed_at = ? WHERE id = ? AND dismissed_at IS NULL")
      .run(timestamp, id);
    if (result.changes > 0) return true;

    return this.database.query("SELECT id FROM messages WHERE id = ?").get(id) !== null;
  }

  close(): void {
    this.database.close();
  }
}

export function parseSince(value: string, now = new Date()): string {
  const relative = /^(\d+)([mhdw])$/.exec(value);
  if (relative) {
    const amount = Number(relative[1]);
    const factors: Record<string, number> = {
      m: 60_000,
      h: 3_600_000,
      d: 86_400_000,
      w: 604_800_000,
    };
    const factor = factors[relative[2] ?? ""];
    if (factor === undefined || !Number.isSafeInteger(amount * factor)) {
      throw new Error(`Invalid --since value: ${value}`);
    }
    return new Date(now.getTime() - amount * factor).toISOString();
  }

  const match =
    /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,9})?)?(?:Z|([+-])(\d{2}):(\d{2}))?)?$/.exec(
      value,
    );
  if (!match) throw new Error(`Invalid --since value: ${value}`);
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4] ?? 0);
  const minute = Number(match[5] ?? 0);
  const second = Number(match[6] ?? 0);
  const offsetHour = Number(match[8] ?? 0);
  const offsetMinute = Number(match[9] ?? 0);
  const leapYear = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const daysInMonth = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
  if (
    month < 1 ||
    month > 12 ||
    day < 1 ||
    daysInMonth === undefined ||
    day > daysInMonth ||
    hour > 23 ||
    minute > 59 ||
    second > 59 ||
    offsetHour > 23 ||
    offsetMinute > 59
  ) {
    throw new Error(`Invalid --since value: ${value}`);
  }
  const normalized = /(?:Z|[+-]\d{2}:\d{2})$/.test(value)
    ? value
    : value.includes("T")
      ? `${value}Z`
      : `${value}T00:00:00Z`;
  const parsed = new Date(normalized);
  if (Number.isNaN(parsed.getTime())) throw new Error(`Invalid --since value: ${value}`);
  return parsed.toISOString();
}

export function formatLocalTimestamp(timestamp: string): string {
  const date = new Date(timestamp);
  if (Number.isNaN(date.getTime())) return timestamp;
  const two = (value: number) => String(value).padStart(2, "0");
  const zone =
    new Intl.DateTimeFormat(undefined, { timeZoneName: "short" })
      .formatToParts(date)
      .find((part) => part.type === "timeZoneName")?.value ?? "local";
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())} ${two(date.getHours())}:${two(date.getMinutes())}:${two(date.getSeconds())} ${zone}`;
}

export function formatRecord(record: MessageRecord): MessageOutput {
  const output: MessageOutput = {
    id: record.id,
    timestamp: formatLocalTimestamp(record.timestamp),
    title: record.title,
    message: record.message,
    method: record.method,
    dismissed_at: record.dismissed_at,
  };
  if (record.sound !== null) output.sound = record.sound;
  if (record.group_id !== null) output.group_id = record.group_id;
  if (record.open_url !== null) output.open_url = record.open_url;
  if (record.execute_cmd !== null) output.execute = record.execute_cmd;
  return output;
}

export function createStore(): MessageStore {
  return new MessageStore(logDatabasePath());
}
