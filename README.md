# agentnotify

`agentnotify` is a local CLI for sending desktop and optional phone notifications, browsing persisted history, dismissing records, and closing grouped desktop notifications.

## Install

The zero-argument installer requires the exact Bun version pinned in `package.json`. It installs the frozen dependency graph, runs the complete repository check, and atomically links `~/.local/bin/agentnotify` to `src/cli.ts` in the exact Git checkout being deployed. Its final completion operation atomically publishes that checkout’s 40-character Git SHA to `~/.local/state/agentnotify/deployed-sha` with mode `0600`; every successful run replaces the receipt inode, including same-SHA reinstalls.

```sh
git clone https://github.com/possibilities/agentnotify.git
cd agentnotify
bash scripts/install.sh
```

Add `~/.local/bin` to `PATH` if it is not already present. The installer is safe to rerun from any working directory and can forward-repair an interruption after command publication but before receipt publication. It rejects foreign command or receipt state, hardlinked evidence, symlinked destination ancestors, unsafe directory permissions, foreign Git origins, and inherited destination overrides rather than adopting them. History and unrelated state are preserved.

## Commands and JSON contract

Every successful command writes one JSON value to stdout, except help and version output. Diagnostics go to stderr. Usage errors exit 2; delivery, storage, and other runtime failures exit 1.

### Send

```sh
agentnotify show-message \
  --title "Build complete" \
  --message "The release artifact is ready" \
  --sound Ping \
  --group release-42 \
  --open-url https://example.test/releases/42
```

Optional flags are `--sound`, `--group`, `--open-url`, `--execute`, and `--no-phone`. Sound defaults to `Ping`. A successful desktop delivery is persisted before optional phone delivery is attempted.

```json
{"success":true,"method":"terminal-notifier"}
```

`method` identifies the desktop delivery method selected on the current host. Phone delivery is best effort and does not change this response. `--no-phone` skips it.

### List

```sh
agentnotify list-messages --limit 20 --since 2h --search release
```

`--since` accepts an ISO timestamp or a whole-number duration ending in `m`, `h`, `d`, or `w`. Results are newest first. The response is a JSON array:

```json
[
  {
    "id": 12,
    "timestamp": "2026-03-13 10:30:00 PDT",
    "title": "Build complete",
    "message": "The release artifact is ready",
    "sound": "Ping",
    "group_id": "release-42",
    "open_url": "https://example.test/releases/42",
    "method": "terminal-notifier",
    "dismissed_at": null
  }
]
```

`sound`, `group_id`, `open_url`, and `execute` are omitted when absent. `dismissed_at` is `null` until dismissal, then an ISO timestamp. Records imported from a schema without dismissal state are classified as dismissed at their recorded timestamp.

### Dismiss

```sh
agentnotify dismiss-message 12
```

```json
{"dismissed":12}
```

Dismissal marks the history record and is idempotent for an existing ID. It does not close a desktop notification.

### Close

```sh
agentnotify close-message --group release-42
```

```json
{"closed":"release-42"}
```

Close asks the desktop delivery method to remove that group. It does not dismiss the history record. Unsupported hosts or a missing macOS notifier make close a successful no-op; a notifier execution failure exits 1.

Use `agentnotify --help`, `agentnotify <command> --help`, and `agentnotify --version` for concise command reference.

## Data, environment, and configuration

Notification history defaults to:

```text
~/.local/share/agentnotify/log.db
```

The installer creates `~/.local/share/agentnotify` and `~/.local/state/agentnotify` with mode `0700`. It creates the exact-checkout CLI symlink and the private atomic deployment receipt; it does not mutate the source executable.

Environment variables:

| Variable | Meaning |
| --- | --- |
| `AGENTNOTIFY_LOG_DB` | Exact SQLite history path. |
| `AGENTNOTIFY_DATA_DIR` | Data directory used when the exact database path is unset. |
| `XDG_DATA_HOME` | Base data directory used when neither override above is set. |
| `AGENTNOTIFY_PHONE_URL` | Phone relay base URL. |
| `AGENTNOTIFY_PHONE_TOKEN` | Phone relay bearer token. |

Phone configuration defaults to `~/.config/agentnotify/config.yaml`. Copy the placeholder file and restrict it to the current user:

```sh
install -d -m 700 ~/.config/agentnotify
install -m 600 config.example.yaml ~/.config/agentnotify/config.yaml
```

Environment values take precedence over matching file values.

### Phone URL and token

The configured URL is the relay base URL, not the notification endpoint. The client removes trailing slashes and posts to `<base-url>/notify` with:

```http
Authorization: Bearer <token>
Content-Type: application/json
```

```json
{"title":"Build complete","body":"The release artifact is ready","channel":"normal"}
```

Phone delivery is optional and best effort. Keep tokens out of the repository and command history.

## Development and checks

Use Bun 1.3.14:

```sh
bun install --frozen-lockfile
bun run lint
bun run typecheck
bun test
bun run check
```

`bun run check` runs lint, typechecking, and the complete test suite. Notification-delivery tests use injected process and network seams; they do not send real notifications.

## Uninstall

```sh
bash scripts/uninstall.sh
```

Uninstall removes only the `~/.local/bin/agentnotify` symlink owned by the current checkout and its matching deployment receipt. It preserves history, unrelated state, and phone configuration. Any other entry at the executable path is left untouched.
