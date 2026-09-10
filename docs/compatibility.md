# Terminal-notifier 3.1 compatibility

AgentNotify targets the observable 3.1 CLI contract. This is not a claim of byte-for-byte equivalence for every undocumented NSUserDefaults parsing quirk or OS presentation.

| Contract | AgentNotify behavior |
|---|---|
| `-message`, stdin | Nonempty UTF-8; piped trailing CR/LF trimmed; one leading backslash removed from legacy flag values |
| `-title`, `-subtitle` | Preserved; title defaults to Terminal |
| `-group` | Exact replacement key; earlier active/scheduled item superseded, retained in history |
| `-sound` | default or named sound; system settings apply |
| `-contentImage` | Local file/file URL; copied before attachment; failure warns without losing inbox item |
| `-execute`, `-open`, `-activate` | Explicit body callbacks, ordered activate → shell command → URL; action buttons do not run them |
| `-action` | Repeated flags and comma splitting; trim whitespace, discard empty parts, preserve order/duplicates; exact selected label on stdout |
| `-reply [placeholder]` | Optional placeholder; literal reply on stdout |
| `-timeout` | Positive seconds; `@TIMEOUT` plus newline, exit 6; durable task remains active with stale controls disabled |
| `-in`, `-at` | One-shot native scheduling; disallow actions/replies or both scheduling flags; local clock/date parsing |
| `-list ALL`, group | Actual native delivered IDs, five-column TSV; empty output has no header |
| `-list PENDING` | Actual native pending IDs, ascending due time, Scheduled For column |
| `-remove`, with optional message | Withdraw before send; retained history; no stdout |
| `-sender`, `-appIcon` | Accepted, warned, ignored, matching version 3 |
| `-ignoreDnD` | Requests time-sensitive presentation, never a promised Focus bypass |
| `-help`, `-version`, `-diagnose` | Help/legacy compatibility version/structured diagnosis; `--version` reports actual product version |
| SIGINT, SIGTERM, SIGHUP | Waiting CLI records interruption, exits 6, no stdout sentinel |

## Intentional differences

- Durable storage is primary. Disabled/failed native delivery does not delete the item. Legacy sends still report native denial (3), watchdog expiry (4), or failure (5); modern send acknowledges durable acceptance and exposes delivery separately through get/changes.
- The GUI always presents one compact, nonactivating arrival preview. It stays until dismissed or opened, updates to the latest arrival without stacking panels, and summarizes unread notifications plus read items that still need attention. Preview dismissal is not a terminal-notifier close response. Clicking it reads the displayed item without executing its body callback. Optional system banners may appear alongside it when enabled; a banner body click opens the item in AgentNotify without executing its callback, while explicit native action and reply controls retain their response behavior. Native `delivery` and legacy exit codes continue to describe native delivery, not the AgentNotify arrival projection.
- Replacement/removal deterministically closes prior waiters with `@CLOSED`. Upstream behavior is not reliably specified for these races.
- A killed legacy process loses its five-second heartbeat lease; the task remains, but its old interactive response cannot be sent to a nonexistent stdout consumer. Asynchronous API/MCP prompts have no lease unless explicitly requested.
- Timeout retains the task, marks its response expired, and withdraws native presentation. Snoozing does not revive a finished script. Completion/reopen changes task state, never replays effects or reopens a resolved interaction.
- Strict typed validation rejects unknown arguments, nonfinite numbers, malformed combinations, and oversized input. Durations are limited to 10 years, action count to 100, each label to 4 KiB, other strings to 64 KiB, and total notification input to 500 KiB. This deliberately does not emulate obscure NSUserDefaults coercions.
- Native macOS categories expose at most the first ten actions including Reply; the custom Options menu retains all accepted actions. Native banners vs alerts and button geometry are controlled by macOS.
- AgentNotify has its own bundle, icon, authorization, and stored history. It cannot list or remove terminal-notifier’s existing native notifications or other apps’ notifications.
- Scheduled records use native triggers and a durable due time. The app catches overdue inbox state up on wake/relaunch. Cross-time-zone/DST behavior and reboots require device-level qualification; no cross-device scheduling guarantee is claimed.
- Headless serve has durable semantics but no native banners. Its legacy list uses the durable projection, and send warns on stderr. GUI use launches the app automatically when the installed default socket is absent.
- Handler stdout/stderr are discarded; completion/failure is recorded. An uncertain crash is never automatically retried. Environment/cwd replay is not promised.

`-version` reports the supported terminal-notifier contract for drop-in consumers; `--version` and diagnose identify AgentNotify. A PATH alias does not redirect absolute or vendored binaries. No system executable is overwritten.
