# 0002 — Semantic interface control beside the durable notification contract

Accepted 2026-09-09.

AgentNotify exposes two capability planes from one account-local service. Notification operations change durable meaning in SQLite and work headlessly. Interface operations control transient native presentation and require the GUI app. They share validation, socket, CLI, MCP, and authenticated fleet routing; there is no second store or UI-only business logic.

Notification mutations always target stable IDs. Single-item writes can use `expectedRevision`; `statusBatch` accepts exact ID/revision references and commits all changes or none. Reading, completion, snoozing, responses, and callback activation remain explicit. Interface selection and navigation never imply a durable read or response.

The interface API is semantic rather than coordinate-based. It can inspect UI state, show or close surfaces, set inbox filters and selection, navigate, pin, dismiss the custom arrival, and copy notification content. Each snapshot carries an app-launch `instanceId` and in-memory `uiRevision`. Relative or retry-sensitive commands can supply both, plus `requestId`, so an app restart, concurrent human interaction, or uncertain transport does not silently redirect a command.

Interface operations return their resulting snapshot after AppKit applies the command. They do not enter the durable notification change feed. Headless services return `native_unavailable`. Existing `show` and `showPreferences` remain compatibility aliases. One MCP exposes both planes with `ui`-prefixed tools; future data-only or UI-focused MCP registrations may be allowlisted projections of this same catalog, never separate implementations.

Generic pixel clicks and application termination are intentionally excluded. Body callbacks remain behind the explicit durable `respond kind: body` operation; selecting, revealing, or opening notification details cannot execute them.
