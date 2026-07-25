#!/usr/bin/env bun

import { homedir } from "node:os";
import {
  closeDesktopNotification,
  sendDesktopNotification,
  validateNotificationRequest,
} from "./notifier.ts";
import { type Environment, logDatabasePath } from "./paths.ts";
import { defaultPhoneDependencies, sendPhoneNotification } from "./phone.ts";
import { formatRecord, MAX_LIST_LIMIT, MessageStore, parseSince } from "./store.ts";
import type { CliIO, NotificationRequest, NotificationResult } from "./types.ts";

export const VERSION = "0.1.0";

export type { CliIO } from "./types.ts";

export interface CliDependencies {
  io: CliIO;
  env: Environment;
  home: string;
  now(): Date;
  notify(request: NotificationRequest): Promise<NotificationResult>;
  closeNotification(group: string): Promise<void>;
  notifyPhone(title: string, message: string): Promise<boolean>;
  openStore(path: string, options?: { create?: boolean }): MessageStore;
}

const ROOT_HELP = `agentnotify ${VERSION}

Send and browse desktop notifications from agents and scripts.

Usage:
  agentnotify <command> [options]

Commands:
  show-message       Send a desktop notification
  list-messages      Browse the notification log
  dismiss-message    Dismiss a notification by ID
  close-message      Close a notification by group ID

Options:
  -h, --help         Show this help
  -v, --version      Show the version
`;

const COMMAND_HELP: Readonly<Record<string, string>> = {
  "show-message": `Usage: agentnotify show-message -t TITLE -m MESSAGE [options]

Options:
  -t, --title TITLE       Notification title (required)
  -m, --message MESSAGE   Notification message (required)
  -s, --sound SOUND       Sound name (default: Ping)
      --open-url URL      URL to open when clicked (macOS)
      --group ID          Notification group ID (macOS)
      --execute COMMAND   Command to run when clicked (macOS)
      --no-phone          Skip phone delivery
  -h, --help              Show this help
`,
  "list-messages": `Usage: agentnotify list-messages [options]

Options:
  -n, --limit COUNT       Maximum results (default: 20, max: ${MAX_LIST_LIMIT})
      --since WHEN        Relative m/h/d/w duration or ISO timestamp
  -q, --search TEXT       Search titles and messages
  -h, --help              Show this help
`,
  "dismiss-message": `Usage: agentnotify dismiss-message ID

Dismiss a notification log record. Repeated dismissal is successful.
`,
  "close-message": `Usage: agentnotify close-message --group ID

Close a grouped desktop notification without dismissing its log record.
`,
};

class UsageError extends Error {}

function defaults(): CliDependencies {
  const env = process.env;
  const home = homedir();
  return {
    io: { stdout: process.stdout, stderr: process.stderr },
    env,
    home,
    now: () => new Date(),
    notify: (request) => sendDesktopNotification(request),
    closeNotification: (group) => closeDesktopNotification(group),
    notifyPhone: (title, message) =>
      sendPhoneNotification(title, message, { ...defaultPhoneDependencies, env, home }),
    openStore: (path, options) => new MessageStore(path, options),
  };
}

function json(io: CliIO, value: unknown): void {
  io.stdout.write(`${JSON.stringify(value)}\n`);
}

function fail(message: string): never {
  throw new UsageError(message);
}

interface ParsedOptions {
  values: Map<string, string>;
  flags: Set<string>;
  positional: string[];
}

function parseOptions(
  args: readonly string[],
  valueOptions: Readonly<Record<string, string>>,
  flagOptions: Readonly<Record<string, string>> = {},
): ParsedOptions {
  const values = new Map<string, string>();
  const flags = new Set<string>();
  const positional: string[] = [];

  for (let index = 0; index < args.length; index += 1) {
    const token = args[index];
    if (token === undefined) continue;
    const equals = token.startsWith("--") ? token.indexOf("=") : -1;
    const name = equals > 0 ? token.slice(0, equals) : token;
    const canonicalValue = valueOptions[name];
    if (canonicalValue) {
      const value = equals > 0 ? token.slice(equals + 1) : args[index + 1];
      if (value === undefined || (equals < 0 && value.startsWith("-"))) {
        fail(`Option ${name} requires a value`);
      }
      if (values.has(canonicalValue)) fail(`Option ${name} was provided more than once`);
      values.set(canonicalValue, value);
      if (equals < 0) index += 1;
      continue;
    }

    const canonicalFlag = flagOptions[name];
    if (canonicalFlag && equals < 0) {
      if (flags.has(canonicalFlag)) fail(`Option ${name} was provided more than once`);
      flags.add(canonicalFlag);
      continue;
    }
    if (token.startsWith("-")) fail(`Unknown option: ${name}`);
    positional.push(token);
  }
  return { values, flags, positional };
}

function required(options: ParsedOptions, name: string): string {
  const value = options.values.get(name);
  if (value === undefined || value.length === 0) fail(`Missing required option: --${name}`);
  return value;
}

async function showMessage(args: readonly string[], deps: CliDependencies): Promise<void> {
  const options = parseOptions(
    args,
    {
      "-t": "title",
      "--title": "title",
      "-m": "message",
      "--message": "message",
      "-s": "sound",
      "--sound": "sound",
      "--open-url": "openUrl",
      "--group": "group",
      "--execute": "execute",
    },
    { "--no-phone": "noPhone" },
  );
  if (options.positional.length > 0) fail(`Unexpected argument: ${options.positional[0]}`);

  const request: NotificationRequest = {
    title: required(options, "title"),
    message: required(options, "message"),
    sound: options.values.get("sound") ?? "Ping",
  };
  const openUrl = options.values.get("openUrl");
  const group = options.values.get("group");
  const execute = options.values.get("execute");
  if (openUrl !== undefined) request.openUrl = openUrl;
  if (group !== undefined) request.group = group;
  if (execute !== undefined) request.execute = execute;
  try {
    validateNotificationRequest(request);
  } catch (error) {
    fail(error instanceof Error ? error.message : String(error));
  }

  const result = await deps.notify(request);
  if (!result.success || !result.method) throw new Error("Failed to send notification");

  const store = deps.openStore(logDatabasePath({ env: deps.env, home: deps.home }));
  try {
    store.add({
      timestamp: deps.now().toISOString(),
      title: request.title,
      message: request.message,
      sound: request.sound ?? null,
      groupId: request.group ?? null,
      openUrl: request.openUrl ?? null,
      execute: request.execute ?? null,
      method: result.method,
    });
  } finally {
    store.close();
  }

  if (!options.flags.has("noPhone")) await deps.notifyPhone(request.title, request.message);
  json(deps.io, { success: true, method: result.method });
}

function listMessages(args: readonly string[], deps: CliDependencies): void {
  const options = parseOptions(args, {
    "-n": "limit",
    "--limit": "limit",
    "--since": "since",
    "-q": "search",
    "--search": "search",
  });
  if (options.positional.length > 0) fail(`Unexpected argument: ${options.positional[0]}`);
  const limitValue = options.values.get("limit") ?? "20";
  if (!/^\d+$/.test(limitValue)) fail("--limit must be an integer");
  const limit = Number(limitValue);
  if (limit < 1 || limit > MAX_LIST_LIMIT) {
    fail(`--limit must be between 1 and ${MAX_LIST_LIMIT}`);
  }
  const since = options.values.get("since");
  if (since !== undefined) {
    try {
      parseSince(since, deps.now());
    } catch (error) {
      fail(error instanceof Error ? error.message : String(error));
    }
  }

  const store = deps.openStore(logDatabasePath({ env: deps.env, home: deps.home }), {
    create: false,
  });
  try {
    json(
      deps.io,
      store
        .list(
          {
            limit,
            ...(since === undefined ? {} : { since }),
            ...(options.values.has("search") ? { search: options.values.get("search") } : {}),
          },
          deps.now(),
        )
        .map(formatRecord),
    );
  } finally {
    store.close();
  }
}

function dismissMessage(args: readonly string[], deps: CliDependencies): void {
  const options = parseOptions(args, {});
  if (options.positional.length !== 1) fail("dismiss-message requires exactly one ID");
  const idValue = options.positional[0] ?? "";
  if (!/^\d+$/.test(idValue)) fail("ID must be a positive safe integer");
  const id = Number(idValue);
  if (!Number.isSafeInteger(id) || id < 1) fail("ID must be a positive safe integer");

  const store = deps.openStore(logDatabasePath({ env: deps.env, home: deps.home }), {
    create: false,
  });
  try {
    if (!store.dismiss(id, deps.now().toISOString())) {
      throw new Error(`No notification with id ${id}`);
    }
  } finally {
    store.close();
  }
  json(deps.io, { dismissed: id });
}

async function closeMessage(args: readonly string[], deps: CliDependencies): Promise<void> {
  const options = parseOptions(args, { "--group": "group" });
  if (options.positional.length > 0) fail(`Unexpected argument: ${options.positional[0]}`);
  const group = required(options, "group");
  try {
    validateNotificationRequest({ title: "", message: "", group });
  } catch (error) {
    fail(error instanceof Error ? error.message : String(error));
  }
  await deps.closeNotification(group);
  json(deps.io, { closed: group });
}

export async function runCli(
  args: readonly string[],
  dependencies: Partial<CliDependencies> = {},
): Promise<number> {
  const base = defaults();
  const env = dependencies.env ?? base.env;
  const home = dependencies.home ?? base.home;
  const deps: CliDependencies = {
    ...base,
    ...dependencies,
    env,
    home,
    notifyPhone:
      dependencies.notifyPhone ??
      ((title, message) =>
        sendPhoneNotification(title, message, { ...defaultPhoneDependencies, env, home })),
  };
  try {
    if (
      args.length === 0 ||
      (args.length === 1 && ["-h", "--help", "help"].includes(args[0] ?? ""))
    ) {
      deps.io.stdout.write(ROOT_HELP);
      return 0;
    }
    if (args.length === 1 && ["-v", "--version", "version"].includes(args[0] ?? "")) {
      deps.io.stdout.write(`${VERSION}\n`);
      return 0;
    }

    const command = args[0] ?? "";
    const commandArgs = args.slice(1);
    if (commandArgs.length === 1 && ["-h", "--help"].includes(commandArgs[0] ?? "")) {
      const help = COMMAND_HELP[command];
      if (!help) fail(`Unknown command: ${command}`);
      deps.io.stdout.write(help);
      return 0;
    }

    switch (command) {
      case "show-message":
        await showMessage(commandArgs, deps);
        break;
      case "list-messages":
        listMessages(commandArgs, deps);
        break;
      case "dismiss-message":
        dismissMessage(commandArgs, deps);
        break;
      case "close-message":
        await closeMessage(commandArgs, deps);
        break;
      default:
        fail(`Unknown command: ${command}`);
    }
    return 0;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    deps.io.stderr.write(`agentnotify: ${message}\n`);
    return error instanceof UsageError ? 2 : 1;
  }
}

if (import.meta.main) {
  process.exitCode = await runCli(Bun.argv.slice(2));
}
