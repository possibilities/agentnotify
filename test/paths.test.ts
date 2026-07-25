import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import { dataDirectory, logDatabasePath, phoneConfigPath } from "../src/paths.ts";

describe("paths", () => {
  test("uses the exact database override first", () => {
    const env = {
      AGENTNOTIFY_LOG_DB: "/override/messages.sqlite",
      AGENTNOTIFY_DATA_DIR: "/data",
      XDG_DATA_HOME: "/xdg",
    };
    expect(logDatabasePath({ env, home: "/home/test" })).toBe("/override/messages.sqlite");
  });

  test("uses data directory before XDG and falls back to the home share", () => {
    expect(logDatabasePath({ env: { AGENTNOTIFY_DATA_DIR: "/data" }, home: "/home/test" })).toBe(
      "/data/log.db",
    );
    expect(dataDirectory({ env: { XDG_DATA_HOME: "/xdg" }, home: "/home/test" })).toBe(
      "/xdg/agentnotify",
    );
    expect(logDatabasePath({ env: {}, home: "/home/test" })).toBe(
      join("/home/test", ".local", "share", "agentnotify", "log.db"),
    );
  });

  test("ignores empty overrides and locates phone configuration", () => {
    expect(logDatabasePath({ env: { AGENTNOTIFY_LOG_DB: "" }, home: "/home/test" })).toContain(
      "/home/test/.local/share/agentnotify/log.db",
    );
    expect(phoneConfigPath({ env: {}, home: "/home/test" })).toBe(
      "/home/test/.config/agentnotify/config.yaml",
    );
  });
});
