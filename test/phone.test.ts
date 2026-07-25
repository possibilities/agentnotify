import { describe, expect, test } from "bun:test";
import {
  type Fetch,
  loadPhoneConfig,
  type PhoneDependencies,
  sendPhoneNotification,
} from "../src/phone.ts";

function dependencies(overrides: Partial<PhoneDependencies> = {}): PhoneDependencies {
  return {
    env: {},
    home: "/home/test",
    readText: async () => {
      throw new Error("missing");
    },
    fetch: async () => new Response(null, { status: 204 }),
    timeoutMs: 10_000,
    ...overrides,
  };
}

describe("phone delivery", () => {
  test("prefers complete environment configuration without reading YAML", async () => {
    let reads = 0;
    const result = await loadPhoneConfig(
      dependencies({
        env: {
          AGENTNOTIFY_PHONE_URL: "https://phone.example/env",
          AGENTNOTIFY_PHONE_TOKEN: "env-token",
        },
        readText: async () => {
          reads += 1;
          return "url: https://phone.example/file\ntoken: file-token\n";
        },
      }),
    );
    expect(result).toEqual({ url: "https://phone.example/env", token: "env-token" });
    expect(reads).toBe(0);
  });

  test("fills missing environment fields from optional YAML", async () => {
    expect(
      await loadPhoneConfig(
        dependencies({
          env: { AGENTNOTIFY_PHONE_TOKEN: "env-token" },
          readText: async (path) => {
            expect(path).toBe("/home/test/.config/agentnotify/config.yaml");
            return "url: https://phone.example/file\ntoken: file-token\n";
          },
        }),
      ),
    ).toEqual({ url: "https://phone.example/file", token: "env-token" });
  });

  test("posts the compact authenticated payload", async () => {
    const calls: Array<{ input: string; init?: RequestInit }> = [];
    const result = await sendPhoneNotification(
      "Build done",
      "Everything passed",
      dependencies({
        env: {
          AGENTNOTIFY_PHONE_URL: "https://phone.example/send",
          AGENTNOTIFY_PHONE_TOKEN: "secret",
        },
        fetch: async (input: string | URL | Request, init?: RequestInit) => {
          calls.push({ input: String(input), init });
          return new Response(null, { status: 204 });
        },
      }),
    );
    expect(result).toBe(true);
    expect(calls[0]?.input).toBe("https://phone.example/send/notify");
    expect(calls[0]?.init?.method).toBe("POST");
    expect(calls[0]?.init?.headers).toEqual({
      authorization: "Bearer secret",
      "content-type": "application/json",
    });
    expect(calls[0]?.init?.body).toBe(
      JSON.stringify({ title: "Build done", body: "Everything passed", channel: "normal" }),
    );
  });

  test("times out and treats fetch and HTTP errors as best effort failures", async () => {
    const base = {
      env: {
        AGENTNOTIFY_PHONE_URL: "https://phone.example/send",
        AGENTNOTIFY_PHONE_TOKEN: "secret",
      },
    };
    const timedOut = await sendPhoneNotification(
      "title",
      "body",
      dependencies({
        ...base,
        timeoutMs: 5,
        fetch: ((_: string | URL | Request, init?: RequestInit) =>
          new Promise<Response>((_, reject) => {
            init?.signal?.addEventListener("abort", () => reject(new Error("aborted")), {
              once: true,
            });
          })) satisfies Fetch,
      }),
    );
    expect(timedOut).toBe(false);

    expect(
      await sendPhoneNotification(
        "title",
        "body",
        dependencies({
          ...base,
          fetch: async () => new Response(null, { status: 500 }),
        }),
      ),
    ).toBe(false);
    expect(
      await sendPhoneNotification(
        "title",
        "body",
        dependencies({
          ...base,
          fetch: async () => {
            throw new Error("offline");
          },
        }),
      ),
    ).toBe(false);
  });
});
