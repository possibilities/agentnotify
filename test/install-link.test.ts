import { afterEach, describe, expect, test } from "bun:test";
import {
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readlinkSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const roots: string[] = [];
const repository = resolve(import.meta.dir, "..");
const installer = join(repository, "scripts", "install-local-link.sh");
const cli = join(repository, "src", "cli.ts");

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

function run(home: string) {
  return Bun.spawnSync(["bash", installer, cli], {
    env: { ...process.env, HOME: home },
    stdout: "pipe",
    stderr: "pipe",
  });
}

describe("local CLI installation", () => {
  test("atomically links the source and creates private data directories", () => {
    const home = mkdtempSync(join(tmpdir(), "agentnotify-install-"));
    roots.push(home);

    expect(run(home).exitCode).toBe(0);
    expect(run(home).exitCode).toBe(0);

    const link = join(home, ".local", "bin", "agentnotify");
    expect(lstatSync(link).isSymbolicLink()).toBe(true);
    expect(readlinkSync(link)).toBe(cli);
    expect(lstatSync(join(home, ".local", "share", "agentnotify")).mode & 0o777).toBe(0o700);
    expect(lstatSync(join(home, ".local", "state", "agentnotify")).mode & 0o777).toBe(0o700);
  });

  test("does not replace a non-symlink executable", () => {
    const home = mkdtempSync(join(tmpdir(), "agentnotify-install-"));
    roots.push(home);
    const bin = join(home, ".local", "bin");
    mkdirSync(bin, { recursive: true });
    const link = join(bin, "agentnotify");
    writeFileSync(link, "foreign\n");

    const result = run(home);
    expect(result.exitCode).toBe(1);
    expect(readFileSync(link, "utf8")).toBe("foreign\n");
  });

  test("refuses symlinked state directories", () => {
    const home = mkdtempSync(join(tmpdir(), "agentnotify-install-"));
    roots.push(home);
    const target = join(home, "foreign-state");
    mkdirSync(target, { recursive: true, mode: 0o755 });
    const initialMode = lstatSync(target).mode & 0o777;
    const stateParent = join(home, ".local", "state");
    mkdirSync(stateParent, { recursive: true });
    symlinkSync(target, join(stateParent, "agentnotify"));

    const result = run(home);
    expect(result.exitCode).toBe(1);
    expect(lstatSync(target).mode & 0o777).toBe(initialMode);
  });
});
