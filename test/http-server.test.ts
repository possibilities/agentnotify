import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHandler, type ListOptions, type Store } from "../src/http";
import { type ServeOptions, serverConfig, startServers } from "../src/server";

let distDir = "";
const calls: ListOptions[] = [];
const store: Store = {
  list(options) {
    calls.push(options);
    return [
      {
        id: 7,
        timestamp: "2026-01-02T03:04:05.000Z",
        title: "Build complete",
        message: "Ready",
        sound: null,
        group_id: "build",
        open_url: null,
        method: "terminal-notifier",
        dismissed_at: null,
        execute_cmd: "rm -rf /",
      },
    ];
  },
  dismiss(id) {
    return id === 7;
  },
};

beforeAll(async () => {
  distDir = await mkdtemp(join(tmpdir(), "agentnotify-http-"));
  await writeFile(join(distDir, "index.html"), "<main>app shell</main>");
  await writeFile(join(distDir, "app.12345678.js"), "console.log('asset')");
  await writeFile(join(distDir, "plain.css"), "body{}");
});

afterAll(async () => {
  await rm(distDir, { recursive: true, force: true });
});

describe("HTTP handler", () => {
  const request = (path: string, method = "GET") =>
    createHandler(store, { distDir })(new Request(`http://localhost${path}`, { method }));

  test("reports health and restricts its method", async () => {
    expect(await (await request("/health")).json()).toEqual({ status: "ok" });
    const response = await request("/health", "POST");
    expect(response.status).toBe(405);
    expect(response.headers.get("Allow")).toBe("GET");
  });

  test("lists messages with validated query options", async () => {
    const response = await request("/api/messages?limit=25&search=%20build%20&since=2026-01-01");
    expect(response.status).toBe(200);
    const body = (await response.json()) as Record<string, unknown>[];
    expect(body[0]?.id).toBe(7);
    expect(body[0]).not.toHaveProperty("execute_cmd");
    expect(calls.at(-1)).toEqual({ limit: 25, search: "build", since: "2026-01-01" });

    for (const value of ["0", "1.5", "nope", "1001"]) {
      expect((await request(`/api/messages?limit=${value}`)).status).toBe(400);
    }
    expect((await request("/api/messages?since=not-a-date")).status).toBe(400);
    expect((await request("/api/messages", "POST")).status).toBe(405);
  });

  test("dismisses existing messages and returns not found", async () => {
    expect(await (await request("/api/messages/7/dismiss", "POST")).json()).toEqual({
      dismissed: 7,
    });
    expect((await request("/api/messages/8/dismiss", "POST")).status).toBe(404);
    expect((await request("/api/messages/7/dismiss")).status).toBe(405);
    expect((await request("/api/missing")).status).toBe(404);
  });

  test("returns a JSON 500 instead of hiding store failures", async () => {
    const failing = createHandler({
      list() {
        throw new Error("database unavailable");
      },
      dismiss() {
        throw new Error("database unavailable");
      },
    });
    const response = await failing(new Request("http://localhost/api/messages"));
    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({ error: "internal server error" });
  });

  test("serves assets safely with caching and SPA fallback", async () => {
    const immutable = await request("/app.12345678.js");
    expect(immutable.status).toBe(200);
    expect(immutable.headers.get("Content-Type")).toContain("javascript");
    expect(immutable.headers.get("Cache-Control")).toContain("immutable");

    const plain = await request("/plain.css");
    expect(plain.headers.get("Cache-Control")).toBe("no-cache");
    expect(await (await request("/settings/history")).text()).toContain("app shell");
    expect((await request("/%2e%2e%2fsecret")).status).toBe(400);
    expect((await request("/", "POST")).status).toBe(405);
  });
});

describe("server startup", () => {
  test("defaults to loopback and supports explicit host listeners", () => {
    expect(serverConfig({})).toEqual({ hosts: ["127.0.0.1"], port: 7700 });
    expect(
      serverConfig({ AGENTNOTIFY_HOSTS: "127.0.0.1, ::1,127.0.0.1", AGENTNOTIFY_PORT: "8800" }),
    ).toEqual({
      hosts: ["127.0.0.1", "::1"],
      port: 8800,
    });

    const options: ServeOptions[] = [];
    const listeners = startServers(
      store,
      { AGENTNOTIFY_HOSTS: "127.0.0.1,::1", AGENTNOTIFY_PORT: "8800" },
      (value) => {
        options.push(value);
        return { hostname: value.hostname, port: value.port, stop() {} };
      },
    );
    expect(listeners).toHaveLength(2);
    expect(options.map(({ hostname }) => hostname)).toEqual(["127.0.0.1", "::1"]);
    expect(options[0]?.fetch).toBe(options[1]?.fetch);
  });

  test("rejects invalid ports", () => {
    expect(() => serverConfig({ AGENTNOTIFY_PORT: "0" })).toThrow();
    expect(() => serverConfig({ AGENTNOTIFY_PORT: "abc" })).toThrow();
  });
});
