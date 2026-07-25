import { createHandler, type ListOptions, type NotificationMessage, type Store } from "./http";

export interface Listener {
  hostname: string;
  port: number;
  stop(closeActiveConnections?: boolean): void | Promise<void>;
}

export interface ServeOptions {
  hostname: string;
  port: number;
  fetch(request: Request): Response | Promise<Response>;
}

export type Serve = (options: ServeOptions) => Listener;

export interface ServerEnvironment {
  [key: string]: string | undefined;
  AGENTNOTIFY_HOSTS?: string;
  AGENTNOTIFY_PORT?: string;
}

export function serverConfig(environment: ServerEnvironment = process.env): {
  hosts: string[];
  port: number;
} {
  const rawPort = environment.AGENTNOTIFY_PORT;
  const port = rawPort === undefined || rawPort === "" ? 7700 : Number(rawPort);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("AGENTNOTIFY_PORT must be an integer between 1 and 65535");
  }

  const configuredHosts = environment.AGENTNOTIFY_HOSTS?.split(",")
    .map((host) => host.trim())
    .filter(Boolean);
  const hosts = [...new Set(configuredHosts?.length ? configuredHosts : ["127.0.0.1"])] as string[];
  return { hosts, port };
}

export function startServers(
  store: Store,
  environment: ServerEnvironment = process.env,
  serve: Serve = Bun.serve as unknown as Serve,
): Listener[] {
  const { hosts, port } = serverConfig(environment);
  const fetch = createHandler(store);
  return hosts.map((hostname) => serve({ hostname, port, fetch }));
}

type UnknownRecord = Record<string, unknown>;
type ListFunction = (
  options: ListOptions,
) => Promise<NotificationMessage[]> | NotificationMessage[];
type DismissFunction = (id: number) => Promise<boolean> | boolean;

function asStore(candidate: UnknownRecord): Store {
  const list = candidate.list;
  const dismiss = candidate.dismiss;
  if (typeof list !== "function" || typeof dismiss !== "function") {
    throw new Error("src/store.ts must expose a store with list(options) and dismiss(id)");
  }
  return {
    list: (options) => (list as ListFunction).call(candidate, options),
    dismiss: (id) => (dismiss as DismissFunction).call(candidate, id),
  };
}

export async function loadStore(): Promise<Store> {
  // Kept dynamic so this standalone web branch typechecks before the core store lands.
  const storePath: string = "./store.ts";
  const module = (await import(storePath)) as UnknownRecord;
  const factory = module.createStore ?? module.openStore;
  if (typeof factory === "function") {
    return asStore((await factory()) as UnknownRecord);
  }
  const candidate = (module.default ?? module.store ?? module) as UnknownRecord;
  return asStore(candidate);
}

if (Bun.main === import.meta.path) {
  const store = await loadStore();
  const listeners = startServers(store);
  for (const listener of listeners) {
    console.log(`agentnotify listening on http://${listener.hostname}:${listener.port}`);
  }
}
