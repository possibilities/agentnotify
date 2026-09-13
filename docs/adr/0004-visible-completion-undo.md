# 0004 — Visible completion with one batch Undo

Accepted 2026-09-13. Refines the completion presentation in [0001](0001-durable-inbox.md); the durable response contract is unchanged.

Move bulk completion from More to a header checkmark beside Pin. Act immediately on the active notifications matching the current view. Snapshot IDs and revisions before writing so arrivals and concurrent changes cannot broaden the action. Keep the global shortcut's separate confirmed whole-Inbox behavior.

Use the existing shared `statusBatch` operation, in transactions of at most 100 references. Record exactly the successful results as one transient Undo batch; preserve that batch if later completion transactions fail. This avoids a second lifecycle API and supports arbitrarily large inboxes without pretending the entire UI operation is atomic.

Undo reopens the exact successful IDs with their post-completion revisions. Skip and report notifications changed afterward, and retain unfinished Undo references if a transaction fails during the attempt. Never reverse an external response, replace a durable prompt closure, or change unrelated notifications. Feedback expires after the existing 60 seconds; expiry does not mutate the store.
