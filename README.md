# AgentNotify

A native macOS menu bar inbox. Notifications are durable tasks: read them, act on them, complete them, or come back later. System light and dark appearance, a monochrome interface, and one panel that can detach from the menu bar.

Requires macOS 14+ and Swift 6 Command Line Tools. No web runtime, package downloads, or database service.

```sh
scripts/build.sh
open dist/AgentNotify.app
```

Click the tray in the menu bar. Its count shows unfinished notifications, including those already read. AgentNotify's own compact preview beneath the tray is the sole arrival presentation: the app never posts macOS notification banners, sounds, or Notification Center entries. The preview shows the latest arrival, stays until dismissed, opened, or completed, and summarizes unread notifications plus any read items that still need attention. Clicking opens and reads the displayed notification in the full inbox; its Complete control durably moves that item to Done, then advances to the next item in the current arrival burst or dismisses the preview when none remain. Dismissing alone never completes the task. More → Preferences lets you choose Queue Peek (default), Compact Toast, or Queue Shelf. Settings persist across restarts.

The first inbox opening offers to install a terminal-notifier shim through AgentStart. Choose Not now to skip it; More → Preferences → Terminal integration keeps an Install shim button for later. An existing fleet shim is recognized automatically. The original notifier stays available as a fallback.

## Terminal-notifier replacement

```sh
agentnotify -title 'Build finished' -message 'Ready for review' -group 'build:exact-task'
agentnotify -message 'Open the report' -open 'file:///absolute/path/report.html'
agentnotify -message 'Deploy?' -action Ship -action Hold -timeout 300
agentnotify -message 'What should change?' -reply 'Your answer' -timeout 300
agentnotify -message 'Check the build' -in 20m -group 'reminder:build'
agentnotify -list ALL
agentnotify -remove 'reminder:build'
```

Legacy noninteractive sends are silent on stdout. Actions and replies wait and print the exact answer. A timeout prints `@TIMEOUT` and exits 6; handle that explicitly under `set -e`. See the [compatibility contract](docs/compatibility.md) for supported flags and intentional differences.

## CLI, socket, and MCP

Each operation has the same parameters and validation:

```sh
agentnotify send --title 'Review ready' --message 'Inspect the patch' --group 'review:task-123' --requestId 'client-unique-123'
agentnotify list --filter unread
agentnotify list --group 'review:task-123' --query patch
agentnotify status --id NOTIFICATION_ID --state read --expectedRevision 2
agentnotify status --id NOTIFICATION_ID --state snooze --in 1h
agentnotify statusBatch --items '[{"id":"NOTIFICATION_ID","expectedRevision":2}]' --state read
agentnotify completeAll --requestId 'complete-inbox-unique-123'
agentnotify respond --id NOTIFICATION_ID --kind action --actionIndex 0
agentnotify changes --after 0 --limit 100
agentnotify uiShow --surface inbox --pinned true
agentnotify uiSetView --filter unread --query build
agentnotify uiNavigate --direction next
agentnotify uiState
agentnotify guide --json
agentnotify mcp
```

Modern commands emit JSON envelopes. `api METHOD JSON` accepts a raw parameter object. MCP `send` returns a durable ID immediately, including when actions are present. `get` returns the typed response later. The legacy waiting CLI maintains a five-second connection lease; a killed caller’s stale controls are disabled while the item remains in the inbox.

The private Unix socket uses newline-delimited JSON:

```json
{"id":"client-request","method":"list","params":{"filter":"inbox"}}
```

Responses echo `id` and carry `{schema_version, ok, data, error}`. Durable notification operations work headlessly; semantic `ui*` operations control the local native inbox for voice-driven search, filtering, selection, navigation, pinning, and presentation. UI selection never marks a notification read. See [the API contract](docs/api.md) and [ADR 0002](docs/adr/0002-semantic-interface-control.md). AgentStart’s shared MCP inventory exposes the same operations to AgentVoice, Codex, and Claude, plus its authenticated fleet and Grok HTTP toolsets; the shipped `notifications` skill teaches usage.

## Durable behavior

Reading is independent of completion. Opening details does not run callbacks. More → Complete All moves every active Inbox notification to Done after confirmation; its global key combination defaults to `⌥⇧⌘D` and can be changed or cleared in Preferences. The recorder requires at least two modifier keys, and the shortcut opens the same count-aware confirmation from any app. The matching `completeAll` CLI/MCP operation is atomic, leaves scheduled and snoozed notifications alone, closes unanswered prompts, and never runs body callbacks. Reopening cannot undo an answer already sent or an external command already executed. Reusing a group supersedes its earlier active notification. Removal and replacement preserve history.

SQLite WAL stores notifications, responses, revisions, idempotency keys, and an ordered change feed. Multiple local clients share one app-owned service. Future mobile clients can use these revisions and cursors; remote transport, authentication, account identity, and mobile apps are not implemented.

Body actions run in order: activate, execute, open. Commands use `/bin/sh -c` with the app’s environment and home working directory. Execution is claimed before running and never automatically replayed after an uncertain crash. A failed or interrupted effect keeps the task open with its outcome visible.

## Install and verify

```sh
scripts/install.sh --check
scripts/install.sh --install
# Optional PATH-level legacy name; never overwrites a foreign binary:
scripts/install.sh --install --terminal-notifier
```

The installer requires a clean checkout and refuses foreign destinations. An identical signed release is left running unchanged; replacing an older running release requires quitting it first. The installer never launches or restarts the app. It installs to `~/Applications/AgentNotify.app` and `~/.local/bin/agentnotify`. Ensure `~/.local/bin` precedes Homebrew for the optional legacy alias. Ruby callers can set `TERMINAL_NOTIFIER_BIN` before loading the gem. Hardcoded/vendored paths require changes at their owning source.

Existing MCP clients launched through the installed entrypoints remain running during atomic app replacement. They keep their loaded CLI contract until their session ends; subsequent processes use the new release. The app, headless service, and interactive CLI waiters must exit before replacement.

```sh
swift run NotifyCoreChecks
swift build --product agentnotify
python3 scripts/test-integration.py
python3 scripts/test-interface.py
# Requires a clean committed checkout; all install destinations are temporary:
python3 scripts/test-install.py
scripts/build.sh
# Debug-only native view renders, without changing system appearance:
.build/debug/agentnotify render-previews /tmp/agentnotify-renders
```

Core checks use plain Swift so a full Xcode installation is unnecessary. Integration tests own a temporary store and service; they never touch the live inbox. The build ad-hoc signs by default. Set `AGENTNOTIFY_SIGNING_IDENTITY` for an available signing identity. Notarization and distributed releases are separate from local packaging.

State lives at `$XDG_STATE_HOME/agentnotify` or `~/.local/state/agentnotify`, with a mode-0700 directory and mode-0600 socket/database. `AGENTNOTIFY_STATE_DIR` selects an isolated store and disables automatic app launch; run `agentnotify serve` for headless use. `AGENTNOTIFY_APP_PATH` overrides app discovery, and `AGENTNOTIFY_NO_LAUNCH=1` disables launch. No telemetry, cloud service, or inspection of other apps’ notifications.

Design sources: [Vercel design.md](https://vercel.com/design.md), [Web Interface Guidelines](https://vercel.com/design/guidelines), and the wiki’s “Vercel design guidance for native fleet apps.” Architecture decisions are [ADR 0001](docs/adr/0001-durable-inbox.md) and [ADR 0002](docs/adr/0002-semantic-interface-control.md).
