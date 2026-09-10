# Verification

Final acceptance target: macOS 26.5.2, arm64, Swift 6.3.3 Command Line Tools, September 10, 2026. Automated checks always use disposable stores and services; they never use the installed inbox.

## Final pass

September 10 final results before the clean-checkout installer pass:

- `swift run NotifyCoreChecks`: **passed, 37 checks**. Coverage includes durable completion, prompt closure without callbacks, preference migration, the default `⌥⇧⌘D` shortcut, assignment and clearing, malformed-shortcut rejection, post-marker legacy-state normalization, nested cached-batch normalization, and the retired banner field remaining inert.
- `python3 scripts/test-integration.py`: **passed, 384 assertion executions in the final run**. Coverage includes matching CLI/socket/MCP behavior, durable send acceptance without system registration, durable legacy list projections, Complete All, and shortcut preference parity. The exact assertion count can vary slightly with polling iterations.
- `python3 scripts/test-interface.py`: **passed, 55 checks**. Coverage includes sticky arrival state, explicit dismissal without durable mutation, and semantic native-interface control.
- `.build/debug/agentnotify check-arrivals <disposable-directory>`: **passed**. Coverage includes one latest-only nonactivating panel, useful unread/waiting summaries, persistence until action, stable pressed identity, failed-completion retention, prompt completion without effects, burst advancement, and final-item dismissal.
- `.build/debug/agentnotify check-shortcut`: **passed, 3 checks**. Modified Escape is assignable, bare Escape cancels, and bare Delete clears. Actual Carbon registration must also be checked in the installed app because another process can own a combination at runtime.
- `.build/debug/agentnotify check-feedback`: **passed, 5 checks**. Coverage includes individual completion feedback, Undo, and Complete All affecting only the active Inbox.
- `.build/debug/agentnotify check-hover`: **passed, 9 checks**. Existing full-inbox hover dismissal remains independent of sticky arrival-preview behavior.
- `scripts/build.sh`: **passed**. Light and dark production renders cover all three arrival styles, the compact Complete control, the `⌥⇧⌘D` default in Preferences, and the absence of banner/authorization/System Settings messaging.
- `python3 scripts/test-install.py`: **passed from a clean committed checkout**. It covered foreign-file preservation, clean install, legacy aliasing, running-app convergence/refusal, live MCP preservation, the signed source revision, and the deployed-SHA receipt. Final delivery must still verify that local `main`, the installed receipt, and the running executable identify the delivery commit.

## Acceptance criteria

- AgentNotify's sticky preview is the sole arrival presentation. Sends are recorded as `accepted` with `nativeRegistered: false`; the app does not request notification authorization or create macOS banners, notification sounds, categories, or Notification Center entries. Launch cleanup withdraws projections left by earlier AgentNotify builds without requesting permission.
- Arrivals reuse one panel, show the latest item, and remain until explicitly dismissed, opened, or completed. The footer distinguishes unread notifications from read items that still need attention.
- The preview's Complete activator performs the durable `status done` transition for the displayed identity. Completing an unanswered prompt records close before effects and runs no callback. A successful completion advances within the current burst or dismisses after its final item; failure leaves the item visible.
- More → Complete All and the global shortcut open the same count-aware confirmation. The default is `⌥⇧⌘D`; Preferences can replace or clear it, recording requires at least two modifiers, and no shortcut silently completes the Inbox.
- Mark All Read remains distinct from completion. Complete All is atomic, leaves scheduled and snoozed notifications alone, and closes unanswered prompts without running actions or body callbacks.
- CLI, Unix socket, and MCP remain peers. Terminal-notifier-compatible noninteractive sends succeed on durable acceptance, and legacy `-list ALL`/`-list PENDING` report durable AgentNotify projections rather than UserNotifications state.

## Manual boundaries

No test should post a real system notification or mutate the real inbox. Physical multi-display placement, VoiceOver navigation, login-session shortcut conflicts, distribution signing, and notarization remain manual checks. The installed-app acceptance check may verify that obsolete AgentNotify Notification Center entries are removed, but it must not create replacements.
