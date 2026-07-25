export interface Writable {
  write(value: string): unknown;
}

export interface CliIO {
  stdout: Writable;
  stderr: Writable;
}

export interface MessageRecord {
  id: number;
  timestamp: string;
  title: string;
  message: string;
  sound: string | null;
  group_id: string | null;
  open_url: string | null;
  execute_cmd: string | null;
  method: string;
  dismissed_at: string | null;
}

export interface MessageOutput {
  id: number;
  timestamp: string;
  title: string;
  message: string;
  sound?: string;
  group_id?: string;
  open_url?: string;
  execute?: string;
  method: string;
  dismissed_at: string | null;
}

export interface NewMessage {
  timestamp: string;
  title: string;
  message: string;
  sound: string | null;
  groupId: string | null;
  openUrl: string | null;
  execute: string | null;
  method: string;
}

export interface ListOptions {
  limit: number;
  since?: string;
  search?: string;
}

export interface SpawnedProcess {
  exited: Promise<number>;
}

export type SpawnProcess = (argv: readonly string[]) => SpawnedProcess;
export type FindExecutable = (name: string) => string | null;

export interface NotificationRequest {
  title: string;
  message: string;
  sound?: string | null;
  group?: string;
  openUrl?: string;
  execute?: string;
}

export interface NotificationResult {
  success: boolean;
  method?: string;
}

export interface PhoneConfig {
  url: string;
  token: string;
}
