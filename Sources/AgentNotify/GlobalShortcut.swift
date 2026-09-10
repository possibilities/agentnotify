import AppKit
import Carbon.HIToolbox
import SwiftUI
import NotifyCore

private let completeAllHotKeySignature: OSType = 0x414E4341 // ANCA

private func completeAllHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let controller = Unmanaged<GlobalShortcutController>.fromOpaque(userData).takeUnretainedValue()
    controller.invoke()
    return noErr
}

/// Registers one app-owned Carbon hot key without requiring Accessibility
/// permission. A failed replacement restores the previously working shortcut.
final class GlobalShortcutController {
    var action: (() -> Void)?
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var eventHandlerStatus: OSStatus = noErr
    private(set) var current: GlobalShortcut?

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        eventHandlerStatus = InstallEventHandler(GetApplicationEventTarget(), completeAllHotKeyHandler, 1, &type,
            Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    func apply(_ shortcut: GlobalShortcut?) -> String? {
        guard shortcut != current else { return nil }
        if let shortcut, !shortcut.isValid { return "That saved shortcut is invalid. Record it again." }
        let previous = current
        unregister()
        guard let shortcut else { return nil }
        guard eventHandlerStatus == noErr else {
            if let previous, register(previous) == noErr { current = previous }
            return "macOS could not prepare the global shortcut handler (error \(eventHandlerStatus))."
        }
        let status = register(shortcut)
        guard status != noErr else { current = shortcut; return nil }
        // Carbon does not promise an output reference on failure. Clear it
        // before trying to restore the last known-good registration.
        hotKey = nil
        if let previous, register(previous) == noErr { current = previous }
        if status == OSStatus(eventHotKeyExistsErr) { return "That shortcut is already in use. Try another combination." }
        return "macOS could not register that global shortcut (error \(status))."
    }

    fileprivate func invoke() {
        DispatchQueue.main.async { [weak self] in self?.action?() }
    }

    private func register(_ shortcut: GlobalShortcut) -> OSStatus {
        let identifier = EventHotKeyID(signature: completeAllHotKeySignature, id: 1)
        return RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, identifier,
            GetApplicationEventTarget(), 0, &hotKey)
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        current = nil
    }

    deinit {
        unregister()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

extension GlobalShortcut {
    fileprivate static let shortcutModifierFlags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    var displayName: String {
        let symbols = ["control": "⌃", "option": "⌥", "shift": "⇧", "command": "⌘"]
        return modifiers.compactMap { symbols[$0] }.joined() + key
    }

    fileprivate var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains("control") { value |= UInt32(controlKey) }
        if modifiers.contains("option") { value |= UInt32(optionKey) }
        if modifiers.contains("shift") { value |= UInt32(shiftKey) }
        if modifiers.contains("command") { value |= UInt32(cmdKey) }
        return value
    }

    static func capture(_ event: NSEvent) -> GlobalShortcut? {
        let flags = event.modifierFlags.intersection(shortcutModifierFlags)
        var modifiers: [String] = []
        if flags.contains(.control) { modifiers.append("control") }
        if flags.contains(.option) { modifiers.append("option") }
        if flags.contains(.shift) { modifiers.append("shift") }
        if flags.contains(.command) { modifiers.append("command") }
        guard modifiers.count >= 2 else { return nil }
        return GlobalShortcut(keyCode: Int(event.keyCode), key: keyLabel(event), modifiers: modifiers)
    }

    private static func keyLabel(_ event: NSEvent) -> String {
        let special: [UInt16: String] = [
            UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥", UInt16(kVK_Space): "Space",
            UInt16(kVK_Delete): "⌫", UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Escape): "⎋",
            UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→", UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
            UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
            UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
            UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15", UInt16(kVK_F16): "F16",
            UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18", UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20"
        ]
        if let value = special[event.keyCode] { return value }
        let value = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "Key \(event.keyCode)" : value.uppercased()
    }
}

final class ShortcutCaptureNSView: NSView {
    var recording = false {
        didSet {
            guard recording, oldValue != recording else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.recording else { return }
                self.window?.makeFirstResponder(self)
            }
        }
    }
    var captured: ((GlobalShortcut?) -> Void)?
    var cancelled: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        let shortcutModifiers = event.modifierFlags.intersection(GlobalShortcut.shortcutModifierFlags)
        if event.keyCode == UInt16(kVK_Escape), shortcutModifiers.isEmpty { finish(cancelled); return }
        if [UInt16(kVK_Delete), UInt16(kVK_ForwardDelete)].contains(event.keyCode),
           shortcutModifiers.isEmpty {
            finish { self.captured?(nil) }; return
        }
        guard let shortcut = GlobalShortcut.capture(event) else { NSSound.beep(); return }
        finish { self.captured?(shortcut) }
    }

    private func finish(_ completion: (() -> Void)?) {
        recording = false
        window?.makeFirstResponder(nil)
        completion?()
    }
}

struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var recording: Bool
    let captured: (GlobalShortcut?) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView { ShortcutCaptureNSView() }
    func updateNSView(_ view: ShortcutCaptureNSView, context: Context) {
        view.captured = { shortcut in
            recording = false
            captured(shortcut)
        }
        view.cancelled = { recording = false }
        view.recording = recording
    }
}
