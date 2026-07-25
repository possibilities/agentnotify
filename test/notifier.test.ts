import { describe, expect, test } from "bun:test";
import {
  closeDesktopNotification,
  type NotifierDependencies,
  sendDesktopNotification,
} from "../src/notifier.ts";

function fakes(exitCodes: number[], platform = "darwin") {
  const calls: string[][] = [];
  const dependencies: NotifierDependencies = {
    platform,
    find: (name) => (name === "terminal-notifier" ? "/tools/terminal-notifier" : null),
    fallbackArgv: ["/runtime/bun", "/local/node-notifier-cli/bin.js"],
    spawn: (argv) => {
      calls.push([...argv]);
      return { exited: Promise.resolve(exitCodes.shift() ?? 0) };
    },
  };
  return { calls, dependencies };
}

describe("desktop notifier", () => {
  test("prioritizes terminal-notifier and preserves optional values as exact argv", async () => {
    const { calls, dependencies } = fakes([0]);
    const result = await sendDesktopNotification(
      {
        title: "title with spaces",
        message: "body; not a shell command",
        sound: "Ping",
        openUrl: "https://example.test/a?x=1&y=2",
        execute: "open /Applications/Example.app",
        group: "build group",
      },
      dependencies,
    );
    expect(result).toEqual({ success: true, method: "terminal-notifier" });
    expect(calls).toEqual([
      [
        "/tools/terminal-notifier",
        "-title",
        "title with spaces",
        "-message",
        "body; not a shell command",
        "-sound",
        "Ping",
        "-open",
        "https://example.test/a?x=1&y=2",
        "-execute",
        "open /Applications/Example.app",
        "-group",
        "build group",
      ],
    ]);
  });

  test("falls back to the pinned local CLI after an immediate failure", async () => {
    const { calls, dependencies } = fakes([7, 0]);
    const result = await sendDesktopNotification(
      {
        title: "title",
        message: "message",
        sound: "Glass",
        openUrl: "https://example.test/result",
      },
      dependencies,
    );
    expect(result).toEqual({ success: true, method: "node-notifier" });
    expect(calls[1]).toEqual([
      "/runtime/bun",
      "/local/node-notifier-cli/bin.js",
      "-t",
      "title",
      "-m",
      "message",
      "-s",
      "Glass",
      "-o",
      "https://example.test/result",
    ]);
  });

  test("reports failure when both exact-argv processes fail", async () => {
    const { dependencies } = fakes([1, 1]);
    expect(
      await sendDesktopNotification({ title: "title", message: "message" }, dependencies),
    ).toEqual({ success: false });
  });

  test("rejects option-like optional values before spawning", async () => {
    const { calls, dependencies } = fakes([0]);
    await expect(
      sendDesktopNotification(
        { title: "title", message: "message", group: "-remove" },
        dependencies,
      ),
    ).rejects.toThrow("Invalid --group");
    expect(calls).toEqual([]);
  });

  test("closes groups on macOS and is a successful no-op elsewhere or when unavailable", async () => {
    const darwin = fakes([0]);
    await closeDesktopNotification("group one", darwin.dependencies);
    expect(darwin.calls).toEqual([["/tools/terminal-notifier", "-remove", "group one"]]);

    const linux = fakes([], "linux");
    await closeDesktopNotification("group one", linux.dependencies);
    expect(linux.calls).toEqual([]);

    const missing = fakes([]);
    missing.dependencies.find = () => null;
    await closeDesktopNotification("group one", missing.dependencies);
    expect(missing.calls).toEqual([]);

    const failing = fakes([1]);
    await expect(closeDesktopNotification("group one", failing.dependencies)).rejects.toThrow(
      "failed to close",
    );
  });
});
