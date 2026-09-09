# AgentNotify

Native macOS notification inbox. SwiftUI renders content, AppKit owns the menu bar and panel, UserNotifications owns system delivery. No WebView.

Read CONTEXT.md and docs/adr/0001-durable-inbox.md before changing notification lifecycle or delivery. `swift run NotifyCoreChecks` verifies the store/contract; `scripts/test-integration.py` verifies CLI/socket/MCP against an isolated headless service; `scripts/build.sh` packages the app. Never use the real inbox for automated tests.

Every behavior belongs to the shared service contract; CLI and MCP are peers. Preserve terminal-notifier 3.1 spellings, stdout, and exit status unless docs/compatibility.md explicitly describes a difference. Reading is not completion. Opening details never executes callbacks. Persist responses before effects; never automatically retry an uncertain external effect.

Shared fleet installation and MCP inventory belong to ~/code/agentstart. Skills under skills/ are discovered by its sync path. Update its skills/fleet/MAP.md when cross-tool edges change. General agent doctrine belongs to ~/code/agentguidance. Do not restart an active installed app as part of a build.
