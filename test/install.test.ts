import { afterEach, describe, expect, setDefaultTimeout, test } from "bun:test";
import {
  chmodSync,
  existsSync,
  linkSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readlinkSync,
  realpathSync,
  rmSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = realpathSync(join(import.meta.dir, ".."));
const installer = join(root, "scripts", "install.sh");
const uninstaller = join(root, "scripts", "uninstall.sh");
const source = join(root, "src", "cli.ts");
const manifest = await Bun.file(join(root, "package.json")).json();
const expectedBun = String(manifest.engines.bun);
const expectedVersion = String(manifest.version);
const expectedSha = git("-C", root, "rev-parse", "HEAD");
const previousSha = "b".repeat(40);
const temporaryRoots: string[] = [];
const destinationOverrides = [
  "AGENTNOTIFY_INSTALL_BIN_DIR",
  "AGENTNOTIFY_INSTALL_STATE_DIR",
  "AGENTNOTIFY_INSTALL_DATA_DIR",
  "AGENTNOTIFY_BUN",
  "AGENTNOTIFY_LOG_DB",
  "AGENTNOTIFY_DATA_DIR",
  "XDG_STATE_HOME",
  "XDG_DATA_HOME",
] as const;

setDefaultTimeout(15_000);

type Fixture = {
  home: string;
  env: Record<string, string>;
  binDir: string;
  dataDir: string;
  stateDir: string;
  target: string;
  receipt: string;
  bunLog: string;
};

function git(...args: string[]): string {
  const result = Bun.spawnSync(["git", ...args]);
  if (result.exitCode !== 0) throw new Error(result.stderr.toString());
  return result.stdout.toString().trim();
}

function temp(prefix: string): string {
  const path = mkdtempSync(join(tmpdir(), prefix));
  temporaryRoots.push(path);
  return path;
}

function writeExecutable(path: string, contents: string): void {
  writeFileSync(path, contents);
  chmodSync(path, 0o755);
}

function fixture(): Fixture {
  const home = temp("agentnotify-install-home-");
  const tools = join(home, "tools");
  const bunLog = join(home, "bun.log");
  mkdirSync(tools);
  writeExecutable(
    join(tools, "bun"),
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >>"$AGENTNOTIFY_FAKE_BUN_LOG"
case "\${1:-}" in
  --version)
    printf '%s\\n' ${JSON.stringify(expectedBun)}
    ;;
  -e)
    if [[ "\${2:-}" == *packageManager* ]]; then
      printf '%s' ${JSON.stringify(expectedBun)}
    else
      printf '%s' ${JSON.stringify(expectedVersion)}
    fi
    ;;
  install)
    [[ "\${2:-}" == --frozen-lockfile ]]
    if [[ "\${AGENTNOTIFY_FAKE_FAIL:-}" == install ]]; then exit 71; fi
    ;;
  run)
    [[ "\${2:-}" == check ]]
    if [[ "\${AGENTNOTIFY_FAKE_FAIL:-}" == check ]]; then exit 72; fi
    ;;
  */.local/bin/agentnotify)
    [[ "\${2:-}" == --version ]]
    if [[ "\${AGENTNOTIFY_FAKE_FAIL:-}" == readiness ]]; then exit 73; fi
    printf '%s\\n' ${JSON.stringify(expectedVersion)}
    ;;
  *)
    printf 'unexpected fake Bun argv: %s\\n' "$*" >&2
    exit 90
    ;;
esac
`,
  );

  const env: Record<string, string> = {};
  for (const [key, value] of Object.entries(process.env)) {
    if (value !== undefined && !destinationOverrides.includes(key as never)) {
      env[key] = value;
    }
  }
  env.HOME = home;
  env.PATH = `${tools}:${process.env.PATH ?? "/usr/bin:/bin"}`;
  env.AGENTNOTIFY_FAKE_BUN_LOG = bunLog;

  const binDir = join(home, ".local", "bin");
  const dataDir = join(home, ".local", "share", "agentnotify");
  const stateDir = join(home, ".local", "state", "agentnotify");
  return {
    home,
    env,
    binDir,
    dataDir,
    stateDir,
    target: join(binDir, "agentnotify"),
    receipt: join(stateDir, "deployed-sha"),
    bunLog,
  };
}

async function runScript(
  script: string,
  value: Fixture,
  options: { args?: string[]; env?: Record<string, string> } = {},
): Promise<{ exitCode: number; stdout: string; stderr: string }> {
  const proc = Bun.spawn(["bash", script, ...(options.args ?? [])], {
    cwd: "/",
    env: { ...value.env, ...(options.env ?? {}) },
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { exitCode, stdout, stderr };
}

function run(value: Fixture, options: { args?: string[]; env?: Record<string, string> } = {}) {
  return runScript(installer, value, options);
}

function prepareInstallPaths(value: Fixture): void {
  mkdirSync(value.binDir, { recursive: true });
  mkdirSync(value.stateDir, { recursive: true });
  chmodSync(value.stateDir, 0o700);
}

function writeReceipt(value: Fixture, sha = expectedSha): void {
  mkdirSync(value.stateDir, { recursive: true });
  chmodSync(value.stateDir, 0o700);
  writeFileSync(value.receipt, `${sha}\n`);
  chmodSync(value.receipt, 0o600);
}

function previousCheckout(origin = "https://github.com/possibilities/agentnotify.git"): {
  root: string;
  cli: string;
  sha: string;
} {
  const checkout = temp("agentnotify-previous-");
  const src = join(checkout, "src");
  mkdirSync(src);
  const cli = join(src, "cli.ts");
  writeExecutable(cli, "#!/usr/bin/env bun\n");
  git("-C", checkout, "init", "-q");
  git("-C", checkout, "config", "user.name", "Agentnotify Test");
  git("-C", checkout, "config", "user.email", "agentnotify@example.invalid");
  git("-C", checkout, "remote", "add", "origin", origin);
  git("-C", checkout, "add", "src/cli.ts");
  git("-C", checkout, "commit", "-qm", "previous checkout");
  return { root: checkout, cli, sha: git("-C", checkout, "rev-parse", "HEAD") };
}

afterEach(() => {
  for (const path of temporaryRoots.splice(0)) {
    rmSync(path, { recursive: true, force: true });
  }
});

describe("shared installer contract", () => {
  test("shell syntax parses and arguments are rejected", async () => {
    expect(Bun.spawnSync(["bash", "-n", installer]).exitCode).toBe(0);
    const value = fixture();
    const result = await run(value, { args: ["--install"] });
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Usage: scripts/install.sh");
    expect(existsSync(value.target)).toBe(false);
  });

  test("zero arguments installs the exact source link and private receipt", async () => {
    const value = fixture();
    const result = await run(value);

    expect(result.exitCode).toBe(0);
    expect(lstatSync(value.target).isSymbolicLink()).toBe(true);
    expect(readlinkSync(value.target)).toBe(source);
    expect(readFileSync(value.receipt, "utf8")).toBe(`${expectedSha}\n`);
    expect(lstatSync(value.receipt).mode & 0o777).toBe(0o600);
    expect(lstatSync(value.stateDir).mode & 0o777).toBe(0o700);
    expect(lstatSync(value.dataDir).mode & 0o777).toBe(0o700);
    expect(readFileSync(value.bunLog, "utf8")).toContain("install --frozen-lockfile");
    expect(readFileSync(value.bunLog, "utf8")).toContain("run check");
    expect(readFileSync(value.bunLog, "utf8")).toContain(`${value.target} --version`);
  });

  test("same-SHA installs atomically replace the receipt inode", async () => {
    const value = fixture();
    expect((await run(value)).exitCode).toBe(0);
    const firstIdentity = `${lstatSync(value.receipt).dev}:${lstatSync(value.receipt).ino}`;

    expect((await run(value)).exitCode).toBe(0);
    const secondIdentity = `${lstatSync(value.receipt).dev}:${lstatSync(value.receipt).ino}`;
    expect(secondIdentity).not.toBe(firstIdentity);
    expect(readFileSync(value.receipt, "utf8")).toBe(`${expectedSha}\n`);
  });

  test("repairs first-install interruption after command publication", async () => {
    const value = fixture();
    prepareInstallPaths(value);
    symlinkSync(source, value.target);

    const result = await run(value);

    expect(result.exitCode).toBe(0);
    expect(readlinkSync(value.target)).toBe(source);
    expect(readFileSync(value.receipt, "utf8")).toBe(`${expectedSha}\n`);
  });

  test("repairs interrupted same-command publication with an old valid receipt", async () => {
    const value = fixture();
    prepareInstallPaths(value);
    symlinkSync(source, value.target);
    writeReceipt(value, previousSha);
    const oldIdentity = lstatSync(value.receipt).ino;

    const result = await run(value);

    expect(result.exitCode).toBe(0);
    expect(lstatSync(value.receipt).ino).not.toBe(oldIdentity);
    expect(readFileSync(value.receipt, "utf8")).toBe(`${expectedSha}\n`);
  });

  test("migrates an exact previous checkout with matching receipt", async () => {
    const value = fixture();
    const previous = previousCheckout("git@github.com:possibilities/agentnotify.git");
    prepareInstallPaths(value);
    symlinkSync(previous.cli, value.target);
    writeReceipt(value, previous.sha);

    const result = await run(value);

    expect(result.exitCode).toBe(0);
    expect(readlinkSync(value.target)).toBe(source);
    expect(readFileSync(value.receipt, "utf8")).toBe(`${expectedSha}\n`);
  });

  test("refuses a mismatched receipt without changing the previous command", async () => {
    const value = fixture();
    const previous = previousCheckout();
    prepareInstallPaths(value);
    symlinkSync(previous.cli, value.target);
    writeReceipt(value, expectedSha);

    const result = await run(value);

    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain("does not match the managed command");
    expect(readlinkSync(value.target)).toBe(previous.cli);
    expect(readFileSync(value.receipt, "utf8")).toBe(`${expectedSha}\n`);
  });

  test("refuses inherited destination overrides", async () => {
    for (const variable of destinationOverrides) {
      const value = fixture();
      const result = await run(value, {
        env: { [variable]: join(value.home, "redirected") },
      });
      expect(result.exitCode).toBe(1);
      expect(result.stderr).toContain(`refusing inherited destination override: ${variable}`);
      expect(existsSync(value.target)).toBe(false);
    }
  });

  test("refuses symlinked destination ancestors without touching their targets", async () => {
    for (const destination of ["local", "bin", "data", "state"] as const) {
      const value = fixture();
      const foreign = temp(`agentnotify-${destination}-foreign-`);
      const sentinel = join(foreign, "sentinel");
      writeFileSync(sentinel, "preserve\n");

      if (destination === "local") {
        symlinkSync(foreign, join(value.home, ".local"));
      } else if (destination === "bin") {
        mkdirSync(join(value.home, ".local"));
        symlinkSync(foreign, value.binDir);
      } else if (destination === "data") {
        mkdirSync(join(value.home, ".local", "share"), { recursive: true });
        symlinkSync(foreign, value.dataDir);
      } else {
        mkdirSync(join(value.home, ".local"));
        symlinkSync(foreign, join(value.home, ".local", "state"));
      }

      const result = await run(value);
      expect(result.exitCode).toBe(1);
      expect(result.stderr).toContain("refusing symlinked");
      expect(readFileSync(sentinel, "utf8")).toBe("preserve\n");
    }
  });

  test("refuses foreign commands, origins, and uncorroborated state", async () => {
    const regular = fixture();
    prepareInstallPaths(regular);
    writeFileSync(regular.target, "foreign\n");
    expect((await run(regular)).stderr).toContain("refusing foreign command path");

    const link = fixture();
    prepareInstallPaths(link);
    symlinkSync("/tmp/not-agentnotify", link.target);
    expect((await run(link)).stderr).toContain("refusing foreign command symlink");

    const origin = fixture();
    const foreignCheckout = previousCheckout("https://example.com/agentnotify.git");
    prepareInstallPaths(origin);
    symlinkSync(foreignCheckout.cli, origin.target);
    expect((await run(origin)).stderr).toContain("foreign origin");

    const state = fixture();
    writeReceipt(state);
    const stateResult = await run(state);
    expect(stateResult.exitCode).toBe(1);
    expect(stateResult.stderr).toContain("uncorroborated deployed receipt");
    expect(readFileSync(state.receipt, "utf8")).toBe(`${expectedSha}\n`);
  });

  test("refuses malformed, permissive, symlinked, and hardlinked receipts", async () => {
    const malformed = fixture();
    prepareInstallPaths(malformed);
    symlinkSync(source, malformed.target);
    writeFileSync(malformed.receipt, "not-a-sha\n");
    chmodSync(malformed.receipt, 0o600);
    expect((await run(malformed)).stderr).toContain("malformed deployed receipt");

    const permissive = fixture();
    prepareInstallPaths(permissive);
    symlinkSync(source, permissive.target);
    writeReceipt(permissive);
    chmodSync(permissive.receipt, 0o644);
    expect((await run(permissive)).stderr).toContain("unsafe permissions");

    const linked = fixture();
    prepareInstallPaths(linked);
    symlinkSync(source, linked.target);
    const elsewhere = join(linked.home, "elsewhere");
    writeFileSync(elsewhere, `${expectedSha}\n`);
    symlinkSync(elsewhere, linked.receipt);
    expect((await run(linked)).stderr).toContain("unsafe deployed receipt");

    const hardlinked = fixture();
    prepareInstallPaths(hardlinked);
    symlinkSync(source, hardlinked.target);
    writeReceipt(hardlinked);
    linkSync(hardlinked.receipt, join(hardlinked.home, "receipt-hardlink"));
    expect((await run(hardlinked)).stderr).toContain("hardlinked deployed receipt");
  });

  test("refuses hardlinked source evidence", async () => {
    const value = fixture();
    const previous = previousCheckout();
    prepareInstallPaths(value);
    linkSync(previous.cli, join(previous.root, "source-hardlink"));
    symlinkSync(previous.cli, value.target);

    const result = await run(value);

    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain("hardlinked agentnotify source command");
  });

  test("failed checks preserve the previous command and receipt", async () => {
    for (const failure of ["install", "check", "readiness"] as const) {
      const value = fixture();
      const previous = previousCheckout();
      prepareInstallPaths(value);
      symlinkSync(previous.cli, value.target);
      writeReceipt(value, previous.sha);
      const receiptIdentity = lstatSync(value.receipt).ino;

      const result = await run(value, { env: { AGENTNOTIFY_FAKE_FAIL: failure } });

      expect(result.exitCode).not.toBe(0);
      if (failure === "readiness") {
        expect(readlinkSync(value.target)).toBe(source);
      } else {
        expect(readlinkSync(value.target)).toBe(previous.cli);
      }
      expect(lstatSync(value.receipt).ino).toBe(receiptIdentity);
      expect(readFileSync(value.receipt, "utf8")).toBe(`${previous.sha}\n`);

      if (failure === "readiness") {
        const recovered = await run(value);
        expect(recovered.exitCode).toBe(0);
        expect(lstatSync(value.receipt).ino).not.toBe(receiptIdentity);
        expect(readFileSync(value.receipt, "utf8")).toBe(`${expectedSha}\n`);
      }
    }
  });

  test("preserves unrelated data and state", async () => {
    const value = fixture();
    mkdirSync(value.dataDir, { recursive: true });
    mkdirSync(value.stateDir, { recursive: true });
    chmodSync(value.dataDir, 0o700);
    chmodSync(value.stateDir, 0o700);
    const data = join(value.dataDir, "history.db");
    const state = join(value.stateDir, "keep-me");
    writeFileSync(data, "history\n");
    writeFileSync(state, "state\n");

    expect((await run(value)).exitCode).toBe(0);
    expect(readFileSync(data, "utf8")).toBe("history\n");
    expect(readFileSync(state, "utf8")).toBe("state\n");

    unlinkSync(value.target);
    expect(readFileSync(data, "utf8")).toBe("history\n");
  });

  test("uninstall removes only this checkout's command and receipt", async () => {
    const value = fixture();
    expect((await run(value)).exitCode).toBe(0);
    const data = join(value.dataDir, "history.db");
    const unrelatedState = join(value.stateDir, "keep-me");
    writeFileSync(data, "history\n");
    writeFileSync(unrelatedState, "state\n");

    const result = await runScript(uninstaller, value);

    expect(result.exitCode).toBe(0);
    expect(existsSync(value.target)).toBe(false);
    expect(existsSync(value.receipt)).toBe(false);
    expect(readFileSync(data, "utf8")).toBe("history\n");
    expect(readFileSync(unrelatedState, "utf8")).toBe("state\n");
  });
});
