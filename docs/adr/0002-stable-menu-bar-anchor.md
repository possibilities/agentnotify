# 0002 — Preserve the inbox position across pinning

Accepted 2026-09-09.

Pinning changes the inbox's lifetime without moving its content or rearranging its controls. Use the hosting view's screen rectangle when moving it between a native NSPopover and a floating NSPanel; their outer window frames include different margins. The panel explicitly remains visible on app deactivation. Dragging the blank header moves the panel freely; unpinning returns it to the current menu-bar anchor.

On macOS 26.5.2 with menu-bar auto-hide, the status item's window moves above the display and its screen becomes nil. Anchoring NSPopover directly to it produced a far-left fallback position and a malformed pointer. Use a transparent, noninteractive positioning window projected inside the nearest screen's safe top edge. AppKit continues to draw and position the actual popover. Recreate the popover after panel use to discard cached content and positioning geometry; retain the same hosting controller and model.

Amended 2026-09-09: remove auto-hide tracking in both modes. The earlier 100ms timer followed the menu bar to preserve its relationship to the inbox, but the movement did not improve browsing. This supersedes that tracking behavior while retaining the safe opening anchor and all pin/unpin positioning fixes. Each surface stays where placed, including when an already-visible inbox is shown again. Closing hides the positioning window. Geometry checks exercise hidden, revealed, notched, and negative-coordinate anchors; actual pin/unpin cycles verify content continuity. Physical multi-display and notch hardware behavior still needs device coverage.
