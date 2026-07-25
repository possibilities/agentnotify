import { describe, expect, test } from "bun:test";
import { localNotifierArgv, runProcess } from "../src/process.ts";

describe("process helpers", () => {
  test("awaits process exit status", async () => {
    expect(await runProcess(["fake"], () => ({ exited: Promise.resolve(0) }))).toBe(true);
    expect(await runProcess(["fake"], () => ({ exited: Promise.resolve(9) }))).toBe(false);
    expect(
      await runProcess(["fake"], () => {
        throw new Error("cannot spawn");
      }),
    ).toBe(false);
  });

  test("resolves the installed notifier CLI without a network runner", () => {
    const argv = localNotifierArgv();
    expect(argv[0]).toBe(process.execPath);
    expect(argv[1]).toEndWith("/node-notifier-cli/bin.js");
  });
});
