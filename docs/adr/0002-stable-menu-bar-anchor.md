# 0002 — Preserve the inbox position across pinning

Accepted 2026-09-09.

Pinning changes the inbox's lifetime without moving its content or rearranging its controls. Use the hosting view's screen rectangle when moving it between a native NSPopover and a floating NSPanel; their outer window frames include different margins. The panel explicitly remains visible on app deactivation. Dragging the blank header releases its menu-bar anchor; unpinning returns it to that anchor.

On macOS 26.5.2 with menu-bar auto-hide, the status item's window moves above the display and its screen becomes nil. Anchoring NSPopover directly to it produced a far-left fallback position and a malformed pointer. Use a transparent, noninteractive positioning window projected inside the nearest screen's safe top edge. AppKit continues to draw and position the actual popover. Recreate the popover after panel use to discard cached content and positioning geometry; retain the same hosting controller and model.

AppKit exposes no menu-bar reveal notification. While the inbox is visible, a 100ms timer with tolerance follows the status item's effective rectangle. Closing stops tracking and hides the positioning window. This introduces no preference changes or visible chrome. Geometry checks exercise hidden, revealed, notched, and negative-coordinate anchors; actual pin/unpin cycles verify content continuity. Physical multi-display and notch hardware behavior still needs device coverage.
