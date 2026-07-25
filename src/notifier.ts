import { findExecutable, localNotifierArgv, runProcess, spawnProcess } from "./process.ts";
import type {
  FindExecutable,
  NotificationRequest,
  NotificationResult,
  SpawnProcess,
} from "./types.ts";

export interface NotifierDependencies {
  platform: NodeJS.Platform | string;
  find: FindExecutable;
  spawn: SpawnProcess;
  fallbackArgv: readonly string[];
}

export const defaultNotifierDependencies: NotifierDependencies = {
  platform: process.platform,
  find: findExecutable,
  spawn: spawnProcess,
  fallbackArgv: localNotifierArgv(),
};

function validatePositional(name: string, value: string | undefined): void {
  if (value === undefined) return;
  if (value.length === 0 || value.startsWith("-") || value.includes("\0")) {
    throw new Error(`Invalid ${name}: values must be nonempty and must not begin with '-'`);
  }
}

export function validateNotificationRequest(request: NotificationRequest): void {
  validatePositional("--group", request.group);
  validatePositional("--open-url", request.openUrl);
  validatePositional("--execute", request.execute);
}

export async function sendDesktopNotification(
  request: NotificationRequest,
  dependencies: NotifierDependencies = defaultNotifierDependencies,
): Promise<NotificationResult> {
  validateNotificationRequest(request);

  if (dependencies.platform === "darwin") {
    const terminalNotifier = dependencies.find("terminal-notifier");
    if (terminalNotifier) {
      const argv = [terminalNotifier, "-title", request.title, "-message", request.message];
      if (request.sound) argv.push("-sound", request.sound);
      if (request.openUrl) argv.push("-open", request.openUrl);
      if (request.execute) argv.push("-execute", request.execute);
      if (request.group) argv.push("-group", request.group);
      if (await runProcess(argv, dependencies.spawn)) {
        return { success: true, method: "terminal-notifier" };
      }
    }
  }

  const fallback = [...dependencies.fallbackArgv, "-t", request.title, "-m", request.message];
  if (await runProcess(fallback, dependencies.spawn)) {
    return { success: true, method: "node-notifier" };
  }
  return { success: false };
}

export async function closeDesktopNotification(
  group: string,
  dependencies: Pick<
    NotifierDependencies,
    "platform" | "find" | "spawn"
  > = defaultNotifierDependencies,
): Promise<void> {
  validatePositional("--group", group);
  if (dependencies.platform !== "darwin") return;
  const terminalNotifier = dependencies.find("terminal-notifier");
  if (!terminalNotifier) return;
  await runProcess([terminalNotifier, "-remove", group], dependencies.spawn);
}
