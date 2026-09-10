# 0003 — AgentNotify owns arrival presentation

Accepted 2026-09-10.

AgentNotify's compact arrival and durable Inbox are the only notification
presentation surfaces. The app never requests authorization for, schedules,
or delivers macOS Notification Center banners, alerts, sounds, categories, or
actions. On a normal installed launch it removes delivered and pending requests
created by earlier AgentNotify releases without requesting authorization.

This is a product boundary, not a fallback preference. System banners duplicate
AgentNotify's richer durable workflow, are transient, and can be suppressed by
Focus or session conditions. No interface or guidance should promote enabling
them. The legacy `showBannerReminder` preference remains accepted and encoded
only for wire compatibility; it is false by default and has no behavior.

New notifications are accepted by the AgentNotify store immediately. The
retained delivery fields describe that acceptance for compatible clients;
`nativeRegistered` remains false. Legacy terminal-notifier list and removal
commands operate on the durable projection. Sound and time-sensitive inputs are
accepted as compatibility metadata but do not create a system presentation.

Explicit actions, replies, completion, and callbacks remain available through
AgentNotify's own surfaces and shared service contract. Reading stays distinct
from completion, and opening details never executes a callback.
