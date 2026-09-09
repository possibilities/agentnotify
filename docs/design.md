# Native notification inbox design

The person opens this panel to decide what still needs attention and take the next action. Content, read state, and completion lead; product identity and transport status do not occupy a rail.

## Visual language

A continuous semantic window surface, SF system typography, and grayscale controls. System appearance selects light and dark automatically. A functional category menu, count, search, filters, and a detach control occupy the top. Notification rows share a title/body/metadata/action alignment without enclosing cards. The selected row gets a subtle surface; every other boundary must earn its space.

Type roles: 20-point semibold category, 13-point semibold titles, 13-point regular body, 11-point metadata. Outer inset 20 points, row inset 10, restrained 6-point control radii, 28-point icon targets. Default popover 440 × 610; the detached panel supports 360–700-point widths. Use semantic colors, never fixed light/dark overrides in production. Relative dates omit ticking seconds.

## Behavior

Inbox, Unread, Later, Done, and All are status views. Search matches title, subtitle, message, and group. Group filtering is exact; time filters use creation time. Long content expands in place. Reading does not complete or execute a callback. Completion offers undo, and a native context/menu surface carries less frequent operations.

One action is a button; multiple actions form an Options menu; a reply expands an inline field. Explicit body callbacks have a distinct Open, Open App, or Run Action control. Their target is inspectable in details. A notification without a supplied action gets no fabricated primary action.

The popover and detached panel reuse one hosting controller and model. Hiding a window never changes task state. API/MCP `show` can select a notification and choose detached presentation.

Pinning preserves the content's screen coordinates and the toolbar's control positions. The pinned panel stays visible over other apps, without the popover pointer. Both presentations stay where placed; neither follows menu-bar auto-hide. The panel uses a transparent borderless window with a continuous 20-point corner to match the popover body. Drag the blank header area to place it independently. Once moved, unpinning keeps that window, position, and triangle-free outline; it only enables hover dismissal. Closing an unpinned window and opening it again restores the anchored popover. An untouched panel still returns to the tray when unpinned. Close lives in More in both presentations. The native popover uses an invisible anchor kept within its display because macOS can move an auto-hidden status window off-screen. See [the positioning decision](adr/0002-stable-menu-bar-anchor.md).

Opening a panel does not automatically focus the category menu. Pointer input clears control focus while preserving an active text editor. Tab and keyboard menu navigation retain native focus indication; VoiceOver retains native focus behavior. Do not suppress every focus ring to make a surface quieter.

An unpinned inbox stays open under the pointer, whether it is an anchored popover or a manually placed panel. After the pointer leaves the popover and tray icon, it dismisses after one second; returning cancels the countdown. Opening from the CLI or API does not start a countdown until the pointer has visited. Native menus pause dismissal, while text editing, keyboard navigation, and VoiceOver keep it open. A pinned panel never dismisses on pointer exit. This uses pointer enter/exit events and a one-shot delay, with no position tracking.

## References and verification

[Vercel design.md](https://vercel.com/design.md) supplies transferable composition and restraint guidance, not Vercel branding for this app. [Web Interface Guidelines](https://vercel.com/design/guidelines) inform native keyboard, focus, label, contrast, and state handling. The wiki’s “Vercel design guidance for native fleet apps” records the adaptation and links the fleet’s chromeless guidance.

Debug `render-previews` renders the production view in both appearances and narrow empty/search states. The native panel self-check exercises actual popover opening, shared-view detachment, durable read state, reattachment, and closing against an isolated store. These tests do not establish system banner button geometry or permission behavior across macOS releases.
