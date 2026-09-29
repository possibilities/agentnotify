#if DEBUG
import AppKit
import Carbon.HIToolbox
import NotifyCore

enum GlobalShortcutChecks {
    static func run() throws -> [String] {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NotifyError("internal_error", message) }
        }
        func event(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
            guard let value = NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: keyCode) else {
                throw NotifyError("internal_error", "Could not create shortcut test event.")
            }
            return value
        }

        let recorder = ShortcutCaptureNSView()
        var captured: GlobalShortcut?
        var captureCalled = false
        var cancelled = false
        recorder.captured = { captured = $0; captureCalled = true }
        recorder.cancelled = { cancelled = true }

        recorder.recording = true
        recorder.keyDown(with: try event(keyCode: UInt16(kVK_Escape), modifiers: [.control, .command]))
        try require(captureCalled && captured == GlobalShortcut(keyCode: Int(kVK_Escape), key: "⎋", modifiers: ["control", "command"]),
            "Modified Escape was treated as cancellation instead of a shortcut.")

        captured = nil; captureCalled = false; cancelled = false; recorder.recording = true
        recorder.keyDown(with: try event(keyCode: UInt16(kVK_Escape), modifiers: []))
        try require(cancelled && !captureCalled, "Bare Escape did not cancel shortcut recording.")

        cancelled = false; recorder.recording = true
        recorder.keyDown(with: try event(keyCode: UInt16(kVK_Delete), modifiers: []))
        try require(captureCalled && captured == nil && !cancelled, "Bare Delete did not clear the shortcut.")

        let complete = GlobalShortcutController(id: 91), show = GlobalShortcutController(id: 92)
        var completions = 0, openings = 0
        complete.action = { completions += 1 }; show.action = { openings += 1 }
        func dispatch(_ hotKey: GlobalShortcutController) throws {
            var event: EventRef?
            guard CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                              GetCurrentEventTime(), 0, &event) == noErr, let event else {
                throw NotifyError("internal_error", "Could not create hotkey event.")
            }
            defer { ReleaseEvent(event) }
            var identifier = hotKey.identifier
            try require(SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                          MemoryLayout<EventHotKeyID>.size, &identifier) == noErr,
                        "Could not assign hotkey identity.")
            try require(SendEventToEventTarget(event, GetApplicationEventTarget()) == noErr, "Hotkey dispatch failed.")
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        try dispatch(complete)
        try require(completions == 1 && openings == 0, "Complete All also invoked Show Inbox.")
        try dispatch(show)
        try require(completions == 1 && openings == 1, "Show Inbox also invoked Complete All.")
        return ["modified Escape can be assigned", "bare Escape cancels", "bare Delete clears", "Carbon hotkeys route to their own actions"]
    }
}
#endif
