# Shared notification API

`agentnotify guide --json` is the authoritative operation/parameter contract. `agentnotify --help` and MCP schemas derive from the same catalog.

Operations: send, list, get, status, respond, remove, changes, diagnose, show, heartbeat. Modern CLI flags match parameter names (`--actionIndex`, `--expectedRevision`, `--requestId`). An actions value is a JSON string array. The legacy `-action` spelling remains repeatable and comma-separated.

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
