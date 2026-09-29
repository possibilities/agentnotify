# 0006 — Two global shortcuts with visible-only completion

Accepted 2026-09-29. Narrows the global shortcut in [0005](0005-centered-surfaces-and-direct-shortcut.md): it no longer completes a hidden Inbox. The durable `completeAll` service operation remains available to CLI, socket, and MCP callers regardless of UI visibility.

Register a second, independently configurable Carbon hotkey to show the inbox from any app. New and nonconflicting migrated preferences default to `⌥⇧⌘I`; `⌥⇧⌘D` remains Complete All. A saved `null` means disabled. Reject identical physical key/modifier combinations across the two settings so one key cannot trigger two actions. Route Carbon events by their hotkey identity rather than running every installed handler for every event. Showing the inbox never reads or completes a notification.

The Complete All hotkey is active only while the arrival preview or inbox is visible. When neither is visible, do not even refresh the inbox for completion. When visible, keep the whole-Inbox scope independent of the current filter and dismiss the visible arrival or inbox after successful completion; Undo remains available on reopening. This prevents an invisible destructive operation while preserving an explicit API operation for automation.
