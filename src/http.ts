import { readFile, stat } from "node:fs/promises";
import { basename, extname, resolve, sep } from "node:path";
import { parseSince } from "./store.ts";

export interface NotificationMessage {
  id: number;
  timestamp: string;
  title: string;
  message: string;
  sound: string | null;
  group_id: string | null;
  open_url: string | null;
  method: string;
  dismissed_at: string | null;
}

export interface ListOptions {
  limit: number;
  search?: string;
  since?: string;
}

export interface Store {
  list(options: ListOptions): Promise<NotificationMessage[]> | NotificationMessage[];
  dismiss(id: number): Promise<boolean> | boolean;
}

export interface HandlerOptions {
  distDir?: string;
}

const DEFAULT_DIST_DIR = resolve(import.meta.dir, "../dist");
const HASHED_ASSET = /(?:^|[.-])[a-z0-9_-]{8,}\.[a-z0-9]+$/i;
const MIME_TYPES: Record<string, string> = {
  ".css": "text/css; charset=utf-8",
  ".gif": "image/gif",
  ".html": "text/html; charset=utf-8",
  ".ico": "image/x-icon",
  ".jpeg": "image/jpeg",
  ".jpg": "image/jpeg",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".map": "application/json; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".webp": "image/webp",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
};

function json(body: unknown, status = 200, headers?: HeadersInit): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...headers },
  });
}

function error(status: number, message: string): Response {
  return json({ error: message }, status);
}

function methodNotAllowed(allowed: string): Response {
  return json({ error: "method not allowed" }, 405, { Allow: allowed });
}

function publicMessage(message: NotificationMessage): NotificationMessage {
  return {
    id: message.id,
    timestamp: message.timestamp,
    title: message.title,
    message: message.message,
    sound: message.sound,
    group_id: message.group_id,
    open_url: message.open_url,
    method: message.method,
    dismissed_at: message.dismissed_at,
  };
}

function parseListOptions(url: URL): ListOptions | Response {
  const rawLimit = url.searchParams.get("limit");
  const limit = rawLimit === null ? 100 : Number(rawLimit);
  if (!Number.isInteger(limit) || limit < 1 || limit > 1000) {
    return error(400, "limit must be an integer between 1 and 1000");
  }

  const rawSearch = url.searchParams.get("search");
  const search = rawSearch?.trim() || undefined;
  if (search && search.length > 500) return error(400, "search must be 500 characters or fewer");

  const rawSince = url.searchParams.get("since");
  const since = rawSince?.trim() || undefined;
  if (since) {
    try {
      parseSince(since);
    } catch {
      return error(400, "since must be a relative m/h/d/w duration or ISO timestamp");
    }
  }

  return { limit, search, since };
}

async function fileResponse(path: string, request: Request): Promise<Response | null> {
  try {
    const details = await stat(path);
    if (!details.isFile()) return null;
    const headers = new Headers({
      "Content-Type": MIME_TYPES[extname(path).toLowerCase()] ?? "application/octet-stream",
      "Cache-Control": HASHED_ASSET.test(basename(path))
        ? "public, max-age=31536000, immutable"
        : "no-cache",
    });
    if (request.method === "HEAD") return new Response(null, { headers });
    return new Response(await readFile(path), { headers });
  } catch (cause) {
    if ((cause as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw cause;
  }
}

async function serveApp(request: Request, pathname: string, distDir: string): Promise<Response> {
  if (request.method !== "GET" && request.method !== "HEAD") return methodNotAllowed("GET, HEAD");

  let decoded: string;
  try {
    decoded = decodeURIComponent(pathname);
  } catch {
    return error(400, "invalid path encoding");
  }
  if (decoded.includes("\0") || decoded.split("/").includes("..")) {
    return error(400, "invalid path");
  }

  const root = resolve(distDir);
  const relative = decoded.replace(/^\/+/, "");
  const candidate = resolve(root, relative);
  if (candidate !== root && !candidate.startsWith(`${root}${sep}`)) {
    return error(400, "invalid path");
  }

  if (relative) {
    const asset = await fileResponse(candidate, request);
    if (asset) return asset;
  }
  const index = await fileResponse(resolve(root, "index.html"), request);
  return index ?? error(500, "web interface is not built");
}

export function createHandler(
  store: Store,
  options: HandlerOptions = {},
): (request: Request) => Promise<Response> {
  const distDir = options.distDir ?? DEFAULT_DIST_DIR;

  return async (request: Request): Promise<Response> => {
    try {
      const url = new URL(request.url);
      const { pathname } = url;

      if (pathname === "/health") {
        if (request.method !== "GET") return methodNotAllowed("GET");
        return json({ status: "ok" });
      }

      if (pathname === "/api/messages") {
        if (request.method !== "GET") return methodNotAllowed("GET");
        const listOptions = parseListOptions(url);
        if (listOptions instanceof Response) return listOptions;
        const messages = await store.list(listOptions);
        return json(messages.map(publicMessage));
      }

      const dismissMatch = /^\/api\/messages\/(\d+)\/dismiss$/.exec(pathname);
      if (dismissMatch) {
        if (request.method !== "POST") return methodNotAllowed("POST");
        const id = Number(dismissMatch[1]);
        if (!Number.isSafeInteger(id) || id < 1) return error(400, "invalid message id");
        return (await store.dismiss(id))
          ? json({ dismissed: id })
          : error(404, "message not found");
      }

      if (pathname.startsWith("/api/")) return error(404, "not found");
      return await serveApp(request, pathname, distDir);
    } catch (cause) {
      console.error("HTTP request failed", cause);
      return error(500, "internal server error");
    }
  };
}
