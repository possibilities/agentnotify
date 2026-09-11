# 0003 — One native panel and native status-button selection

Accepted 2026-09-11. Supersedes the two-window presentation and invisible positioning window in ADR 0002; preserves its stable geometry and pinning requirements.

Use one borderless, nonactivating `NSPanel` with one hosting controller for both pinned and unpinned inbox presentation. Pinning changes dismissal policy without moving or reparenting content. A fresh unpinned opening projects the real status-button rectangle inside the nearest screen and positions the panel below it. No invisible status-level window participates in presentation. The open panel stays stationary across menu-bar auto-hide and repeated show requests.

Keep the native `NSStatusBarButton` intact. Set `isHighlighted` synchronously after opening and reassert it on the next main-queue turn; clear it after ordering the panel out. Count refreshes must not set selection: opening refreshes while the button is pressed but the panel is still hidden. An opening generation prevents deferred selection from surviving a close. Do not draw a second selection capsule or insert siblings into AppKit's status-button hierarchy. Native AppKit owns pressed/selected geometry, color, and accessibility.

An anchored unpinned inbox retains its upward pointer. Reserve a 12-point strip above the body in both pin states so hiding the pointer on pin does not move the content. Sample its horizontal anchor on opening, clamp away from the rounded corners, and hide it after manual dragging. A fresh unpinned opening restores it.

The exact status button's primary press/release events are handled locally while its native renderer remains intact. AppKit's default momentary tracker clears selection for a frame at mouse-up, so reasserting selection asynchronously alone is insufficient. Release inside toggles, release outside cancels, and Command-drag passes through for native rearrangement. Accessibility activation retains the normal target/action path. A global mouse-up observer clears a cancelled press released outside the app.

Unpinned dismissal has separate paths for loss of key status, outside mouse-down, and pointer-exit grace. A global mouse-down monitor covers another app's menu extra even when that app does not activate or become key. The inbox's own status-button click owns its toggle. Pinning disables automatic dismissal. Local menus, editing and sheets keep their normal input behavior; a protected sheet is not dismissed by the outside-click handler.

Source references inspected at implementation time: Maccy `c376789` (`FloatingPanel.swift`, native selection and resign-key lifecycle), Itsycal `8d7676d` (`ViewController.m`, pin-aware resign-key dismissal), Stats `4759b1e` (`Kit/module/popup.swift`, locked-window exception), Pika `4edac16` and OnlySwitch `0d8a6c7` (direct status-button anchoring / outside-click handling). These are architectural references, not vendored code.

Interface snapshots now report `presentation: panel` for every visible inbox; `pinned` remains the authoritative lifetime policy. Durable notifications and CLI/MCP actions are unchanged.
