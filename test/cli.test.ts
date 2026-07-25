import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { type CliDependencies, type CliIO, runCli, VERSION } from "../src/cli.ts";
import type { NotificationRequest } from "../src/types.ts";

const temporaryDirectories: string[] = [];

function captureIO(): { io: CliIO; stdout: string[]; stderr: string[] } {
  const stdout: string[] = [];
  const stderr: string[] = [];
  return {
    io: {
      stdout: { write: (value) => stdout.push(value) },
      stderr: { write: (value) => stderr.push(value) },
    },
    stdout,
    stderr,
  };
}

function fixture(): {
  deps: Partial<CliDependencies>;
  requests: NotificationRequest[];
  closed: string[];
  phone: Array<[string, string]>;
  io: ReturnType<typeof captureIO>;
  database: string;
} {
  const directory = mkdtempSync(join(tmpdir(), "agentnotify-cli-"));
  temporaryDirectories.push(directory);
  const database = join(directory, "log.db");
  const io = captureIO();
  const requests: NotificationRequest[] = [];
  const closed: string[] = [];
  const phone: Array<[string, string]> = [];
  return {
    io,
    database,
    requests,
    closed,
    phone,
    deps: {
      io: io.io,
      env: { AGENTNOTIFY_LOG_DB: database },
      home: directory,
      now: () => new Date("2025-02-03T04:05:06.000Z"),
      notify: async (request) => {
        requests.push(request);
        return { success: true, method: "fake-notifier" };
      },
      closeNotification: async (group) => {
        closed.push(group);
      },
      notifyPhone: async (title, message) => {
        phone.push([title, message]);
        return true;
      },
    },
  };
}

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

describe("agentnotify CLI", () => {
  test("has root, version, and command help", async () => {
    const root = fixture();
    expect(await runCli([], root.deps)).toBe(0);
    expect(root.io.stdout.join("")).toContain(`agentnotify ${VERSION}`);
    expect(root.io.stdout.join("")).toContain("show-message");

    const version = fixture();
    expect(await runCli(["--version"], version.deps)).toBe(0);
    expect(version.io.stdout.join("")).toBe("0.1.0\n");

    const command = fixture();
    expect(await runCli(["show-message", "--help"], command.deps)).toBe(0);
    expect(command.io.stdout.join("")).toContain("--no-phone");
  });

  test("the package bin source is directly executable", () => {
    expect(statSync(new URL("../src/cli.ts", import.meta.url)).mode & 0o111).not.toBe(0);
  });

  test("shows, logs, and optionally phones with one compact JSON result", async () => {
    const first = fixture();
    const code = await runCli(
      [
        "show-message",
        "-t",
        "Build",
        "-m",
        "Passed",
        "--group",
        "build-one",
        "--open-url",
        "https://example.test/result",
        "--execute",
        "open result.txt",
      ],
      first.deps,
    );
    expect(code).toBe(0);
    expect(first.io.stdout.join("")).toBe('{"success":true,"method":"fake-notifier"}\n');
    expect(first.io.stderr).toEqual([]);
    expect(first.requests[0]).toEqual({
      title: "Build",
      message: "Passed",
      sound: "Ping",
      group: "build-one",
      openUrl: "https://example.test/result",
      execute: "open result.txt",
    });
    expect(first.phone).toEqual([["Build", "Passed"]]);

    first.io.stdout.length = 0;
    expect(await runCli(["list-messages"], first.deps)).toBe(0);
    const listed = JSON.parse(first.io.stdout.join("")) as Array<Record<string, unknown>>;
    expect(listed).toHaveLength(1);
    expect(listed[0]?.title).toBe("Build");
    expect(listed[0]?.timestamp).not.toBe("2025-02-03T04:05:06.000Z");

    const skipped = fixture();
    expect(
      await runCli(["show-message", "-t", "Build", "-m", "Passed", "--no-phone"], skipped.deps),
    ).toBe(0);
    expect(skipped.phone).toEqual([]);
  });

  test("lists with search/since, dismisses idempotently, and errors for a missing ID", async () => {
    const item = fixture();
    await runCli(["show-message", "-t", "Alpha", "-m", "needle", "--no-phone"], item.deps);
    item.io.stdout.length = 0;

    expect(
      await runCli(
        ["list-messages", "--search", "needle", "--since", "1h", "--limit", "1"],
        item.deps,
      ),
    ).toBe(0);
    expect(JSON.parse(item.io.stdout.join(""))).toHaveLength(1);

    item.io.stdout.length = 0;
    expect(await runCli(["dismiss-message", "1"], item.deps)).toBe(0);
    expect(item.io.stdout.join("")).toBe('{"dismissed":1}\n');
    item.io.stdout.length = 0;
    expect(await runCli(["dismiss-message", "1"], item.deps)).toBe(0);

    item.io.stdout.length = 0;
    item.io.stderr.length = 0;
    expect(await runCli(["dismiss-message", "999"], item.deps)).toBe(1);
    expect(item.io.stdout).toEqual([]);
    expect(item.io.stderr.join("")).toContain("No notification with id 999");
  });

  test("closes a group without changing the log", async () => {
    const item = fixture();
    await runCli(
      ["show-message", "-t", "Alpha", "-m", "body", "--group", "group-one", "--no-phone"],
      item.deps,
    );
    item.io.stdout.length = 0;
    expect(await runCli(["close-message", "--group", "group-one"], item.deps)).toBe(0);
    expect(item.closed).toEqual(["group-one"]);
    expect(item.io.stdout.join("")).toBe('{"closed":"group-one"}\n');

    item.io.stdout.length = 0;
    await runCli(["list-messages"], item.deps);
    expect(
      (JSON.parse(item.io.stdout.join("")) as Array<{ dismissed_at: string | null }>)[0]
        ?.dismissed_at,
    ).toBeNull();
  });

  test("returns 2 for unknown, missing, and invalid arguments", async () => {
    for (const args of [
      ["unknown"],
      ["show-message", "--title", "title"],
      ["list-messages", "--limit", "0"],
      ["list-messages", "--since", "1H"],
      ["show-message", "--title", "title", "--message", "body", "--sound", "--no-phone"],
      ["dismiss-message", "9007199254740993"],
      ["close-message", "--group=-remove"],
    ]) {
      const item = fixture();
      expect(await runCli(args, item.deps)).toBe(2);
      expect(item.io.stdout).toEqual([]);
      expect(item.io.stderr.join("")).toStartWith("agentnotify: ");
    }
  });

  test("returns 1 with stderr when desktop delivery fails and never phones or logs", async () => {
    const item = fixture();
    item.deps.notify = async () => ({ success: false });
    expect(await runCli(["show-message", "-t", "title", "-m", "body"], item.deps)).toBe(1);
    expect(item.io.stdout).toEqual([]);
    expect(item.io.stderr.join("")).toContain("Failed to send notification");
    expect(item.phone).toEqual([]);
    expect(Bun.file(item.database).size).toBe(0);
  });

  test("phone failure never flips desktop success", async () => {
    const item = fixture();
    item.deps.notifyPhone = async () => false;
    expect(await runCli(["show-message", "-t", "title", "-m", "body"], item.deps)).toBe(0);
    expect(item.io.stdout.join("")).toContain('"success":true');
  });
});
