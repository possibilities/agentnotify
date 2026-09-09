# Shared notification API

`agentnotify guide --json` is the authoritative operation/parameter contract. `agentnotify --help` and MCP schemas derive from the same catalog.

Operations: send, list, get, status, respond, remove, changes, diagnose, show, heartbeat, preferences, setPreferences, showPreferences, shimStatus, installShim, dismissShimSetup. Modern CLI flags match parameter names (`--actionIndex`, `--expectedRevision`, `--requestId`). An actions value is a JSON string array. The legacy `-action` spelling remains repeatable and comma-separated.

`show detached:true` pins the inbox; `detached:false` unpins it while retaining any manual placement and keeping the menu-bar triangle hidden. Omit `detached` to preserve pin state. After an unpinned inbox closes, a fresh opening returns to the anchored popover.

The app owns a private Unix socket at `<state>/notify.sock`. Each request is one UTF-8 JSON line:

```json
{"id":"correlation-id","method":"send","params":{"message":"Build finished","requestId":"unique-operation-id"}}
```

Each response echoes id and adds `schema_version: 1`, `ok`, `data`, and `error`. Errors contain code, message, and exit_code. Request correlation id is not an idempotency key. Use params.requestId for retryable mutations: the same operation/input returns its original result; reusing it with different input fails. Keep keys unique across clients. A lost connection is an unknown result, not evidence the write failed.

The directory is 0700, the socket 0600, and accepted peers must have the same UID. Connections allow sequential newline frames, max 1 MiB per frame (notification input capped at 500 KiB and pages bounded below the frame limit), ten-second IO deadlines, and 32 concurrent connections. The service lock prevents replacing a live socket, including app/CLI startup races. This is an account-local trust boundary. Do not publish the socket directly over a network. AgentStart’s authenticated MCP gateway is the existing remote tool boundary.

Notifications include UUID id, content, ordered actions, optional callbacks, creation/update timestamps (Unix seconds), status, readAt, revision, delivery state, native registration state, and a typed response. Responses distinguish action/reply/body/close/timeout/interrupt and track callback effect running/succeeded/failed/interrupted.

`expectedRevision` gives conditional status/response mutation. A stale client gets revision_conflict and must refetch; the server does not silently overwrite a newer response. One response wins transactionally, even across simultaneous native, inbox, CLI, and MCP actions.

`changes after:0` bootstraps a client using ordered complete notification snapshots. Keep the last cursor, drain hasMore, and resume after disconnect. Apply each snapshot by ID and revision. Historical removal/supersession records remain visible, serving as tombstones. A cursor ahead of the server is rejected; initialize again when changing stores. There is no compaction or retention cutoff yet. Durable request-key retention is likewise unbounded.

A legacy CLI send adds waiterId and renews heartbeat every second. Heartbeats extend a five-second lease without changing the record revision or adding a change event. Expiry records interruption and disables stale controls. API/MCP callers normally omit waiterId and consume responses asynchronously. A heartbeat is not a read receipt or response acknowledgment.

The MCP uses newline JSON-RPC over stdio, initialize/ping/tools/list/tools/call, typed schemas, tool annotations, and structured envelopes alongside text content. It negotiates 2024-11-05, 2025-03-26, and 2025-06-18. No private per-harness registry or alternate lifecycle exists.

## App preferences

`preferences` returns `{arrivalStyle, revision}`; a new store returns `queue-peek` at revision 1. `setPreferences` accepts `arrivalStyle` (`queue-peek`, `compact-toast`, or `queue-shelf`), optional `expectedRevision`, and optional `requestId`. Writes are durable and transactional. A stale revision fails; identical request retries return their original result. A same-style write does not increase the revision. Preferences are local to this inbox service and separate from the notification change feed; clients reread `preferences` to refresh their settings.

`showPreferences` opens the native Preferences window and returns `native_unavailable` for a headless service. All three operations are available through the CLI, Unix socket, and stdio MCP. AgentStart’s authenticated fleet and Grok HTTP toolsets expose them as `agentnotify_preferences`, `agentnotify_setPreferences`, and `agentnotify_showPreferences`, alongside the full notification contract.

## Terminal-notifier integration

`shimStatus` returns installed/available booleans, the target and installer paths, and `promptHandled`. `installShim` delegates to the existing `~/code/agentstart/scripts/install-notification-shim` owner, then durably handles the setup offer. This requires AgentStart and explicit human intent; it installs the availability router into `~/.local/bin`, preserving the original fallback and refusing foreign commands. It does not edit shell profiles. `dismissShimSetup` durably handles the offer without installation. All three are CLI/socket/MCP peers, emit no notification changes, and remain separate from arrival-style revisions. An isolated `AGENTNOTIFY_STATE_DIR` also isolates the shim destination beneath `<state>/shim-home` to protect the real PATH during tests.
