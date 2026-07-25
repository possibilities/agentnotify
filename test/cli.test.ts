import { describe, expect, test } from "bun:test";
import { type CliIO, run, VERSION } from "../src/cli.ts";

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

describe("agentnotify CLI", () => {
  test("prints deterministic help", () => {
    const capture = captureIO();

    run(["--help"], capture.io);

    expect(capture.stdout.join("")).toBe(`agentnotify ${VERSION}

Send and browse desktop notifications from agents and scripts.

Usage:
  agentnotify [options]

Options:
  -h, --help     Show this help
  -v, --version  Show the version
`);
    expect(capture.stderr).toEqual([]);
  });

  test("prints the version", () => {
    const capture = captureIO();

    run(["--version"], capture.io);

    expect(capture.stdout.join("")).toBe("0.1.0\n");
    expect(capture.stderr).toEqual([]);
  });
});
