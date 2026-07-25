import { readFile } from "node:fs/promises";
import { parse } from "yaml";
import { type Environment, phoneConfigPath } from "./paths.ts";
import type { PhoneConfig } from "./types.ts";

export type Fetch = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

export interface PhoneDependencies {
  env: Environment;
  home?: string;
  readText(path: string): Promise<string>;
  fetch: Fetch;
  timeoutMs: number;
}

export const defaultPhoneDependencies: PhoneDependencies = {
  env: process.env,
  readText: (path) => readFile(path, "utf8"),
  fetch: globalThis.fetch,
  timeoutMs: 10_000,
};

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

export async function loadPhoneConfig(
  dependencies: Pick<PhoneDependencies, "env" | "home" | "readText"> = defaultPhoneDependencies,
): Promise<PhoneConfig | null> {
  const envUrl = stringValue(dependencies.env.AGENTNOTIFY_PHONE_URL);
  const envToken = stringValue(dependencies.env.AGENTNOTIFY_PHONE_TOKEN);
  if (envUrl && envToken) return { url: envUrl, token: envToken };

  let fileUrl: string | undefined;
  let fileToken: string | undefined;
  try {
    const contents = await dependencies.readText(
      phoneConfigPath({ env: dependencies.env, home: dependencies.home }),
    );
    const config: unknown = parse(contents);
    if (config && typeof config === "object") {
      const values = config as Record<string, unknown>;
      fileUrl = stringValue(values.url);
      fileToken = stringValue(values.token);
    }
  } catch {
    // The phone destination is optional.
  }

  const url = envUrl ?? fileUrl;
  const token = envToken ?? fileToken;
  return url && token ? { url, token } : null;
}

export async function sendPhoneNotification(
  title: string,
  body: string,
  dependencies: PhoneDependencies = defaultPhoneDependencies,
): Promise<boolean> {
  try {
    const config = await loadPhoneConfig(dependencies);
    if (!config) return false;
    const endpoint = `${config.url.replace(/\/+$/, "")}/notify`;
    const response = await dependencies.fetch(endpoint, {
      method: "POST",
      headers: {
        authorization: `Bearer ${config.token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ title, body, channel: "normal" }),
      signal: AbortSignal.timeout(dependencies.timeoutMs),
    });
    return response.ok;
  } catch {
    return false;
  }
}
