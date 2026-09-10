---
name: notifications
description: Send, browse, and resolve durable AgentNotify inbox tasks on macOS with matching MCP, socket API, and terminal-notifier-compatible CLI. Use for completion notices, actionable prompts, replies, inbox tasks, and notification diagnosis.
---

# Notifications

Use the AgentNotify MCP for structured operations or the `agentnotify` CLI when a shell needs terminal-notifier’s argument and stdout contract. `agentnotify guide --json` is the complete schema and behavior guide. The native app owns one durable inbox for all clients.

## Send useful notifications

Write the outcome in a short title and the next useful step in the message. Notify for a meaningful completion or a need for the human’s attention; do not create a task for routine progress. Use a group tied to the exact task or conversation. A repeated group REPLACES its earlier active notification, while retaining history. Never use a broad group like `build` across unrelated tasks.

```sh
agentnotify -title 'Review ready' -message 'The notification inbox is ready to inspect.' \
  -group 'agentnotify:inbox-review' -open 'file:///absolute/path/to/review.html'
```

Equivalent MCP `send` arguments use the same field names without a leading dash:

```json
{"title":"Review ready","message":"The notification inbox is ready to inspect.","group":"agentnotify:inbox-review","open":"file:///absolute/path/to/review.html","requestId":"unique-client-generated-id"}
```

Use `execute` only for an explicitly intended body action, with absolute executable paths and safely quoted caller-owned arguments. It runs `/bin/sh -c` on this Mac. Do not interpolate untrusted content. `activate` launches/focuses a bundle; it does not know a Herdr pane or conversation. Use a verified app-specific focus command or deep link when one exists. Do not invent a focus target.

AgentNotify's own sticky arrival is the only presentation. It does not post macOS banners, sounds, categories, or Notification Center entries. The legacy `sound` and `ignoreDnD` inputs are accepted for argument compatibility but do not opt into system notification delivery.

## Choices, replies, and durable outcomes

- No actions: an informational task that can be marked done; optional body callback.
- One action: a single named button.
- Multiple actions: ordered choices in an Options menu. MCP uses an `actions` string array; legacy CLI uses repeatable `-action` or comma-separated labels.
- Reply: `reply` enables literal text input with an optional placeholder. Reply text is never shell code.

MCP/API `send` returns immediately with a stable notification ID. Read `get` later for its typed response. `respond` records an explicitly supplied human answer using `actionIndex`, `value`, or `kind: body`. Do not infer consent from a notification’s read state, dismissal, timeout, absence, or silence. Use the harness’s approval mechanism for tool approvals; notifications do not replace it.

The legacy CLI waits for `-action` or `-reply`, writes the exact answer to stdout, and exits 0. Timeout writes `@TIMEOUT` and exits 6. Close writes `@CLOSED`; a body click without handlers writes `@ACTIONCLICKED`. A body handler writes no selected label. Handle exit 6 explicitly under `set -e`. Action labels are literal caller data; they can match sentinels, so also inspect exit status. Group replacement/removal closes old waiters.

Read is separate from done. Reading never executes callbacks. The inbox does not prove that a disconnected script received an answer. A response claimed before an app crash can have an interrupted external effect; inspect the destination before taking further action. No automatic replay.

## Browse and coordinate

`list` filters inbox, unread, later, done, or all; add exact group, search query, and creation time bounds. `status` marks read/unread, done, reopen, or snooze; snooze accepts `until`, `in`, or `at`. `statusBatch` applies the same state atomically to exact ID/revision references and is the safe basis for Mark All Read. The compact arrival's Complete control performs this durable done transition for the displayed item, closes an unanswered prompt without callbacks, and advances through a burst before dismissing after its last item. `completeAll` atomically moves every active Inbox notification to Done, closes unanswered prompts without running callbacks, and leaves scheduled or snoozed notifications alone. The native Complete All command has a count-aware confirmation; its global shortcut defaults to `⌥⇧⌘D` and can be changed or cleared in Preferences. Recording requires at least two modifiers. `remove` withdraws a group or ALL while preserving history. Never remove ALL merely to clean up a test.

For concurrent clients, include a unique `requestId` on mutations and reuse it with identical input only for retries. Use the current `expectedRevision` to avoid stale writes. `changes` returns ordered snapshots after a cursor; persist that cursor and drain `hasMore` pages. This is a local multi-client contract, not a deployed mobile sync service.

## Appearance preferences

`preferences` reads the saved arrival design, Complete All shortcut, and revision. `setPreferences` changes `arrivalStyle` (`queue-peek`, `compact-toast`, or `queue-shelf`) and `completeAllShortcut`; use `null` to clear the shortcut. A shortcut object contains `keyCode`, its display `key`, and two to four unique `modifiers` drawn from `control`, `option`, `shift`, and `command`. Queue Peek and `⌥⇧⌘D` are the defaults. The retained `showBannerReminder` field is deprecated and inert: it renders no UI and cannot enable macOS presentation.

## Control the native interface

Use `uiState` to ground voice or agent interaction in the exact native surface, filters, selection, matching rows, pin state, and custom arrival. Use `uiShow`, `uiClose`, `uiSetView`, `uiNavigate`, `uiSetPinned`, `uiDismissArrival`, and `uiCopy` for semantic interface control. These tools require the GUI app; headless services return `native_unavailable`.

UI selection and navigation never mark a notification read or execute a callback. To act on “this notification,” read `uiState`, take the selected stable ID and notification revision, then call `status` or `respond` explicitly. Supply `expectedInstanceId`, `expectedUIRevision`, and `requestId` for relative or retry-sensitive UI commands. Interface state is ephemeral and separate from durable `changes`.

AgentStart exposes the full MCP in managed Codex, Claude, and AgentVoice sessions and authenticated HTTP fleet/Grok toolsets. HTTP names have the `agentnotify_` prefix, such as `agentnotify_send` and `agentnotify_preferences`; use the tools advertised by the current client. A running stdio session retains its loaded tool catalog until that session ends.

`shimStatus` checks PATH-router setup. Only when the human asks, `installShim` installs the existing AgentStart router in `~/.local/bin`; the original terminal-notifier remains the fallback. `dismissShimSetup` records that the one-time offer was handled without installing. Preferences provides the same opt-in action. Neither command changes shell profiles; `~/.local/bin` must precede the original notifier on PATH. These operations require the fleet installer owner, not a per-agent replacement script.

## Diagnose and replacement

Run `diagnose` to inspect store counts, app connection, and the AgentNotify-only presentation policy. `-list ALL` uses AgentNotify's durable active projection; `list --filter all` includes durable history, including removed and replaced records. macOS notification authorization is irrelevant because AgentNotify never requests UserNotifications delivery.

`agentnotify` is usable anywhere a script previously invoked `terminal-notifier`. The installer can optionally add a PATH-level terminal-notifier symlink; it never overwrites Homebrew or vendored binaries. Ruby callers can set `TERMINAL_NOTIFIER_BIN` to the absolute agentnotify path before loading the gem. Hardcoded paths must be changed at their owning source.

AgentStart owns fleet installation, MCP inventory, and the shared skill scan. Do not write private per-harness registries or restart AgentVoice/Herdr to advertise this tool.
