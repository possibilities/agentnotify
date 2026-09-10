# 0001 — A durable inbox with native presentation

Accepted 2026-09-08.

SQLite WAL is the source of truth. One account-local app owns a private Unix socket, transactions, AgentNotify arrival presentation, and callback execution. The CLI and stdio MCP call the same service. A headless service exists for isolated tests and non-GUI use. As of the own-arrivals-only decision, the app deliberately never projects records into macOS Notification Center.

Reading and completing are independent. Group replacement and removal retain records. Every mutation increments a revision and appends a change snapshot in the same transaction. A stable client request ID makes retries idempotent; optional expected revisions reject stale writes. This supports multiple local clients and a future authenticated sync transport without pretending a mobile backend exists today.

Responses are claimed transactionally before external effects. Effects are never replayed automatically after process loss: interrupted execution remains visible and the task stays open. Arbitrary shell execution cannot be exactly-once across crashes. Native category IDs are per-notification, preventing one prompt’s action list from overwriting another’s.

Use SwiftUI/AppKit rather than a cross-platform rendering layer: this product depends on the macOS menu bar, popover, panel, and accessibility behavior. Keep presentation monochrome and tied to system appearance. The popover and detached panel share the same view and state.

Reference: [terminal-notifier 3.1 research](https://github.com/julienXX/terminal-notifier/tree/ac959e57d059cc799af0929842fb0169ff458315). Compatibility decisions ship in [compatibility.md](../compatibility.md).
