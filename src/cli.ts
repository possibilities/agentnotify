#!/usr/bin/env bun

export const VERSION = "0.1.0";

export interface CliIO {
  stdout: { write(value: string): unknown };
  stderr: { write(value: string): unknown };
}

const HELP = `agentnotify ${VERSION}

Send and browse desktop notifications from agents and scripts.

Usage:
  agentnotify [options]

Options:
  -h, --help     Show this help
  -v, --version  Show the version
`;

const defaultIO: CliIO = {
  stdout: process.stdout,
  stderr: process.stderr,
};

export function run(args: readonly string[], io: CliIO = defaultIO): void {
  if (args.length === 1 && (args[0] === "--help" || args[0] === "-h")) {
    io.stdout.write(HELP);
    return;
  }

  if (args.length === 1 && (args[0] === "--version" || args[0] === "-v")) {
    io.stdout.write(`${VERSION}\n`);
    return;
  }

  throw new Error("agentnotify: implementation pending");
}

if (import.meta.main) {
  try {
    run(Bun.argv.slice(2));
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    defaultIO.stderr.write(`${message}\n`);
    process.exitCode = 1;
  }
}
