# AgentNotify context

**Notification** — A durable item submitted to AgentNotify, with content, optional response choices, read state, and task status. It is not a mirror of other apps’ notifications. _Avoid_: toast, message, alert as the stored entity.

**Inbox** — Active notifications requiring attention. Reading does not remove them. _Avoid_: unread queue.

**Group** — The terminal-notifier replacement key and a browsing filter. Reusing a nonempty group supersedes its earlier active item; history remains. _Avoid_: folder, authenticated source.

**Response** — One durable resolution of the interaction: action, reply, body, close, timeout, or interruption. A response does not prove a disconnected script received stdout. _Avoid_: approval, receipt unless actually established.

**Change** — A monotonically sequenced snapshot committed with each notification mutation. Clients resume from a cursor and use revisions for conditional writes. _Avoid_: cloud sync (there is no remote sync service yet).
