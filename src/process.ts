import { fileURLToPath } from "node:url";
import type { FindExecutable, SpawnProcess } from "./types.ts";

export const spawnProcess: SpawnProcess = (argv) => {
  const child = Bun.spawn({
    cmd: [...argv],
    stdin: "ignore",
    stdout: "ignore",
    stderr: "ignore",
  });
  return { exited: child.exited };
};

export const findExecutable: FindExecutable = (name) => Bun.which(name);

export function localNotifierArgv(): readonly string[] {
  const script = fileURLToPath(import.meta.resolve("node-notifier-cli/bin.js"));
  return [process.execPath, script];
}

export async function runProcess(argv: readonly string[], spawn: SpawnProcess): Promise<boolean> {
  try {
    const process = spawn(argv);
    return (await process.exited) === 0;
  } catch {
    return false;
  }
}
