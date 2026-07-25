# ADR 0001: Keep notification ownership in one standalone CLI boundary

- Status: Accepted
- Date: 2026-07-25

## Decision

One standalone `agentnotify` CLI boundary owns desktop delivery, optional phone delivery, and persisted notification history. Dismiss and close remain separate operations: dismiss changes the history record, while close addresses a visible grouped notification.

Local installation links `~/.local/bin/agentnotify` directly to the Bun source executable in the checkout. There is no resident service.

## Consequences

Callers depend on one product identity and one history contract instead of coordinating delivery backends themselves. The direct source link makes checkout updates immediately active and keeps the Bun version a host prerequisite. Moving the checkout can break the link, and changing the process or persistence boundary later requires an explicit migration.
