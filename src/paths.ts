import { homedir } from "node:os";
import { join } from "node:path";

export type Environment = Readonly<Record<string, string | undefined>>;

export interface PathOptions {
  env?: Environment;
  home?: string;
}

function nonempty(value: string | undefined): string | undefined {
  return value && value.length > 0 ? value : undefined;
}

export function dataDirectory(options: PathOptions = {}): string {
  const env = options.env ?? process.env;
  const home = options.home ?? homedir();
  const overridden = nonempty(env.AGENTNOTIFY_DATA_DIR);
  if (overridden) return overridden;

  const xdg = nonempty(env.XDG_DATA_HOME) ?? join(home, ".local", "share");
  return join(xdg, "agentnotify");
}

export function logDatabasePath(options: PathOptions = {}): string {
  const env = options.env ?? process.env;
  return nonempty(env.AGENTNOTIFY_LOG_DB) ?? join(dataDirectory(options), "log.db");
}

export function phoneConfigPath(options: PathOptions = {}): string {
  const home = options.home ?? homedir();
  return join(home, ".config", "agentnotify", "config.yaml");
}
